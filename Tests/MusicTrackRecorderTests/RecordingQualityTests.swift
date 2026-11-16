import XCTest
@testable import MusicTrackRecorder

final class RecordingQualityTests: XCTestCase {
    func testCleanRecordingHasNoIssues() {
        let quality = RecordingQuality(writtenFrames: 48_000)
        XCTAssertFalse(quality.hasIssues)
        XCTAssertTrue(quality.summary.contains("No dropped frames"))
    }

    func testDroppedSamplesAreReported() {
        let quality = RecordingQuality(
            droppedFrames: 1_024,
            droppedBuffers: 1,
            maximumBufferedBuffers: 512,
            writtenFrames: 47_000
        )
        XCTAssertTrue(quality.hasIssues)
        XCTAssertTrue(quality.summary.contains("1 audio buffer"))
        XCTAssertTrue(quality.summary.contains("1024 frames"))
    }
}
