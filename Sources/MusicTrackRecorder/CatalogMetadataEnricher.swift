import Foundation

struct CatalogMetadataEnricher {
    private struct SearchResponse: Decodable {
        let results: [CatalogTrack]
    }

    private struct CatalogTrack: Decodable {
        let trackName: String
        let artistName: String
        let collectionArtistName: String?
        let collectionName: String
        let trackNumber: Int?
        let discNumber: Int?
        let releaseDate: String?
        let trackTimeMillis: Int?
    }

    private struct CatalogValues: Equatable {
        let year: Int
        let trackNumber: Int
        let discNumber: Int
    }

    static func enrich(
        _ track: TrackMetadata,
        duration: Double,
        data: Data
    ) throws -> TrackMetadata {
        let response = try JSONDecoder().decode(SearchResponse.self, from: data)
        let artist = track.artist.isEmpty ? track.albumArtist : track.artist
        let matches = response.results.filter { result in
            Self.normalize(result.trackName) == Self.normalize(track.title)
                && Self.normalize(result.collectionName) == Self.normalize(track.album)
                && Self.artistMatches(result, artist: artist)
                && Self.durationMatches(result.trackTimeMillis, duration: duration)
        }
        guard !matches.isEmpty else { throw CatalogMetadataError.noReliableMatch }

        let values = matches.map { result in
            CatalogValues(
                year: Self.year(from: result.releaseDate),
                trackNumber: result.trackNumber ?? 0,
                discNumber: result.discNumber ?? 0
            )
        }
        guard let first = values.first, values.allSatisfy({ $0 == first }) else {
            throw CatalogMetadataError.ambiguousMatch
        }

        return track.applyingCatalogMetadata(
            year: first.year,
            trackNumber: first.trackNumber,
            discNumber: first.discNumber
        )
    }

    private static func artistMatches(_ result: CatalogTrack, artist: String) -> Bool {
        let expected = normalize(artist)
        return [result.artistName, result.collectionArtistName]
            .compactMap { $0 }
            .contains { normalize($0) == expected }
    }

    private static func durationMatches(_ milliseconds: Int?, duration: Double) -> Bool {
        guard let milliseconds, duration > 0 else { return true }
        return abs(Double(milliseconds) / 1_000 - duration) <= 5
    }

    private static func year(from releaseDate: String?) -> Int {
        guard let releaseDate, releaseDate.count >= 4 else { return 0 }
        return Int(releaseDate.prefix(4)) ?? 0
    }

    static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

struct CatalogMetadataEntry: Codable, Equatable {
    let year: Int
    let trackNumber: Int
    let discNumber: Int
}

struct CatalogMetadataDiskCache {
    let defaults: UserDefaults
    let key: String

    init(defaults: UserDefaults = .standard, key: String = "catalogMetadataCache.v1") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> [String: CatalogMetadataEntry] {
        guard let data = defaults.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: CatalogMetadataEntry].self, from: data)) ?? [:]
    }

    func save(_ cache: [String: CatalogMetadataEntry]) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        defaults.set(data, forKey: key)
    }
}

actor CatalogMetadataStore {
    static let shared = CatalogMetadataStore()

    private var cache: [String: CatalogMetadataEntry]
    private let diskCache: CatalogMetadataDiskCache

    init(defaults: UserDefaults = .standard) {
        let diskCache = CatalogMetadataDiskCache(defaults: defaults)
        self.diskCache = diskCache
        cache = diskCache.load()
    }

    func enrich(_ track: TrackMetadata, duration: Double) async throws -> TrackMetadata {
        guard track.needsCatalogEnrichment else { return track }
        let key = Self.cacheKey(for: track)
        if let cached = cache[key] {
            return track.applyingCatalogMetadata(
                year: cached.year,
                trackNumber: cached.trackNumber,
                discNumber: cached.discNumber
            )
        }

        let artist = track.artist.isEmpty ? track.albumArtist : track.artist
        guard !track.title.isEmpty, !artist.isEmpty, !track.album.isEmpty else {
            throw CatalogMetadataError.insufficientInformation
        }
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: "\(artist) \(track.title) \(track.album)"),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "20")
        ]
        guard let url = components?.url else { throw CatalogMetadataError.invalidResponse }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw CatalogMetadataError.invalidResponse
        }

        let enriched = try CatalogMetadataEnricher.enrich(track, duration: duration, data: data)
        cache[key] = CatalogMetadataEntry(
            year: enriched.year,
            trackNumber: enriched.trackNumber,
            discNumber: enriched.discNumber
        )
        diskCache.save(cache)
        return enriched
    }

    static func cacheKey(for track: TrackMetadata) -> String {
        [track.title, track.artist, track.albumArtist, track.album]
            .map { value in
                value
                    .precomposedStringWithCanonicalMapping
                    .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                    .components(separatedBy: .whitespacesAndNewlines)
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            }
            .joined(separator: "\u{1F}")
    }
}

enum CatalogMetadataError: LocalizedError {
    case insufficientInformation
    case noReliableMatch
    case ambiguousMatch
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .insufficientInformation:
            return "Insufficient title, artist, or album information"
        case .noReliableMatch:
            return "No consistent catalog track found"
        case .ambiguousMatch:
            return "Multiple inconsistent catalog versions found"
        case .invalidResponse:
            return "The Apple catalog returned an invalid response"
        }
    }
}
