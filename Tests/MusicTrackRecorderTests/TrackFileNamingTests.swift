import XCTest
@testable import MusicTrackRecorder

final class TrackFileNamingTests: XCTestCase {
    private func metadata(
        title: String = "Song",
        artist: String = "Artist",
        albumArtist: String? = nil,
        album: String = "Album",
        year: Int = 2024,
        trackNumber: Int = 3,
        discNumber: Int = 0
    ) -> TrackMetadata {
        TrackMetadata(
            title: title,
            artist: artist,
            albumArtist: albumArtist ?? artist,
            album: album,
            genre: "",
            composer: "",
            year: year,
            trackNumber: trackNumber,
            discNumber: discNumber
        )
    }

    func testAlbumTrackURLUsesRequestedPathAndAvoidsCollision() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = TrackFileNaming.makeURL(metadata: metadata(), directory: directory)
        XCTAssertEqual(first.deletingLastPathComponent().lastPathComponent, "Artist-Album")
        XCTAssertEqual(first.lastPathComponent, "3-Song.m4a")

        try FileManager.default.createDirectory(
            at: first.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: first.path, contents: Data())
        let second = TrackFileNaming.makeURL(metadata: metadata(), directory: directory)
        XCTAssertEqual(second.lastPathComponent, "3-Song-2.m4a")
    }

    func testCompilationUsesSharedAlbumDirectory() {
        let url = TrackFileNaming.makeURL(
            metadata: metadata(artist: "Singer", albumArtist: "Various Artists"),
            directory: URL(fileURLWithPath: "/tmp")
        )
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "合集-Album")
    }

    func testDiscNumberPrefixesTrackFileName() {
        let url = TrackFileNaming.makeURL(
            metadata: metadata(trackNumber: 4, discNumber: 2),
            directory: URL(fileURLWithPath: "/tmp")
        )
        XCTAssertEqual(url.lastPathComponent, "Disk2-4-Song.m4a")
    }

    func testMissingInformationAndPathSeparatorsUseSafeNames() {
        let url = TrackFileNaming.makeURL(
            metadata: metadata(
                title: "Song/One",
                artist: "A/B",
                album: "Live:One",
                year: 0,
                trackNumber: 0
            ),
            directory: URL(fileURLWithPath: "/tmp")
        )
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "A_B-Live_One")
        XCTAssertEqual(url.lastPathComponent, "Song_One.m4a")
    }

    func testSanitizedTitleRemovesPathSeparators() {
        XCTAssertEqual(TrackFileNaming.sanitizedTitle("  Song:A/B  "), "Song_A_B")
        XCTAssertEqual(TrackFileNaming.sanitizedTitle("A\nB"), "A_B")
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

    func testTemporaryURLAddsTmpWithoutReplacingAudioExtension() {
        let finalURL = URL(fileURLWithPath: "/tmp/Song.m4a")
        let temporaryURL = TrackFileNaming.temporaryURL(for: finalURL)
        XCTAssertEqual(temporaryURL.lastPathComponent, "Song.m4a.tmp")
        XCTAssertEqual(temporaryURL.deletingPathExtension(), finalURL)
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
