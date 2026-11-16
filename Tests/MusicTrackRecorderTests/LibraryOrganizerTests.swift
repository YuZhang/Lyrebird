import XCTest
@testable import MusicTrackRecorder

final class LibraryOrganizerTests: XCTestCase {
    func testMovesFileAndRemovesEmptyLegacyDirectory() throws {
        let root = try testDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let legacy = root.appendingPathComponent("Legacy", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        let source = legacy.appendingPathComponent("Old Name.m4a")
        try Data("audio".utf8).write(to: source)

        let destination = try LibraryOrganizer.organizeFile(
            at: source,
            metadata: metadata(),
            directory: root
        )
        XCTAssertEqual(destination.lastPathComponent, "Disk1-5-Song.m4a")
        XCTAssertEqual(destination.deletingLastPathComponent().lastPathComponent, "Artist-Album")
        XCTAssertEqual(try Data(contentsOf: destination), Data("audio".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
    }

    func testOrganizerUsesUnderscorePlaceholders() throws {
        let root = try testDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Old.m4a")
        try Data("audio".utf8).write(to: source)
        let unsafe = TrackMetadata(
            title: "Song:A/B",
            artist: "A/B",
            albumArtist: "A/B",
            album: "Live:One",
            genre: "",
            composer: "",
            year: 0,
            trackNumber: 5,
            discNumber: 1
        )
        let destination = try LibraryOrganizer.organizeFile(
            at: source,
            metadata: unsafe,
            directory: root
        )
        XCTAssertEqual(destination.deletingLastPathComponent().lastPathComponent, "A_B-Live_One")
        XCTAssertEqual(destination.lastPathComponent, "Disk1-5-Song_A_B.m4a")
    }

    func testAlreadyOrganizedFileIsNotTouched() throws {
        let root = try testDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = LibraryOrganizer.destination(for: metadata(), in: root)
        try FileManager.default.createDirectory(
            at: source.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("audio".utf8).write(to: source)
        let date = Date(timeIntervalSince1970: 1_600_000_000)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: source.path)

        let result = try LibraryOrganizer.organizeFile(
            at: source,
            metadata: metadata(),
            directory: root
        )
        XCTAssertEqual(result, source)
        let attributes = try FileManager.default.attributesOfItem(atPath: source.path)
        XCTAssertEqual(attributes[.modificationDate] as? Date, date)
    }

    func testDestinationConflictNeverOverwritesEitherFile() throws {
        let root = try testDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Old.m4a")
        try Data("source".utf8).write(to: source)
        let destination = LibraryOrganizer.destination(for: metadata(), in: root)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("destination".utf8).write(to: destination)

        XCTAssertThrowsError(try LibraryOrganizer.organizeFile(
            at: source,
            metadata: metadata(),
            directory: root
        ))
        XCTAssertEqual(try Data(contentsOf: source), Data("source".utf8))
        XCTAssertEqual(try Data(contentsOf: destination), Data("destination".utf8))
    }

    func testNonM4AFileIsSkippedWithoutChanges() async throws {
        let root = try testDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Song.mp3")
        try Data("audio".utf8).write(to: source)

        let report = await LibraryOrganizer().organize(in: root)
        XCTAssertEqual(report.skipped, 1)
        XCTAssertEqual(report.moved, 0)
        XCTAssertEqual(try Data(contentsOf: source), Data("audio".utf8))
    }

    func testMultipleArtistsUseOneCompilationDirectory() {
        let first = metadata(artist: "Artist A", albumArtist: "")
        let second = metadata(artist: "Artist B", albumArtist: "")
        let tracks = [first, second]
        XCTAssertTrue(LibraryOrganizer.shouldUseCompilationDirectory(for: first, allTracks: tracks))
        XCTAssertTrue(LibraryOrganizer.shouldUseCompilationDirectory(for: second, allTracks: tracks))
        let destination = LibraryOrganizer.destination(
            for: first,
            in: URL(fileURLWithPath: "/tmp"),
            isCompilation: true
        )
        XCTAssertEqual(destination.deletingLastPathComponent().lastPathComponent, "合集-Album")
    }

    func testSingleArtistAlbumDoesNotBecomeCompilation() {
        let first = metadata(artist: "Artist", albumArtist: "Shared Artist")
        let second = metadata(artist: "Artist", albumArtist: "Shared Artist")
        XCTAssertFalse(LibraryOrganizer.shouldUseCompilationDirectory(
            for: first,
            allTracks: [first, second]
        ))
    }

    func testExecutePlanAndUndoRestoreOriginalLocation() async throws {
        let root = try testDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Old.m4a")
        let destination = root.appendingPathComponent("Artist-Album/Disk1-5-Song.m4a")
        try Data("audio".utf8).write(to: source)
        let plan = LibraryOrganizationPlan(
            directory: root,
            items: [.init(kind: .move, source: source, destination: destination, reason: "To move")],
            messages: []
        )
        let organizer = LibraryOrganizer()
        let report = await organizer.execute(plan)
        XCTAssertEqual(report.moved, 1)
        XCTAssertEqual(report.history?.moves.count, 1)
        XCTAssertEqual(try Data(contentsOf: destination), Data("audio".utf8))

        let undo = await organizer.undo(try XCTUnwrap(report.history))
        XCTAssertEqual(undo.restored, 1)
        XCTAssertTrue(undo.remainingMoves.isEmpty)
        XCTAssertEqual(try Data(contentsOf: source), Data("audio".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testConflictCanSkipOrKeepBothWithoutOverwriting() async throws {
        let root = try testDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Old.m4a")
        let destination = root.appendingPathComponent("Artist-Album/Disk1-5-Song.m4a")
        try Data("source".utf8).write(to: source)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("destination".utf8).write(to: destination)
        let organizer = LibraryOrganizer()

        let skipPlan = LibraryOrganizationPlan(
            directory: root,
            items: [.init(kind: .conflict, source: source, destination: destination, reason: "Conflict")],
            messages: []
        )
        let skipped = await organizer.execute(skipPlan)
        XCTAssertEqual(skipped.skipped, 1)
        XCTAssertEqual(try Data(contentsOf: source), Data("source".utf8))

        let keepPlan = LibraryOrganizationPlan(
            directory: root,
            items: [.init(kind: .conflict, source: source, destination: destination, reason: "Conflict", keepBoth: true)],
            messages: []
        )
        let kept = await organizer.execute(keepPlan)
        XCTAssertEqual(kept.moved, 1)
        XCTAssertEqual(kept.history?.moves.first?.destination.lastPathComponent, "Disk1-5-Song-2.m4a")
        XCTAssertEqual(try Data(contentsOf: destination), Data("destination".utf8))
        XCTAssertEqual(try Data(contentsOf: destination.deletingLastPathComponent().appendingPathComponent("Disk1-5-Song-2.m4a")), Data("source".utf8))
    }

    func testUndoNeverOverwritesNewFileAtOriginalLocation() async throws {
        let root = try testDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Old.m4a")
        let destination = root.appendingPathComponent("Artist-Album/Disk1-5-Song.m4a")
        try Data("original".utf8).write(to: source)
        let plan = LibraryOrganizationPlan(
            directory: root,
            items: [.init(kind: .move, source: source, destination: destination, reason: "To move")],
            messages: []
        )
        let organizer = LibraryOrganizer()
        let report = await organizer.execute(plan)
        try Data("new".utf8).write(to: source)

        let undo = await organizer.undo(try XCTUnwrap(report.history))
        XCTAssertEqual(undo.skipped, 1)
        XCTAssertEqual(undo.remainingMoves.count, 1)
        XCTAssertEqual(try Data(contentsOf: source), Data("new".utf8))
        XCTAssertEqual(try Data(contentsOf: destination), Data("original".utf8))
    }

    func testOrganizationHistoryPersists() throws {
        let suite = "LyrebirdTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LibraryOrganizationHistoryStore(defaults: defaults)
        let history = LibraryOrganizationHistory(
            directory: URL(fileURLWithPath: "/tmp/Music"),
            date: Date(),
            moves: [.init(source: URL(fileURLWithPath: "/tmp/Old.m4a"), destination: URL(fileURLWithPath: "/tmp/New.m4a"))]
        )
        store.save(history)
        XCTAssertEqual(store.load(), history)
        store.clear()
        XCTAssertNil(store.load())
    }

    func testSingleArtistAlbumWithCollaborationTrackIsNotCompilation() {
        let duet = metadata(title: "Duet", artist: "Coldplay & Rihanna", albumArtist: "")
        let tracks = [
            metadata(title: "One", artist: "Coldplay", albumArtist: ""),
            metadata(title: "Two", artist: "Coldplay", albumArtist: ""),
            duet
        ]
        for track in tracks {
            XCTAssertFalse(LibraryOrganizer.shouldUseCompilationDirectory(for: track, allTracks: tracks))
        }
        let directory = LibraryOrganizer.directoryMetadata(for: duet, allTracks: tracks)
        XCTAssertEqual(directory.metadata.artist, "Coldplay")
        let url = LibraryOrganizer.destination(
            for: directory.metadata,
            in: URL(fileURLWithPath: "/tmp"),
            isCompilation: directory.isCompilation
        )
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "Coldplay-Album")
    }

    func testSoloAndCollaborationPairStillHasSingleAlbumOwner() {
        let tracks = [
            metadata(title: "Solo", artist: "Coldplay", albumArtist: ""),
            metadata(title: "Duet", artist: "Coldplay & Rihanna", albumArtist: "")
        ]
        XCTAssertFalse(LibraryOrganizer.shouldUseCompilationDirectory(for: tracks[1], allTracks: tracks))
        XCTAssertEqual(
            LibraryOrganizer.directoryMetadata(for: tracks[1], allTracks: tracks).metadata.artist,
            "Coldplay"
        )
    }

    func testExplicitAlbumArtistKeepsFeaturedTrackInSameDirectory() {
        let tracks = [
            metadata(title: "Solo", artist: "Coldplay", albumArtist: "Coldplay"),
            metadata(title: "Duet", artist: "Coldplay & Rihanna", albumArtist: "Coldplay")
        ]
        XCTAssertFalse(LibraryOrganizer.shouldUseCompilationDirectory(for: tracks[1], allTracks: tracks))
        XCTAssertEqual(
            LibraryOrganizer.directoryMetadata(for: tracks[1], allTracks: tracks).metadata.artist,
            "Coldplay"
        )
    }

    private func metadata(
        title: String = "Song",
        artist: String = "Artist",
        albumArtist: String? = nil
    ) -> TrackMetadata {
        TrackMetadata(
            title: title,
            artist: artist,
            albumArtist: albumArtist ?? artist,
            album: "Album",
            genre: "",
            composer: "",
            year: 2011,
            trackNumber: 5,
            discNumber: 1
        )
    }

    private func testDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
