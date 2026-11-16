import XCTest
@testable import MusicTrackRecorder

final class MusicLibraryTests: XCTestCase {
    private let punctuationTrack = TrackMetadata(
        title: "Song:A/B",
        artist: "Artist",
        albumArtist: "Artist",
        album: "Album",
        genre: "",
        composer: "",
        year: 2026,
        trackNumber: 3,
        discNumber: 0
    )

    func testUnderscoreFileNameMatchesForbiddenTitleCharacters() async throws {
        try await assertPunctuationTrackExists(as: "3-Song_A_B.m4a")
    }

    func testLegacyHyphenFileNameStillMatchesForbiddenTitleCharacters() async throws {
        try await assertPunctuationTrackExists(as: "Artist - Song-A-B.m4a")
    }

    func testMetadataComparisonTreatsUnderscoreAsForbiddenPlaceholder() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Song.m4a")
        FileManager.default.createFile(atPath: file.path, contents: Data())
        let library = MusicLibrary()
        let sanitized = TrackMetadata(
            title: "Song_A_B",
            artist: punctuationTrack.artist,
            albumArtist: punctuationTrack.albumArtist,
            album: punctuationTrack.album,
            genre: "",
            composer: "",
            year: 2026,
            trackNumber: 3,
            discNumber: 0
        )
        await library.register(sanitized, at: file)
        let contains = await library.contains(punctuationTrack)
        XCTAssertTrue(contains)
    }

    private func assertPunctuationTrackExists(as fileName: String) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        FileManager.default.createFile(
            atPath: directory.appendingPathComponent(fileName).path,
            contents: Data()
        )
        let library = MusicLibrary()
        await library.prepare(in: directory)
        let contains = await library.contains(punctuationTrack)
        XCTAssertTrue(contains)
    }

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

    func testNestedAlbumFilePreventsDuplicateAndRefreshesAfterDeletion() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let existing = TrackFileNaming.makeURL(metadata: track, directory: directory)
        try FileManager.default.createDirectory(
            at: existing.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
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

    func testCompletedTrackIsRegistered() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Song.m4a")
        FileManager.default.createFile(atPath: file.path, contents: Data())

        let library = MusicLibrary()
        let before = await library.contains(track)
        XCTAssertFalse(before)

        await library.register(track, at: file)
        let after = await library.contains(track)
        XCTAssertTrue(after)
    }

    func testMissingFileCannotBeRegistered() async {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        let library = MusicLibrary()
        await library.register(track, at: missing)
        let contains = await library.contains(track)
        XCTAssertFalse(contains)
    }

    func testDifferentSongIsNotDuplicate() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Song.m4a")
        FileManager.default.createFile(atPath: file.path, contents: Data())
        let library = MusicLibrary()
        await library.register(track, at: file)
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
