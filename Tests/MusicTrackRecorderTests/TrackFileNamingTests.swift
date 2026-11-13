import XCTest
@testable import MusicTrackRecorder

final class TrackFileNamingTests: XCTestCase {
    func testSanitizedTitleRemovesPathSeparators() {
        XCTAssertEqual(TrackFileNaming.sanitizedTitle("  Song:A/B  "), "Song-A-B")
        XCTAssertEqual(TrackFileNaming.sanitizedTitle("   "), "音轨")
    }

    func testFileURLUsesM4AAndAvoidsCollision() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let first = TrackFileNaming.makeURL(title: "测试", date: date, directory: directory)
        XCTAssertEqual(first.pathExtension, "m4a")
        XCTAssertEqual(first.lastPathComponent, "测试.m4a")

        FileManager.default.createFile(atPath: first.path, contents: Data())
        let second = TrackFileNaming.makeURL(title: "测试", date: date, directory: directory)
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(second.lastPathComponent.hasSuffix("-2.m4a"))
    }

    func testElapsedFormatting() {
        XCTAssertEqual(TrackFileNaming.elapsedText(0), "00:00:00")
        XCTAssertEqual(TrackFileNaming.elapsedText(3_661.9), "01:01:01")
        XCTAssertEqual(TrackFileNaming.elapsedText(-1), "00:00:00")
    }

    func testShortTimeFormatting() {
        XCTAssertEqual(TrackFileNaming.shortTime(0), "0:00")
        XCTAssertEqual(TrackFileNaming.shortTime(65.2), "1:05")
        XCTAssertEqual(TrackFileNaming.shortTime(3_661), "1:01:01")
    }
}
