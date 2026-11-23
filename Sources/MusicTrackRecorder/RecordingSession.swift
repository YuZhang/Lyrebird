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
    var status = "Ready"
    var currentFileName = "No audio file created"
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
                    actions.append(.log("Song already exists; skipped: \(track.displayText)"))
                    currentFileName = "Song already exists in the folder; not recorded again"
                    status = "Song already exists; skipped"
                } else if firstObservation && !trackRestarted && !RecordingCompleteness.canStart(at: recordingStartPosition) {
                    phase = .waitingForPlayback
                    currentFileName = "Current song was not recorded from the beginning"
                    status = "Waiting for the next song…"
                } else if snapshot.sampleRate <= 0 {
                    phase = .waitingForFormat
                    actions.append(.log("Could not confirm sample rate; not recorded: \(track.displayText)"))
                    currentFileName = "Sample rate unknown; not recorded"
                    status = "Waiting for the next song…"
                } else if !RecordingCompleteness.canStart(at: snapshot.position),
                          restartedForHigherRateTrackID != snapshot.trackID {
                    restartedForHigherRateTrackID = snapshot.trackID
                    awaitingRestartTrackID = snapshot.trackID
                    phase = .waitingForRestart
                    actions.append(.restart)
                    actions.append(.log("Sample rate confirmed at \(snapshot.sampleRate) Hz; recording from the beginning"))
                    currentFileName = "Sample rate confirmed; recording from the beginning"
                    status = "Starting from the beginning…"
                    previousPosition = snapshot.position
                    previousDuration = snapshot.duration
                    return actions
                } else {
                    phase = .recording
                    actions.append(.begin(metadata: track, sampleRate: snapshot.sampleRate))
                    writingTrackID = snapshot.trackID
                    writingTrack = track
                    writingSampleRate = snapshot.sampleRate
                    currentFileName = "Waiting for Apple Music audio…"
                    status = "Recording Automatically"
                }
            } else {
                if pausedTrackID == snapshot.trackID {
                    actions.append(.resume)
                    pausedTrackID = nil
                    phase = .recording
                    currentFileName = writingTrack?.fileTitle ?? currentFileName
                    status = "Recording Automatically"
                    actions.append(.log("Playback resumed; continuing recording: \(track.displayText)"))
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
                    actions.append(.log("Sample rate increased (\(writingSampleRate) Hz → \(snapshot.sampleRate) Hz); restarting from the beginning"))
                    writingTrackID = nil
                    writingTrack = nil
                    writingSampleRate = 0
                    currentFileName = "Hi-res version ready; restarting from the beginning"
                    status = "Restarting from the beginning for hi-res audio…"
                    previousPosition = snapshot.position
                    previousDuration = snapshot.duration
                    return actions
                }
                if writingTrackID == nil {
                    if skippedTrackID == snapshot.trackID {
                        currentFileName = "Song already exists in the folder; not recorded again"
                        status = "Song already exists; skipped"
                    } else {
                        currentFileName = "Waiting for the next song"
                        status = "Waiting for the next song…"
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
                currentFileName = "Complete track saved"
                status = "Waiting for the next song…"
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
                currentFileName = pausedTrackID == snapshot.trackID ? "Paused; resumes with playback" : "No audio written while paused"
                status = "Playback Paused"
            } else {
                if writingTrackID != nil {
                    actions.append(.finish(completed: false, register: nil))
                    writingTrackID = nil
                    writingTrack = nil
                    writingSampleRate = 0
                    currentFileName = "Incomplete recording discarded"
                } else {
                    currentFileName = "Waiting for a song to start"
                }
                pausedTrackID = nil
                observedTrackID = nil
                skippedTrackID = nil
                phase = .waitingForPlayback
                status = "Waiting for Apple Music…"
            }
        }

        return actions
    }
}

enum RecordingPollPolicy {
    static func nanoseconds(for snapshot: MusicPlayerSnapshot, phase: RecordingSession.Phase) -> UInt64 {
        guard snapshot.state == .playing, phase == .recording, snapshot.duration > 0 else {
            return 200_000_000
        }
        let isStable = snapshot.position >= 3 && snapshot.duration - snapshot.position >= 3
        return isStable ? 1_000_000_000 : 200_000_000
    }
}
