import XCTest
@testable import MusicTrackRecorder

final class RecordingSessionTests: XCTestCase {
    func testValidTrackBeginsAtSourceRate() {
        var session = RecordingSession()
        let actions = session.process(snapshot: snapshot(rate: 44_100), isDuplicate: false, recordingStartPosition: 0.1, restartsForHigherSampleRate: false)
        XCTAssertTrue(hasBegin(actions, rate: 44_100))
        XCTAssertEqual(session.phase, .recording)
    }

    func testUnknownRateDoesNotDefaultTo48() {
        var session = RecordingSession()
        let actions = session.process(snapshot: snapshot(rate: 0), isDuplicate: false, recordingStartPosition: 0.1, restartsForHigherSampleRate: false)
        XCTAssertFalse(actions.contains { action in
            if case .begin = action { return true }
            return false
        })
        XCTAssertEqual(session.phase, .waitingForFormat)
    }

    func testLateFormatRequestsRestartOnce() {
        var session = RecordingSession()
        let first = session.process(snapshot: snapshot(rate: 192_000, position: 2), isDuplicate: false, recordingStartPosition: 0.1, restartsForHigherSampleRate: false)
        XCTAssertTrue(first.contains { action in
            if case .restart = action { return true }
            return false
        })
        let resumed = session.process(snapshot: snapshot(rate: 192_000, position: 0.2), isDuplicate: false, recordingStartPosition: 0.1, restartsForHigherSampleRate: false)
        XCTAssertTrue(hasBegin(resumed, rate: 192_000))
    }

    func testHigherRateRestartHappensOnlyOnce() {
        var session = RecordingSession()
        _ = session.process(snapshot: snapshot(rate: 48_000), isDuplicate: false, recordingStartPosition: 0.1, restartsForHigherSampleRate: true)
        let first = session.process(snapshot: snapshot(rate: 192_000, position: 2), isDuplicate: false, recordingStartPosition: 0.1, restartsForHigherSampleRate: true)
        let second = session.process(snapshot: snapshot(rate: 192_000, position: 2.2), isDuplicate: false, recordingStartPosition: 0.1, restartsForHigherSampleRate: true)
        XCTAssertEqual(restartCount(first), 1)
        XCTAssertEqual(restartCount(second), 0)
    }

    func testPauseAndResumeKeepCurrentFile() {
        var session = RecordingSession()
        _ = session.process(snapshot: snapshot(rate: 44_100), isDuplicate: false, recordingStartPosition: 0.1, restartsForHigherSampleRate: false)
        let paused = session.process(snapshot: snapshot(state: .paused, rate: 44_100), isDuplicate: false, recordingStartPosition: 0.1, restartsForHigherSampleRate: false)
        XCTAssertTrue(paused.contains { action in
            if case .pause = action { return true }
            return false
        })
        XCTAssertEqual(session.phase, .paused)
        let resumed = session.process(snapshot: snapshot(rate: 44_100), isDuplicate: false, recordingStartPosition: 0.1, restartsForHigherSampleRate: false)
        XCTAssertTrue(resumed.contains { action in
            if case .resume = action { return true }
            return false
        })
        XCTAssertFalse(resumed.contains { action in
            if case .finish = action { return true }
            return false
        })
    }

    func testPausedTrackChangeDiscardsIncompleteFile() {
        var session = RecordingSession()
        _ = session.process(snapshot: snapshot(rate: 44_100), isDuplicate: false, recordingStartPosition: 0.1, restartsForHigherSampleRate: false)
        let actions = session.process(snapshot: snapshot(state: .paused, id: "new", rate: 44_100), isDuplicate: false, recordingStartPosition: 0.1, restartsForHigherSampleRate: false)
        XCTAssertTrue(actions.contains { action in
            if case .finish(let completed, _) = action { return !completed }
            return false
        })
    }

