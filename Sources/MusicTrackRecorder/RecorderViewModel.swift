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

enum RecorderErrorAction: Equatable {
    case automation
    case audioPermission
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
    @Published private(set) var isPanelVisible = false
    @Published private(set) var status = "Ready"
    @Published private(set) var currentFileName = "No audio file created"
    @Published private(set) var detectedTrack = "Waiting for a Song"
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
    @Published private(set) var organizationStatus = ""
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

    var errorAction: RecorderErrorAction? {
        guard let errorMessage else { return nil }
        if errorMessage.contains("Automation") {
            return .automation
        }
        if errorMessage.contains("Screen") || errorMessage.contains("system audio") {
            return .audioPermission
        }
        return nil
    }

    func clearLogs() {
        logEvents.removeAll()
    }

    func setPanelVisible(_ visible: Bool) {
        guard isPanelVisible != visible else { return }
        isPanelVisible = visible
        if visible {
            Task { await refreshNowPlaying() }
        }
    }

    private func appendLog(_ level: LogLevel, _ message: String) {
        logEvents.insert(LogEvent(level: level, message: message), at: 0)
        if logEvents.count > 200 {
            logEvents.removeLast(logEvents.count - 200)
        }
    }

    private let engine: any AudioCaptureControlling
    private let musicAutomation: any MusicAutomationControlling
    private let musicLibrary = MusicLibrary()
    private let organizationHistoryStore = LibraryOrganizationHistoryStore()
    private var monitorTask: Task<Void, Never>?
    private var elapsedTimer: Timer?
    private var startedAt: Date?
    private var recordingStartPosition = 0.0
    private var hasUnfinishedFile = false
    private var pendingStopNotice: String?
    private var isRefreshingNowPlaying = false
    private var lastNowPlayingRefresh = Date.distantPast
    private var nowPlayingTrackID: String?

