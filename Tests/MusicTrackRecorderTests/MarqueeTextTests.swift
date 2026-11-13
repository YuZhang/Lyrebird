import XCTest
@testable import MusicTrackRecorder

final class MarqueeTextTests: XCTestCase {
    func testShortTextStaysStill() {
        XCTAssertFalse(MarqueeText.overflows(textWidth: 100, containerWidth: 120))
        XCTAssertEqual(MarqueeText.offset(textWidth: 100, containerWidth: 120, elapsed: 10), 0)
    }

    func testLongTextMovesAfterInitialPause() {
        XCTAssertTrue(MarqueeText.overflows(textWidth: 200, containerWidth: 100))
        XCTAssertEqual(MarqueeText.offset(textWidth: 200, containerWidth: 100, elapsed: 0.5), 0)
        XCTAssertEqual(MarqueeText.offset(textWidth: 200, containerWidth: 100, elapsed: 2), -30)
        XCTAssertEqual(MarqueeText.offset(textWidth: 200, containerWidth: 100, elapsed: 3), -60)
    }

    func testLongTextLoopsContinuously() {
        let cycleDuration: TimeInterval = 1 + (200 + 28) / 30
        XCTAssertEqual(
            MarqueeText.offset(textWidth: 200, containerWidth: 100, elapsed: cycleDuration),
            0,
            accuracy: 0.0001
        )
    }
}