    func testMusicRestartStartsFreshAfterDiscardingIncompleteFile() {
        var session = RecordingSession()
        _ = session.process(snapshot: snapshot(rate: 48_000), isDuplicate: false, recordingStartPosition: 0.1, restartsForHigherSampleRate: false)
        let stopped = session.process(snapshot: .stopped, isDuplicate: false, recordingStartPosition: 0.1, restartsForHigherSampleRate: false)
        XCTAssertTrue(stopped.contains { action in
            if case .finish(let completed, _) = action { return !completed }
            return false
        })
        let restarted = session.process(snapshot: snapshot(id: "new", rate: 192_000), isDuplicate: false, recordingStartPosition: 0.1, restartsForHigherSampleRate: false)
        XCTAssertTrue(hasBegin(restarted, rate: 192_000))
        XCTAssertEqual(session.phase, .recording)
    }

    func testStablePlaybackUsesSlowerPolling() {
        let current = snapshot(rate: 48_000, position: 10)
        XCTAssertEqual(RecordingPollPolicy.nanoseconds(for: current, phase: .recording), 1_000_000_000)
    }

    func testTrackBoundariesAndTransitionsKeepFastPolling() {
        let beginning = snapshot(rate: 48_000, position: 0.2)
        let ending = snapshot(rate: 48_000, position: 178)
        let stable = snapshot(rate: 48_000, position: 10)
        XCTAssertEqual(RecordingPollPolicy.nanoseconds(for: beginning, phase: .recording), 200_000_000)
        XCTAssertEqual(RecordingPollPolicy.nanoseconds(for: ending, phase: .recording), 200_000_000)
        XCTAssertEqual(RecordingPollPolicy.nanoseconds(for: stable, phase: .waitingForRestart), 200_000_000)
    }

    private func snapshot(
        state: MusicPlayerSnapshot.State = .playing,
        id: String = "track",
        rate: Int,
        position: Double = 0.1
    ) -> MusicPlayerSnapshot {
        MusicPlayerSnapshot(state: state, trackID: id, track: metadata(), duration: 180, position: position, sampleRate: rate)
    }

    private func metadata() -> TrackMetadata {
        TrackMetadata(title: "Song", artist: "Artist", albumArtist: "Artist", album: "Album", genre: "", composer: "", year: 2026, trackNumber: 1, discNumber: 1)
    }

    private func hasBegin(_ actions: [RecordingSessionAction], rate: Int) -> Bool {
        actions.contains { action in
            if case .begin(_, let sampleRate) = action { return sampleRate == rate }
            return false
        }
    }

    private func restartCount(_ actions: [RecordingSessionAction]) -> Int {
        actions.reduce(into: 0) { count, action in
            if case .restart = action { count += 1 }
        }
    }
}

@MainActor
final class InjectedRecordingTests: XCTestCase {
    func testInjectedDependenciesRecordAt44100WithoutRealMusic() async {
        let engine = FakeCaptureEngine()
        let automation = FakeMusicAutomation(snapshot: injectedSnapshot(rate: 44_100))
        let model = makeModel(engine: engine, automation: automation)
        await model.start()
        await assertEventually { engine.begunRates == [44_100] }
        await model.stop()
    }

    func testInjectedPauseAndResumeUseSameFile() async {
        let engine = FakeCaptureEngine()
        let automation = FakeMusicAutomation(snapshot: injectedSnapshot(rate: 44_100))
        let model = makeModel(engine: engine, automation: automation)
        await model.start()
        await assertEventually { !engine.begunRates.isEmpty }
        automation.update(state: .paused)
        await assertEventually { engine.pauseCalls == 1 }
        automation.update(state: .playing)
        await assertEventually { engine.resumeCalls == 1 }
        XCTAssertTrue(engine.finishedCompleted.isEmpty)
        await model.stop()
    }

    func testInjectedHighRateRestartSurvivesTransientPause() async {
        let engine = FakeCaptureEngine()
        let automation = FakeMusicAutomation(snapshot: injectedSnapshot(rate: 48_000))
        automation.pauseAfterRestart = true
        let model = makeModel(engine: engine, automation: automation)
        model.restartsForHigherSampleRate = true
        await model.start()
        await assertEventually { engine.begunRates == [48_000] }
        automation.update(rate: 192_000, position: 2)
        await assertEventually { automation.restartCount == 1 }
        automation.update(state: .playing, rate: 192_000, position: 0.2)
        await assertEventually { engine.begunRates == [48_000, 192_000] }
        await model.stop()
    }