    init(
        engine: any AudioCaptureControlling = AudioCaptureEngine(),
        musicAutomation: any MusicAutomationControlling = MusicAutomation()
    ) {
        self.engine = engine
        self.musicAutomation = musicAutomation
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
                self.status = self.automaticMode ? "Recording Automatically" : "Recording"
                self.hasUnfinishedFile = true
            }
        }
        engine.onFileFinished = { [weak self] url, quality in
            Task { @MainActor in
                guard let self else { return }
                self.hasUnfinishedFile = false
                self.appendLog(.success, "Recording completed: \(url.lastPathComponent)")
                for warning in quality.metadataWarnings {
                    self.appendLog(.warning, "\(url.lastPathComponent): \(warning)")
                }
                if let track = try? LibraryOrganizer.metadata(for: url) {
                    await self.musicLibrary.register(track, at: url)
                }
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
        engine.onNotice = { [weak self] message in
            Task { @MainActor in
                self?.pendingStopNotice = message
                self?.errorMessage = nil
                self?.appendLog(.warning, message)
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
        status = "Requesting Audio Capture…"
        errorMessage = nil
        pendingStopNotice = nil

        do {
            try FileManager.default.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: true
            )
            if automaticMode {
                status = "Checking for Existing Songs…"
                await musicLibrary.prepare(in: outputDirectory)
            }
            let title = TrackFileNaming.sanitizedTitle(trackTitle)
            isRecording = true
            startedAt = Date()
            startElapsedTimer()
            currentFileName = automaticMode ? "File will be created at the start of a song" : "Waiting for Apple Music audio…"
            status = "Waiting for Apple Music…"

            guard try await waitForMusicPlayback(), isRecording else {
                isBusy = false
                return
            }

            status = "Requesting Audio Capture…"
            try await engine.start(
                outputDirectory: outputDirectory,
                title: title,
                automatic: automaticMode,
                format: recordingFormat
            )
            trackTitle = ""

            if automaticMode {
                detectedTrack = "Reading Apple Music…"
                status = "Identifying Track…"
                startMusicMonitoring()
            } else {
                status = "Recording"
            }
        } catch {
            errorMessage = error.localizedDescription
            appendLog(.error, "Failed to start recording: \(error.localizedDescription)")
            status = "Could Not Start Recording"
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
                detectedTrack = snapshot.track?.displayText ?? "Waiting for a Song"
                if snapshot.state == .playing {
                    if snapshot.sampleRate > 0 {
                        recordingStartPosition = snapshot.position
                        return true
                    }
                    unknownSampleRateCount += 1
                    if unknownSampleRateCount >= 30 {
                        recordingStartPosition = snapshot.position
                        appendLog(.warning, "Apple Music sample rate is still unknown; using the audio stream's default format")
                        return true
                    }
                    status = "Waiting for Apple Music Sample Rate…"
                } else {
                    unknownSampleRateCount = 0
                    status = "Waiting for Apple Music…"
                }
            } catch let error as MusicAutomationError {
                if case .automationPermission = error {
                    throw error
                }
                status = "Waiting for Apple Music Track Information…"
            } catch {
                status = "Waiting for Apple Music Track Information…"
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
        status = "Saving Audio…"
        await engine.stop()
        resetAfterStop()
        if discardedIncompleteFile {
            appendLog(.warning, "Current song was incomplete; file discarded")
            status = "Incomplete; Not Saved"
            currentFileName = "Current song was incomplete; file discarded"
        }
    }

    func split() async {
        guard isRecording, !isBusy, !automaticMode else { return }
        isBusy = true
        status = "Saving and Splitting…"
        let title = TrackFileNaming.sanitizedTitle(trackTitle)
        await engine.split(title: title)
        trackTitle = ""
        currentFileName = "Waiting for the next audio track…"
        status = "Recording"
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
        guard isPanelVisible else { return }
        if isRecording, let startedAt {
            elapsed = Date().timeIntervalSince(startedAt)
        } else if Date().timeIntervalSince(lastNowPlayingRefresh) > 3 {
            Task { await refreshNowPlaying() }
        }
    }

    func refreshNowPlaying() async {
        guard isPanelVisible, !isRecording, !isBusy, !isRefreshingNowPlaying else { return }
        isRefreshingNowPlaying = true
        lastNowPlayingRefresh = Date()
        defer { isRefreshingNowPlaying = false }

        do {
            let snapshot = try await musicAutomation.snapshot()
            guard !isRecording else { return }
            let trackChanged = nowPlayingTrackID != snapshot.trackID
            var resolvedSnapshot = snapshot
            if trackChanged, snapshot.track != nil,
               let artworkSnapshot = try? await musicAutomation.snapshot(includeArtwork: true),
               artworkSnapshot.trackID == snapshot.trackID {
                resolvedSnapshot = snapshot.withArtwork(artworkSnapshot.track?.artworkData)
            }
            nowPlayingTrackID = snapshot.trackID
            currentTrack = resolvedSnapshot.track
            detectedTrack = resolvedSnapshot.track?.displayText ?? "Waiting for a Song"
            if trackChanged {
                detectedArtworkData = resolvedSnapshot.track?.artworkData
            }
            detectedPosition = snapshot.position
            detectedDuration = snapshot.duration
        } catch {
            // Idle refreshes do not affect recording or permission settings.
        }
    }

    func chooseOutputDirectory() {
        guard !isRecording, !isBusy else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.directoryURL = outputDirectory

        if panel.runModal() == .OK, let url = panel.url {
            setOutputDirectory(url)
        }
    }

    func setOutputDirectory(_ url: URL) {
        outputDirectory = url
        organizationStatus = ""
        UserDefaults.standard.set(url.path, forKey: "outputDirectoryPath")
        appendLog(.info, "Save folder changed: \(url.path)")
    }

    func openOutputDirectory() {
        try? FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        NSWorkspace.shared.open(outputDirectory)
    }

    var canUndoOrganization: Bool {
        guard let history = organizationHistoryStore.load() else { return false }
        return history.directory.standardizedFileURL.path == outputDirectory.standardizedFileURL.path
            && !history.moves.isEmpty
    }

    func prepareOrganizationPreview() async -> LibraryOrganizationPlan? {
        guard !isRecording, !isBusy else { return nil }
        isBusy = true
        organizationStatus = "Generating Preview…"
        let plan = await LibraryOrganizer().plan(in: outputDirectory)
        organizationStatus = "Preview: move \(plan.moveCount), conflicts \(plan.conflictCount), organized \(plan.unchangedCount), skipped \(plan.skippedCount)"
        isBusy = false
        return plan
    }

    func executeOrganization(_ plan: LibraryOrganizationPlan) async {
        guard !isRecording, !isBusy,
              plan.directory.standardizedFileURL.path == outputDirectory.standardizedFileURL.path else { return }
        isBusy = true
        organizationStatus = "Organizing…"
        let report = await LibraryOrganizer().execute(plan)
        if let history = report.history {
            organizationHistoryStore.save(history)
        }
        for message in report.messages {
            appendLog(.info, message)
        }
        appendLog(.info, report.summary)
        organizationStatus = report.summary
        isBusy = false
        await refreshNowPlaying()
    }

    func undoOrganization() async {
        guard !isRecording, !isBusy,
              let history = organizationHistoryStore.load(),
              history.directory.standardizedFileURL.path == outputDirectory.standardizedFileURL.path else { return }
        isBusy = true
        organizationStatus = "Undoing Organization…"
        let report = await LibraryOrganizer().undo(history)
        if report.remainingMoves.isEmpty {
            organizationHistoryStore.clear()
        } else {
            organizationHistoryStore.save(LibraryOrganizationHistory(
                directory: history.directory,
                date: Date(),
                moves: report.remainingMoves
            ))
        }
        for message in report.messages {
            appendLog(.info, message)
        }
        appendLog(.info, report.summary)
        organizationStatus = report.summary
        isBusy = false
        await refreshNowPlaying()
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
        if errorMessage?.contains("Automation") == true {
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
            await self?.monitorMusicWithSession()
        }
    }

    private func monitorMusicWithSession() async {
        var session = RecordingSession()
        var enrichedTracks: [String: TrackMetadata] = [:]

        while !Task.isCancelled && isRecording {
            var pollInterval: UInt64 = 200_000_000
            do {
                var snapshot = try await musicAutomation.snapshot()
                guard !Task.isCancelled, isRecording else { return }
                currentTrack = snapshot.track
                detectedPosition = snapshot.position
                detectedDuration = snapshot.duration

                if snapshot.state == .playing, let track = snapshot.track {
                    detectedTrack = track.displayText
                    let trackChanged = snapshot.trackID != session.observedTrackID
                    let awaitingRestart = session.awaitingRestartTrackID == snapshot.trackID
                    let positionRestarted = session.previousPosition != nil
                        && snapshot.position < session.previousPosition! - 1.5
                    let needsPreparation = trackChanged || awaitingRestart || positionRestarted
                    var isDuplicate = false

                    if needsPreparation {
                        if let artworkSnapshot = try? await musicAutomation.snapshot(includeArtwork: true),
                           artworkSnapshot.trackID == snapshot.trackID {
                            detectedArtworkData = artworkSnapshot.track?.artworkData
                            snapshot = snapshot.withArtwork(detectedArtworkData)
                        }
                        await musicLibrary.refreshIfNeeded(in: outputDirectory)
                        isDuplicate = await musicLibrary.contains(track)
                    }

                    let rejectsMidTrack = session.observedTrackID == nil
                        && !awaitingRestart
                        && !positionRestarted
                        && !RecordingCompleteness.canStart(at: recordingStartPosition)
                    if needsPreparation && !isDuplicate && !rejectsMidTrack && snapshot.sampleRate <= 0 {
                        let sampleRate = try await waitForSampleRate(trackID: snapshot.trackID)
                        if sampleRate > 0 {
                            let latest = try await musicAutomation.snapshot()
                            snapshot = MusicPlayerSnapshot(
                                state: latest.state,
                                trackID: latest.trackID,
                                track: latest.track?.withArtwork(snapshot.track?.artworkData),
                                duration: latest.duration,
                                position: latest.position,
                                sampleRate: latest.sampleRate > 0 ? latest.sampleRate : sampleRate
                            )
                            currentTrack = snapshot.track
                            detectedPosition = snapshot.position
                            detectedDuration = snapshot.duration
                        }
                    }

                    if needsPreparation, !isDuplicate, !rejectsMidTrack,
                       let originalTrack = snapshot.track {
                        if let cached = enrichedTracks[snapshot.trackID] {
                            snapshot = snapshot.withTrack(
                                cached.withArtwork(originalTrack.artworkData ?? cached.artworkData)
                            )
                        } else if originalTrack.needsCatalogEnrichment {
                            do {
                                let enriched = try await CatalogMetadataStore.shared.enrich(
                                    originalTrack,
                                    duration: snapshot.duration
                                )
                                enrichedTracks[snapshot.trackID] = enriched
                                snapshot = snapshot.withTrack(enriched)
                                if enriched != originalTrack {
                                    appendLog(.info, "Catalog metadata enriched: \(originalTrack.displayText)")
                                }
                            } catch {
                                enrichedTracks[snapshot.trackID] = originalTrack
                                appendLog(.warning, "Could not enrich catalog metadata: \(error.localizedDescription)")
                            }
                        }
                    }
                    guard !Task.isCancelled, isRecording else { return }

                    let actions = session.process(
                        snapshot: snapshot,
                        isDuplicate: isDuplicate,
                        recordingStartPosition: recordingStartPosition,
                        restartsForHigherSampleRate: restartsForHigherSampleRate
                    )
                    for action in actions {
                        try await perform(action)
                    }
                    currentTrack = snapshot.track
                    currentFileName = session.currentFileName
                    status = session.status
                } else {
                    let actions = session.process(
                        snapshot: snapshot,
                        isDuplicate: false,
                        recordingStartPosition: recordingStartPosition,
                        restartsForHigherSampleRate: restartsForHigherSampleRate
                    )
                    for action in actions {
                        try await perform(action)
                    }
                    detectedTrack = snapshot.state == .stopped
                        ? "Apple Music Playback Stopped"
                        : snapshot.track?.displayText ?? "Playback Paused"
                    if snapshot.state == .stopped {
                        detectedArtworkData = nil
                    }
                    currentFileName = session.currentFileName
                    status = session.status
                }
                pollInterval = RecordingPollPolicy.nanoseconds(for: snapshot, phase: session.phase)
            } catch let error as MusicAutomationError {
                if case .automationPermission = error {
                    appendLog(.error, error.localizedDescription)
                    errorMessage = error.localizedDescription
                    await stop()
                    return
                }
                status = "Could not read the track; retrying…"
            } catch {
                status = "Could not read the track; retrying…"
            }

            try? await Task.sleep(nanoseconds: pollInterval)
        }
    }

    private func perform(_ action: RecordingSessionAction) async throws {
        switch action {
        case .begin(let metadata, let sampleRate):
            await engine.updateSampleRate(sampleRate)
            await engine.beginTrack(title: metadata.fileTitle, metadata: metadata)
        case .finish(let completed, _):
            await engine.finishTrack(completed: completed)
        case .pause:
            await engine.pauseTrack()
        case .resume:
            await engine.resumeTrack()
        case .restart:
            try await musicAutomation.restartCurrentTrack()
        case .log(let message):
            appendLog(.info, message)
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
        nowPlayingTrackID = nil
        detectedTrack = "Waiting for a Song"
        detectedArtworkData = nil
        detectedPosition = 0
        detectedDuration = 0
        status = "Ready"
        if let pendingStopNotice {
            currentFileName = "Incomplete recording deleted"
            status = pendingStopNotice
            self.pendingStopNotice = nil
        }
        lastNowPlayingRefresh = .distantPast
        Task { await refreshNowPlaying() }
    }
}
