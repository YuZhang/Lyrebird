import XCTest
@testable import MusicTrackRecorder

final class CatalogMetadataEnricherTests: XCTestCase {
    private let track = TrackMetadata(
        title: "Charlie Brown",
        artist: "Coldplay",
        albumArtist: "Coldplay",
        album: "Mylo Xyloto",
        genre: "",
        composer: "",
        year: 0,
        trackNumber: 0,
        discNumber: 0
    )

    func testHighConfidenceMatchFillsMetadataAndFilePath() throws {
        let enriched = try CatalogMetadataEnricher.enrich(
            track,
            duration: 285.206,
            data: response(trackNumber: 4, discNumber: 1)
        )
        XCTAssertEqual(enriched.year, 2011)
        XCTAssertEqual(enriched.trackNumber, 4)
        XCTAssertEqual(enriched.discNumber, 1)

        let url = TrackFileNaming.makeURL(
            metadata: enriched,
            directory: URL(fileURLWithPath: "/tmp")
        )
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "Coldplay-Mylo Xyloto")
        XCTAssertEqual(url.lastPathComponent, "Disk1-4-Charlie Brown.m4a")
    }

    func testExistingMetadataIsNotOverwritten() throws {
        let existing = TrackMetadata(
            title: track.title,
            artist: track.artist,
            albumArtist: track.albumArtist,
            album: track.album,
            genre: "",
            composer: "",
            year: 2020,
            trackNumber: 9,
            discNumber: 2
        )
        let enriched = try CatalogMetadataEnricher.enrich(
            existing,
            duration: 285.206,
            data: response(trackNumber: 4, discNumber: 1)
        )
        XCTAssertEqual(enriched.year, 2020)
        XCTAssertEqual(enriched.trackNumber, 9)
        XCTAssertEqual(enriched.discNumber, 2)
    }

    func testDifferentAlbumIsRejected() {
        XCTAssertThrowsError(try CatalogMetadataEnricher.enrich(
            track,
            duration: 285.206,
            data: response(album: "Mylo Xyloto (Live)")
        ))
    }

    func testInconsistentMatchesAreRejected() {
        let data = """
        {"resultCount":2,"results":[
            {"trackName":"Charlie Brown","artistName":"Coldplay","collectionName":"Mylo Xyloto","trackNumber":4,"discNumber":1,"releaseDate":"2011-10-19T07:00:00Z","trackTimeMillis":285158},
            {"trackName":"Charlie Brown","artistName":"Coldplay","collectionName":"Mylo Xyloto","trackNumber":5,"discNumber":1,"releaseDate":"2011-10-19T07:00:00Z","trackTimeMillis":285158}
        ]}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try CatalogMetadataEnricher.enrich(
            track,
            duration: 285.206,
            data: data
        ))
    }

    func testCacheKeyDistinguishesPunctuationVariants() {
        func key(title: String) -> String {
            CatalogMetadataStore.cacheKey(for: TrackMetadata(
                title: title,
                artist: "Coldplay",
                albumArtist: "",
                album: "Viva la Vida (Prospekt's March Edition)",
                genre: "",
                composer: "",
                year: 0,
                trackNumber: 0,
                discNumber: 0
            ))
        }
        XCTAssertNotEqual(key(title: "Lost!"), key(title: "Lost+"))
        XCTAssertEqual(key(title: " Lost+ "), key(title: "lost+"))
    }

    func testDiskCacheRestoresMetadataWithoutNetwork() async throws {
        let suite = "LyrebirdTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            return XCTFail("无法创建测试偏好设置")
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let original = track.withArtwork(Data([1, 2, 3]))
        let diskCache = CatalogMetadataDiskCache(defaults: defaults)
        diskCache.save([
            CatalogMetadataStore.cacheKey(for: original): CatalogMetadataEntry(
                year: 2001,
                trackNumber: 9,
                discNumber: 2
            )
        ])

        let store = CatalogMetadataStore(defaults: defaults)
        let restored = try await store.enrich(original, duration: 0)
        XCTAssertEqual(restored.year, 2001)
        XCTAssertEqual(restored.trackNumber, 9)
        XCTAssertEqual(restored.discNumber, 2)
        XCTAssertEqual(restored.artworkData, original.artworkData)
        XCTAssertNotNil(defaults.data(forKey: "catalogMetadataCache.v1"))
    }

    private func response(
        trackNumber: Int = 4,
        discNumber: Int = 1,
        album: String = "Mylo Xyloto"
    ) -> Data {
        """
        {"resultCount":1,"results":[
            {"trackName":"Charlie Brown","artistName":"Coldplay","collectionName":"\(album)","trackNumber":\(trackNumber),"discNumber":\(discNumber),"releaseDate":"2011-10-19T07:00:00Z","trackTimeMillis":285158}
        ]}
        """.data(using: .utf8)!
    }
}
