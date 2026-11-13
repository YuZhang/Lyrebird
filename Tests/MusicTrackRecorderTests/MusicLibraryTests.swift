import XCTest
@testable import MusicTrackRecorder

final class MusicLibraryTests: XCTestCase {
    private let track = TrackMetadata(
        title: "测试歌曲",
        artist: "测试艺人",
        albumArtist: "测试艺人",
        album: "测试专辑",
        genre: "流行",
        composer: "作曲者",
        year: 2026,
        trackNumber: 1,
        discNumber: 1
    )

    func testExistingFileNamePreventsDuplicate() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let existing = directory.appendingPathComponent("测试艺人 - 测试歌曲-20261111-015200.m4a")
        FileManager.default.createFile(atPath: existing.path, contents: Data())

        let library = MusicLibrary()
        await library.prepare(in: directory)
        let contains = await library.contains(track)
        XCTAssertTrue(contains)
    }

    func testDeletedFileIsRemovedFromIndex() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let existing = directory.appendingPathComponent("测试艺人 - 测试歌曲-20261111-015200.m4a")
        FileManager.default.createFile(atPath: existing.path, contents: Data())

        let library = MusicLibrary()
        await library.prepare(in: directory)
        var contains = await library.contains(track)
        XCTAssertTrue(contains)

        try FileManager.default.removeItem(at: existing)
        await library.refreshIfNeeded(in: directory)
        contains = await library.contains(track)
        XCTAssertFalse(contains)
    }

    func testCompletedTrackIsRegistered() async {
        let library = MusicLibrary()
        let before = await library.contains(track)
        XCTAssertFalse(before)

        await library.register(track)
        let after = await library.contains(track)
        XCTAssertTrue(after)
    }

    func testDifferentSongIsNotDuplicate() async {
        let library = MusicLibrary()
        await library.register(track)
        let other = TrackMetadata(
            title: "另一首歌曲",
            artist: "测试艺人",
            albumArtist: "测试艺人",
            album: "测试专辑",
            genre: "流行",
            composer: "作曲者",
            year: 2026,
            trackNumber: 2,
            discNumber: 1
        )
        let contains = await library.contains(other)
        XCTAssertFalse(contains)
    }
}
