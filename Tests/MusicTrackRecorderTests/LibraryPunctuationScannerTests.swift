import XCTest
@testable import MusicTrackRecorder

final class LibraryPunctuationScannerTests: XCTestCase {
    func testGroupsOnlyPunctuationVariantsWithinSameAlbum() {
        let items = [
            item(title: "Lost!"),
            item(title: "Lost+"),
            item(title: "Charlie Brown"),
            item(title: "Lost!", album: "Another Album")
        ]
        let groups = LibraryPunctuationScanner.conflictGroups(for: items)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].normalizedTitle, "lost")
        XCTAssertEqual(Set(groups[0].items.map { $0.metadata.title }), Set(["Lost!", "Lost+"]))
    }

    func testSameTitleAtDifferentPathsDoesNotCreateConflict() {
        let groups = LibraryPunctuationScanner.conflictGroups(for: [
            item(title: "Song", path: "/tmp/A/Song.m4a"),
            item(title: "Song", path: "/tmp/B/Song.m4a")
        ])
        XCTAssertTrue(groups.isEmpty)
    }

    private func item(
        title: String,
        album: String = "Viva la Vida (Prospekt's March Edition)",
        path: String? = nil
    ) -> LibraryPunctuationScanner.Item {
        LibraryPunctuationScanner.Item(
            metadata: TrackMetadata(
                title: title,
                artist: "Coldplay",
                albumArtist: "",
                album: album,
                genre: "",
                composer: "",
                year: 0,
                trackNumber: 0,
                discNumber: 0
            ),
            path: path ?? "/tmp/\(title).m4a"
        )
    }
}
