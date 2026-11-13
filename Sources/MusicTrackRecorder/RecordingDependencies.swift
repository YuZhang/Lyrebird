import Foundation

protocol AudioCaptureControlling: AnyObject {
    var onFileStarted: ((String) -> Void)? { get set }
    var onFileFinished: ((URL, RecordingQuality) -> Void)? { get set }
    var onError: ((String) -> Void)? { get set }
    var onCaptureStopped: (() -> Void)? { get set }
    var onSampleRateChanged: ((Int) -> Void)? { get set }

    func start(
        outputDirectory: URL,
        title: String,
        automatic: Bool,
        format: AudioRecordingFormat
    ) async throws
    func updateSampleRate(_ requestedRate: Int) async
    func stop() async
    func split(title: String) async
    func beginTrack(title: String, metadata: TrackMetadata?) async
    func pauseTrack() async
    func resumeTrack() async
    func finishTrack(completed: Bool) async
}

extension AudioCaptureEngine: AudioCaptureControlling {}

protocol MusicAutomationControlling: AnyObject {
    func snapshot(includeArtwork: Bool) async throws -> MusicPlayerSnapshot
    func restartCurrentTrack() async throws
}

extension MusicAutomationControlling {
    func snapshot() async throws -> MusicPlayerSnapshot {
        try await snapshot(includeArtwork: false)
    }
}

extension MusicAutomation: MusicAutomationControlling {}
