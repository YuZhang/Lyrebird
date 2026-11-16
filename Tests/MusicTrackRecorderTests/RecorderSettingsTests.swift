import XCTest
@testable import MusicTrackRecorder

@MainActor
final class RecorderSettingsTests: XCTestCase {
    func testHighRateRestartDefaultsOffAndPersists() {
        let key = "restartsForHigherSampleRate"
        let originalValue = UserDefaults.standard.object(forKey: key)
        defer {
            if let originalValue {
                UserDefaults.standard.set(originalValue, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        UserDefaults.standard.removeObject(forKey: key)
        let model = RecorderViewModel()
        XCTAssertFalse(model.restartsForHigherSampleRate)

        model.restartsForHigherSampleRate = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: key))

        let restoredModel = RecorderViewModel()
        XCTAssertTrue(restoredModel.restartsForHigherSampleRate)
    }

    func testCaptureFormatTextShowsOutputDepthOrBitrate() {
        let model = RecorderViewModel()
        model.recordingFormat = .alac
        XCTAssertEqual(model.captureFormatText, "48 kHz · 24-bit")

        model.recordingFormat = .aac
        XCTAssertEqual(model.captureFormatText, "48 kHz · 256 kbps")
    }

    func testErrorActionMatchesPermissionCause() {
        let model = RecorderViewModel()
        model.errorMessage = "Automation permission is required"
        XCTAssertEqual(model.errorAction, .automation)
        model.errorMessage = "Screen & System Audio Recording permission is required"
        XCTAssertEqual(model.errorAction, .audioPermission)
        model.errorMessage = "Audio file write failed"
        XCTAssertNil(model.errorAction)
    }

    func testOutputDirectoryChangePersists() {
        let key = "outputDirectoryPath"
        let originalValue = UserDefaults.standard.string(forKey: key)
        defer {
            if let originalValue {
                UserDefaults.standard.set(originalValue, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Lyrebird Directory Test", isDirectory: true)
        let model = RecorderViewModel()
        model.setOutputDirectory(url)

        XCTAssertEqual(model.outputDirectory, url)
        XCTAssertEqual(UserDefaults.standard.string(forKey: key), url.path)
        XCTAssertEqual(RecorderViewModel().outputDirectory.path, url.path)
    }
}
