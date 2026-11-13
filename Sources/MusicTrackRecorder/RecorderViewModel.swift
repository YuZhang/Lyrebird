import Foundation
import AppKit
import CoreGraphics

struct RecordedFile: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let createdAt = Date()
    var quality: RecordingQuality? = nil
    var reportURL: URL? = nil
    var info: RecordingFileInfo? = nil

    var detailText: String {
        guard let info else { return "" }
        let size = ByteCountFormatter.string(fromByteCount: info.fileSize, countStyle: .file)
        let sampleRate = Double(info.sampleRate) / 1_000
        let rate = sampleRate.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(sampleRate)) kHz"
            : String(format: "%.1f kHz", sampleRate)
        return "\(TrackFileNaming.shortTime(info.duration)) · \(size) · \(info.codec) · \(rate)"
    }
}

enum LogLevel {
    case success
    case info
    case warning
    case error
}

struct LogEvent: Identifiable, Equatable {
    let id = UUID()
    let date = Date()
    let level: LogLevel
    let message: String
}

@MainActor
final class RecorderViewModel: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isBusy = false
    @Published private(set) var status = "准备就绪"
    @Published private(set) var currentFileName = "尚未创建音频文件"
    @Published private(set) var detectedTrack = "等待播放歌曲"
    @Published private(set) var currentTrack: TrackMetadata?
    @Published private(set) var detectedArtworkData: Data?
    @Published private(set) var detectedPosition = 0.0
    @Published private(set) var detectedDuration = 0.0
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var captureSampleRate = 48_000
    @Published private(set) var files: [RecordedFile] = []
    @Published private(set) var logEvents: [LogEvent] = []
    @Published var automaticMode = true
    @Published var recordingFormat: AudioRecordingFormat = .alac {
        didSet {
            UserDefaults.standard.set(recordingFormat.rawValue, forKey: "audioRecordingFormat")
        }
    }
    @Published var restartsForHigherSampleRate = false {
        didSet {
            UserDefaults.standard.set(restartsForHigherSampleRate, forKey: "restartsForHigherSampleRate")
        }
    }
    @Published var trackTitle = ""
    @Published var outputDirectory: URL
    @Published var errorMessage: String?

    var captureSampleRateText: String {
        let value = Double(captureSampleRate) / 1_000
        return value.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(value)) kHz"
            : String(format: "%.1f kHz", value)
    }

    var captureFormatText: String {
        switch recordingFormat {
        case .alac:
            return "\(captureSampleRateText) · 24-bit"
        case .aac:
            return "\(captureSampleRateText) · 256 kbps"
        }
    }

    func clearLogs() {
        logEvents.removeAll()
    }

    private func appendLog(_ level: LogLevel, _ message: String) {
        logEvents.insert(LogEvent(level: level, message: message), at: 0)
        if logEvents.count > 200 {
            logEvents.removeLast(logEvents.count - 200)
        }
    }

    private let engine = AudioCaptureEngine()
    private let musicAutomation = MusicAutomation()
    private let musicLibrary = MusicLibrary()
    private var monitorTask: Task<Void, Never>?
    private var elapsedTimer: Timer?
    private var startedAt: Date?
    private var recordingStartPosition = 0.0
    private var hasUnfinishedFile = false
    private var isRefreshingNowPlaying = false
    private var lastNowPlayingRefresh = Date.distantPast

    init() {
        if let savedPath = UserDefaults.standard.string(forKey: "outputDirectoryPath") {
            outputDirectory = URL(fileURLWithPath: savedPath)
        } else {
            let music = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser
            outputDirectory = music.appendingPathComponent("Apple Music 录音", isDirectory: true)
        }
        if let savedFormat = UserDefaults.standard.string(forKey: "audioRecordingFormat"),
           let format = AudioRecordingFormat(rawValue: savedFormat) {
            recordingFormat = format
        }
        restartsForHigherSampleRate = UserDefaults.standard.bool(forKey: "restartsForHigherSampleRate")

        engine.onFileStarted = { [weak self] name in
            Task { @MainActor in
                guard let self else { return }
                self.currentFileName = name
                self.status = self.automaticMode ? "正在自动录音" : "正在录音"
                self.hasUnfinishedFile = true
            }
        }
        engine.onFileFinished = { [weak self] url, quality in
            Task { @MainActor in
                guard let self else { return }
                self.hasUnfinishedFile = false
                self.appendLog(.success, "录制完成：\(url.lastPathComponent)")
                let info = try? await RecordingQualityReport.info(url: url)
                self.files.insert(
                    RecordedFile(url: url, quality: quality, info: info),
                    at: 0
                )
            }
        }
        engine.onError = { [weak self] message in
            Task { @MainActor in
                self?.errorMessage = message
                self?.appendLog(.error, message)
            }
        }
        engine.onCaptureStopped = { [weak self] in
            Task { @MainActor in
                self?.resetAfterStop()
            }
        }
        engine.onSampleRateChanged = { [weak self] rate in
            Task { @MainActor in
                self?.captureSampleRate = rate
            }
        }
    }

    func start() async {
        guard !isRecording, !isBusy else { return }
        isBusy = true
        status = "正在请求音频捕获…"
        errorMessage = nil

        do {
            try FileManager.default.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: true
            )
            if automaticMode {
                status = "正在检查文件夹中的已有歌曲…"
                await musicLibrary.prepare(in: outputDirectory)
            }
            let title = TrackFileNaming.sanitizedTitle(trackTitle)
            isRecording = true
            startedAt = Date()
            startElapsedTimer()
            currentFileName = automaticMode ? "从歌曲开始时自动创建文件" : "等待 Apple Music 音频…"
            status = "等待 Apple Music 播放…"

            guard try await waitForMusicPlayback(), isRecording else {
                isBusy = false
                return
            }

            status = "正在请求音频捕获…"
            try await engine.start(
                outputDirectory: outputDirectory,
                title: title,
                automatic: automaticMode,
                format: recordingFormat
            )
            trackTitle = ""

            if automaticMode {
                detectedTrack = "正在读取 Apple Music…"
                status = "正在识别歌曲…"
                startMusicMonitoring()
            } else {
                status = "正在录音"
            }
        } catch {
            errorMessage = error.localizedDescription
            appendLog(.error, "启动录音失败：\(error.localizedDescription)")
            status = "无法开始录音"
            isRecording = false
            elapsedTimer?.invalidate()
            elapsedTimer = nil
            startedAt = nil
            elapsed = 0
        }
        isBusy = false
    }

    private func waitForMusicPlayback() async throws -> Bool {
        var unknownSampleRateCount = 0
        while isRecording && !Task.isCancelled {
            do {
                let snapshot = try await musicAutomation.snapshot()
                guard isRecording else { return false }
                detectedPosition = snapshot.position
                detectedDuration = snapshot.duration
                currentTrack = snapshot.track
                detectedTrack = snapshot.track?.displayText ?? "等待播放歌曲"
                if snapshot.state == .playing {
                    if snapshot.sampleRate > 0 {
                        recordingStartPosition = snapshot.position
                        return true
                    }
                    unknownSampleRateCount += 1
                    if unknownSampleRateCount >= 30 {
                        recordingStartPosition = snapshot.position
                        appendLog(.warning, "Apple Music 采样率仍未知，使用音频流默认格式")
                        return true
                    }
                    status = "等待 Apple Music 采样率…"
                } else {
                    unknownSampleRateCount = 0
                    status = "等待 Apple Music 播放…"
                }
            } catch let error as MusicAutomationError {
                if case .automationPermission = error {
                    throw error
                }
                status = "等待 Apple Music 曲目信息…"
            } catch {
                status = "等待 Apple Music 曲目信息…"
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        return false
    }

    private func waitForSampleRate(trackID: String) async throws -> Int {
        for _ in 0..<300 {
            let snapshot = try await musicAutomation.snapshot()
            guard snapshot.trackID == trackID, snapshot.state == .playing else { return 0 }
            if snapshot.sampleRate > 0 {
                return snapshot.sampleRate
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        return 0
    }

    func stop() async {
        monitorTask?.cancel()
        monitorTask = nil
        guard isRecording else {
            resetAfterStop()
            return
        }
        let discardedIncompleteFile = automaticMode && hasUnfinishedFile
        isBusy = true
        status = "正在保存音频…"
        await engine.stop()
        resetAfterStop()
        if discardedIncompleteFile {
            appendLog(.warning, "当前歌曲未录完整，文件已丢弃")
            status = "未完成，未保存"
            currentFileName = "当前歌曲未录完整，文件已丢弃"
        }
    }

    func split() async {
        guard isRecording, !isBusy, !automaticMode else { return }
        isBusy = true
        status = "正在保存并切分…"
        let title = TrackFileNaming.sanitizedTitle(trackTitle)
        await engine.split(title: title)
        trackTitle = ""
        currentFileName = "等待下一首音频…"
        status = "正在录音"
        isBusy = false
    }

    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        updateElapsed()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateElapsed()
            }
        }
        elapsedTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func updateElapsed() {
        if isRecording, let startedAt {
            elapsed = Date().timeIntervalSince(startedAt)
        } else if Date().timeIntervalSince(lastNowPlayingRefresh) > 3 {
            Task { await refreshNowPlaying() }
        }
    }

    func refreshNowPlaying() async {
        guard !isRecording, !isBusy, !isRefreshingNowPlaying else { return }
        isRefreshingNowPlaying = true
        lastNowPlayingRefresh = Date()
        defer { isRefreshingNowPlaying = false }

        do {
            let snapshot = try await musicAutomation.snapshot(includeArtwork: true)
            guard !isRecording else { return }
            currentTrack = snapshot.track
            detectedTrack = snapshot.track?.displayText ?? "等待播放歌曲"
            detectedArtworkData = snapshot.track?.artworkData
            detectedPosition = snapshot.position
            detectedDuration = snapshot.duration
        } catch {
            // 待机刷新不影响录音或权限设置。
        }
    }

    func chooseOutputDirectory() {
        guard !isRecording, !isBusy else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        panel.directoryURL = outputDirectory

        if panel.runModal() == .OK, let url = panel.url {
            setOutputDirectory(url)
        }
    }

    func setOutputDirectory(_ url: URL) {
        outputDirectory = url
        UserDefaults.standard.set(url.path, forKey: "outputDirectoryPath")
        appendLog(.info, "保存目录已更改：\(url.path)")
    }

    func openOutputDirectory() {
        try? FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        NSWorkspace.shared.open(outputDirectory)
    }

    func reveal(_ file: RecordedFile) {
        NSWorkspace.shared.activateFileViewerSelecting([file.url])
    }

    func revealReport(_ file: RecordedFile) {
        guard let reportURL = file.reportURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([reportURL])
    }

    func revealApplication() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    func openPermissionSettings() {
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
        openSettings(anchor: "Privacy_ScreenCapture")
    }

    func openAutomationSettings() {
        openSettings(anchor: "Privacy_Automation")
    }

    func openRelevantPermissionSettings() {
        if errorMessage?.contains("自动化") == true {
            openAutomationSettings()
        } else {
            openPermissionSettings()
        }
    }

    private func openSettings(anchor: String) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
        if !NSWorkspace.shared.open(url) {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        }
    }

    private func startMusicMonitoring() {
        monitorTask = Task { @MainActor [weak self] in
            await self?.monitorMusic()
        }
    }

    private func monitorMusic() async {
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

        while !Task.isCancelled && isRecording {
            do {
                let snapshot = try await musicAutomation.snapshot()
                guard !Task.isCancelled, isRecording else { return }
                currentTrack = snapshot.track
                detectedPosition = snapshot.position
                detectedDuration = snapshot.duration

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
                            await engine.finishTrack(completed: previousWasComplete)
                            if previousWasComplete, let writingTrack {
                                await musicLibrary.register(writingTrack)
                            }
                            writingTrackID = nil
                            writingTrack = nil
                            writingSampleRate = 0
                        }

                        let firstObservation = observedTrackID == nil
                        observedTrackID = snapshot.trackID
                        skippedTrackID = nil
                        detectedTrack = track.displayText
                        if let artworkSnapshot = try? await musicAutomation.snapshot(includeArtwork: true),
                           artworkSnapshot.trackID == snapshot.trackID {
                            detectedArtworkData = artworkSnapshot.track?.artworkData
                        }

                        await musicLibrary.refreshIfNeeded(in: outputDirectory)
                        if await musicLibrary.contains(track) {
                            skippedTrackID = snapshot.trackID
                            appendLog(.info, "歌曲已存在，已跳过：\(track.displayText)")
                            currentFileName = "文件夹中已有此歌曲，未重复录制"
                            status = "歌曲已存在，已跳过"
                        } else if firstObservation && !trackRestarted && !RecordingCompleteness.canStart(at: recordingStartPosition) {
                            currentFileName = "当前歌曲未从头录制"
                            status = "等待下一首自动开始…"
                        } else {
                            let sampleRate = snapshot.sampleRate > 0
                                ? snapshot.sampleRate
                                : try await waitForSampleRate(trackID: snapshot.trackID)
                            if sampleRate == 0 {
                                appendLog(.warning, "无法确认采样率，未录制：\(track.displayText)")
                                currentFileName = "采样率未知，未录制"
                                status = "等待下一首自动开始…"
                            } else {
                                let detailed = try await musicAutomation.snapshot()
                                if detailed.trackID == snapshot.trackID,
                                   detailed.state == .playing,
                                   let detailedTrack = detailed.track?.withArtwork(detectedArtworkData) {
                                    if RecordingCompleteness.canStart(at: detailed.position) {
                                        detectedArtworkData = detailedTrack.artworkData
                                        currentFileName = "等待 Apple Music 音频…"
                                        await engine.updateSampleRate(sampleRate)
                                        await engine.beginTrack(title: detailedTrack.fileTitle, metadata: detailedTrack)
                                        writingTrackID = snapshot.trackID
                                        writingTrack = detailedTrack
                                        writingSampleRate = sampleRate
                                        status = "正在自动录音"
                                    } else if restartedForHigherRateTrackID != snapshot.trackID {
                                        restartedForHigherRateTrackID = snapshot.trackID
                                        try await musicAutomation.restartCurrentTrack()
                                        awaitingRestartTrackID = snapshot.trackID
                                        appendLog(.info, "采样率确认为 \(sampleRate) Hz，从头开始录制")
                                        currentFileName = "采样率已确认，从头开始录制"
                                        status = "正在从头录制…"
                                        previousPosition = detailed.position
                                        previousDuration = detailed.duration
                                        continue
                                    } else {
                                        currentFileName = "采样率确认过晚，当前歌曲未录制"
                                        status = "等待下一首自动开始…"
                                    }
                                }
                            }
                        }
                    } else {
                        detectedTrack = track.displayText
                        if pausedTrackID == snapshot.trackID {
                            await engine.resumeTrack()
                            pausedTrackID = nil
                            currentFileName = writingTrack?.fileTitle ?? currentFileName
                            status = "正在自动录音"
                            appendLog(.info, "恢复播放，继续录制：\(track.displayText)")
                        }
                        if restartsForHigherSampleRate,
                           writingTrackID == snapshot.trackID,
                           restartedForHigherRateTrackID != snapshot.trackID,
                           writingSampleRate > 0,
                           snapshot.sampleRate > writingSampleRate {
                            try await musicAutomation.restartCurrentTrack()
                            restartedForHigherRateTrackID = snapshot.trackID
                            awaitingRestartTrackID = snapshot.trackID
                            await engine.finishTrack(completed: false)
                            writingTrackID = nil
                            writingTrack = nil
                            appendLog(.info, "检测到采样率提升（\(writingSampleRate) Hz → \(snapshot.sampleRate) Hz），从头重录")
                            writingSampleRate = 0
                            currentFileName = "高解析版本已就绪，从头重录"
                            status = "正在从头重录高解析版本…"
                            previousPosition = snapshot.position
                            previousDuration = snapshot.duration
                            continue
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
                        await engine.finishTrack(completed: true)
                        if let writingTrack {
                            await musicLibrary.register(writingTrack)
                        }
                        writingTrackID = nil
                        writingTrack = nil
                        writingSampleRate = 0
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
                            await engine.finishTrack(completed: false)
                            writingTrackID = nil
                            writingTrack = nil
                            writingSampleRate = 0
                            pausedTrackID = nil
                        }
                        if writingTrackID != nil {
                            await engine.pauseTrack()
                            pausedTrackID = writingTrackID
                        }
                        detectedTrack = snapshot.track?.displayText ?? "播放已暂停"
                        currentFileName = pausedTrackID == snapshot.trackID ? "已暂停，恢复后继续" : "暂停期间不写入音频"
                        status = "播放已暂停"
                    } else {
                        let discardedIncompleteFile = writingTrackID != nil
                        if writingTrackID != nil {
                            await engine.finishTrack(completed: false)
                            writingTrackID = nil
                            writingTrack = nil
                            writingSampleRate = 0
                        }
                        pausedTrackID = nil
                        observedTrackID = nil
                        skippedTrackID = nil
                        detectedTrack = "Apple Music 已停止播放"
                        detectedArtworkData = nil
                        currentFileName = discardedIncompleteFile ? "录音不完整，已丢弃" : "等待歌曲开始"
                        status = "等待 Apple Music 播放…"
                    }
                }
            } catch let error as MusicAutomationError {
                if case .automationPermission = error {
                    appendLog(.error, error.localizedDescription)
                    errorMessage = error.localizedDescription
                    await stop()
                    return
                }
                status = "暂时无法读取歌曲，正在重试…"
            } catch {
                status = "暂时无法读取歌曲，正在重试…"
            }

            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    private func resetAfterStop() {
        monitorTask?.cancel()
        monitorTask = nil
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        isRecording = false
        isBusy = false
        startedAt = nil
        elapsed = 0
        hasUnfinishedFile = false
        currentTrack = nil
        detectedTrack = "等待播放歌曲"
        detectedArtworkData = nil
        detectedPosition = 0
        detectedDuration = 0
        status = "准备就绪"
        lastNowPlayingRefresh = .distantPast
        Task { await refreshNowPlaying() }
    }
}
