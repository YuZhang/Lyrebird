import Foundation

enum RecordingSessionAction {
    case begin(metadata: TrackMetadata, sampleRate: Int)
    case finish(completed: Bool, register: TrackMetadata?)
    case pause
    case resume
    case restart
    case log(String)
}

struct RecordingSession {
    enum Phase {
        case idle
        case waitingForPlayback
        case waitingForFormat
        case waitingForRestart
        case recording
        case paused
        case completed
        case skipped
    }

    private(set) var phase = Phase.idle
    var status = "准备就绪"
    var currentFileName = "尚未创建音频文件"
    var observedTrackID: String?
    var writingTrackID: String?
    var writingTrack: TrackMetadata?
    var writingSampleRate = 0
    var restartedForHigherRateTrackID: String?
    var awaitingRestartTrackID: String?
    var pausedTrackID: String?
    var skippedTrackID: String?
    var previousPosition: Double?
    var previousDuration = 0.0

    mutating func process(
        snapshot: MusicPlayerSnapshot,
        isDuplicate: Bool,
        recordingStartPosition: Double,
        restartsForHigherSampleRate: Bool
    ) -> [RecordingSessionAction] {
        var actions: [RecordingSessionAction] = []

        if snapshot.state == .playing, let track = snapshot.track {
            let trackChanged = snapshot.trackID != observedTrackID
            let trackRestarted = awaitingRestartTrackID == snapshot.trackID || (!trackChanged
                && previousPosition != nil
                && snapshot.position < previousPosition! - 1.5)

            if trackChanged || trackRestarted {
                awaitingRestartTrackID = nil
                let previousWasComplete = RecordingCompleteness.completedBeforeChange(
                    duration: previousDuration,
                    position: previousPosition
                )
                if writingTrackID != nil {
                    actions.append(.finish(
                        completed: previousWasComplete,
                        register: previousWasComplete ? writingTrack : nil
                    ))
                    writingTrackID = nil
                    writingTrack = nil
                    writingSampleRate = 0
                }

                let firstObservation = observedTrackID == nil
                observedTrackID = snapshot.trackID
                skippedTrackID = nil
                if isDuplicate {
                    skippedTrackID = snapshot.trackID
                    phase = .skipped
                    actions.append(.log("歌曲已存在，已跳过：\(track.displayText)"))
                    currentFileName = "文件夹中已有此歌曲，未重复录制"
                    status = "歌曲已存在，已跳过"
                } else if firstObservation && !trackRestarted && !RecordingCompleteness.canStart(at: recordingStartPosition) {
                    phase = .waitingForPlayback
                    currentFileName = "当前歌曲未从头录制"
                    status = "等待下一首自动开始…"
                } else if snapshot.sampleRate <= 0 {
                    phase = .waitingForFormat
                    actions.append(.log("无法确认采样率，未录制：\(track.displayText)"))
                    currentFileName = "采样率未知，未录制"
                    status = "等待下一首自动开始…"
                } else if !RecordingCompleteness.canStart(at: snapshot.position),
                          restartedForHigherRateTrackID != snapshot.trackID {
                    restartedForHigherRateTrackID = snapshot.trackID
                    awaitingRestartTrackID = snapshot.trackID
                    phase = .waitingForRestart
                    actions.append(.restart)
                    actions.append(.log("采样率确认为 \(snapshot.sampleRate) Hz，从头开始录制"))
                    currentFileName = "采样率已确认，从头开始录制"
                    status = "正在从头录制…"
                    previousPosition = snapshot.position
                    previousDuration = snapshot.duration
                    return actions
                } else {
                    phase = .recording
                    actions.append(.begin(metadata: track, sampleRate: snapshot.sampleRate))
                    writingTrackID = snapshot.trackID
                    writingTrack = track
                    writingSampleRate = snapshot.sampleRate
                    currentFileName = "等待 Apple Music 音频…"
                    status = "正在自动录音"
                }
            } else {
                if pausedTrackID == snapshot.trackID {
                    actions.append(.resume)
                    pausedTrackID = nil
                    phase = .recording
                    currentFileName = writingTrack?.fileTitle ?? currentFileName
                    status = "正在自动录音"
                    actions.append(.log("恢复播放，继续录制：\(track.displayText)"))
                }
                if restartsForHigherSampleRate,
                   writingTrackID == snapshot.trackID,
                   restartedForHigherRateTrackID != snapshot.trackID,
                   writingSampleRate > 0,
                   snapshot.sampleRate > writingSampleRate {
                    restartedForHigherRateTrackID = snapshot.trackID
                    awaitingRestartTrackID = snapshot.trackID
                    phase = .waitingForRestart
                    actions.append(.restart)
                    actions.append(.finish(completed: false, register: nil))
                    actions.append(.log("检测到采样率提升（\(writingSampleRate) Hz → \(snapshot.sampleRate) Hz），从头重录"))
                    writingTrackID = nil
                    writingTrack = nil
                    writingSampleRate = 0
                    currentFileName = "高解析版本已就绪，从头重录"
                    status = "正在从头重录高解析版本…"
                    previousPosition = snapshot.position
                    previousDuration = snapshot.duration
                    return actions
                }
                if writingTrackID == nil {
                    if skippedTrackID == snapshot.trackID {
                        currentFileName = "文件夹中已有此歌曲，未重复录制"
                        status = "歌曲已存在，已跳过"
                    } else {
                        currentFileName = "等待下一首歌曲"
                        status = "等待下一首自动开始…"
                    }
                }
            }

            if writingTrackID == snapshot.trackID,
               RecordingCompleteness.reachedEnd(
                duration: snapshot.duration,
                position: snapshot.position
               ) {
                actions.append(.finish(completed: true, register: writingTrack))
                writingTrackID = nil
                writingTrack = nil
                writingSampleRate = 0
                phase = .completed
                currentFileName = "完整音轨已保存"
                status = "等待下一首自动开始…"
            }
            previousPosition = snapshot.position
            previousDuration = snapshot.duration
        } else {
            previousPosition = nil
            previousDuration = 0

            if snapshot.state == .paused {
                if writingTrackID != nil && writingTrackID != snapshot.trackID {
                    actions.append(.finish(completed: false, register: nil))
                    writingTrackID = nil
                    writingTrack = nil
                    writingSampleRate = 0
                    pausedTrackID = nil
                }
                if writingTrackID != nil {
                    actions.append(.pause)
                    pausedTrackID = writingTrackID
                    phase = .paused
                }
                currentFileName = pausedTrackID == snapshot.trackID ? "已暂停，恢复后继续" : "暂停期间不写入音频"
                status = "播放已暂停"
            } else {
                if writingTrackID != nil {
                    actions.append(.finish(completed: false, register: nil))
                    writingTrackID = nil
                    writingTrack = nil
                    writingSampleRate = 0
                    currentFileName = "录音不完整，已丢弃"
                } else {
                    currentFileName = "等待歌曲开始"
                }
                pausedTrackID = nil
                observedTrackID = nil
                skippedTrackID = nil
                phase = .waitingForPlayback
                status = "等待 Apple Music 播放…"
            }
        }

        return actions
    }
}
