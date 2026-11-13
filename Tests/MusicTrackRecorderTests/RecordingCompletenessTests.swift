import XCTest
@testable import MusicTrackRecorder

final class RecordingCompletenessTests: XCTestCase {
    func testStartMustBeNearBeginning() {
        XCTAssertTrue(RecordingCompleteness.canStart(at: 0.2))
        XCTAssertFalse(RecordingCompleteness.canStart(at: 5))
    }

    func testNaturalEndIsComplete() {
        XCTAssertTrue(RecordingCompleteness.reachedEnd(duration: 180, position: 179.9))
        XCTAssertFalse(RecordingCompleteness.reachedEnd(duration: 180, position: 100))
        XCTAssertFalse(RecordingCompleteness.reachedEnd(duration: 0, position: 0))
    }

    func testTrackChangeOnlyCompletesNearEnd() {
        XCTAssertTrue(RecordingCompleteness.completedBeforeChange(duration: 180, position: 179.5))
        XCTAssertFalse(RecordingCompleteness.completedBeforeChange(duration: 180, position: 30))
        XCTAssertFalse(RecordingCompleteness.completedBeforeChange(duration: 180, position: nil))
    }
}