    func testDeviceInterruptionUsesStatusWithoutAlert() async {
        let engine = FakeCaptureEngine()
        let automation = FakeMusicAutomation(snapshot: injectedSnapshot(rate: 48_000))
        let model = makeModel(engine: engine, automation: automation)
        await model.start()
        await assertEventually { engine.begunRates == [48_000] }
        let message = "The default output device changed. Stopped and discarded the incomplete recording."
        engine.onNotice?(message)
        engine.onCaptureStopped?()
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isRecording)
        XCTAssertEqual(model.status, message)
        XCTAssertTrue(model.logEvents.contains { $0.message == message })
    }

    func testPanelVisibilityControlsIdleRefresh() async {
        let engine = FakeCaptureEngine()
        let automation = FakeMusicAutomation(snapshot: injectedSnapshot(rate: 48_000))
        let model = makeModel(engine: engine, automation: automation)
        model.setPanelVisible(false)
        model.updateElapsed()
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(automation.snapshotCalls, 0)

        model.setPanelVisible(true)
        await assertEventually { automation.snapshotCalls > 0 }
    }

    private func makeModel(engine: FakeCaptureEngine, automation: FakeMusicAutomation) -> RecorderViewModel {
        let model = RecorderViewModel(engine: engine, musicAutomation: automation)
        model.outputDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("Lyrebird Tests \(UUID().uuidString)", isDirectory: true)
        return model
    }

    private func assertEventually(_ condition: () -> Bool) async {
        var passed = false
        for _ in 0..<30 {
            if condition() {
                passed = true
                break
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(condition())
        XCTAssertTrue(passed)
    }
}

private func injectedSnapshot(rate: Int) -> MusicPlayerSnapshot {
    MusicPlayerSnapshot(state: .playing, trackID: "injected", track: TrackMetadata(title: "Injected", artist: "Test", albumArtist: "Test", album: "Tests", genre: "", composer: "", year: 2026, trackNumber: 1, discNumber: 1), duration: 180, position: 0.1, sampleRate: rate)
}

private final class FakeCaptureEngine: AudioCaptureControlling {
    var onFileStarted: ((String) -> Void)?
    var onFileFinished: ((URL, RecordingQuality) -> Void)?
    var onError: ((String) -> Void)?
    var onNotice: ((String) -> Void)?
    var onCaptureStopped: (() -> Void)?
    var onSampleRateChanged: ((Int) -> Void)?
    var begunRates: [Int] = []
    var finishedCompleted: [Bool] = []
    var pauseCalls = 0
    var resumeCalls = 0

    func start(outputDirectory: URL, title: String, automatic: Bool, format: AudioRecordingFormat) async throws {}
    func updateSampleRate(_ requestedRate: Int) async { begunRates.append(requestedRate) }
    func stop() async {}
    func split(title: String) async {}
    func beginTrack(title: String, metadata: TrackMetadata?) async {}
    func pauseTrack() async { pauseCalls += 1 }
    func resumeTrack() async { resumeCalls += 1 }
    func finishTrack(completed: Bool) async { finishedCompleted.append(completed) }
}

private final class FakeMusicAutomation: MusicAutomationControlling {
    var currentSnapshot: MusicPlayerSnapshot
    var restartCount = 0
    var snapshotCalls = 0
    var pauseAfterRestart = false

    init(snapshot: MusicPlayerSnapshot) {
        currentSnapshot = snapshot
    }

    func snapshot(includeArtwork: Bool) async throws -> MusicPlayerSnapshot {
        snapshotCalls += 1
        return currentSnapshot
    }

    func restartCurrentTrack() async throws {
        restartCount += 1
        update(state: pauseAfterRestart ? .paused : .playing, rate: currentSnapshot.sampleRate, position: 0.2)
    }

    func update(state: MusicPlayerSnapshot.State? = nil, rate: Int? = nil, position: Double? = nil) {
        currentSnapshot = MusicPlayerSnapshot(
            state: state ?? currentSnapshot.state,
            trackID: currentSnapshot.trackID,
            track: currentSnapshot.track,
            duration: currentSnapshot.duration,
            position: position ?? currentSnapshot.position,
            sampleRate: rate ?? currentSnapshot.sampleRate
        )
    }
}
