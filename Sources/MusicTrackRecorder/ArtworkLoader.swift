import Foundation

actor ArtworkLoader {
    static let shared = ArtworkLoader()

    private var cache: [String: Data?] = [:]

    func artwork(for track: TrackMetadata) async -> Data? {
        if let artworkData = track.artworkData {
            return artworkData
        }

        let key = "\(track.artist)|\(track.albumArtist)|\(track.title)|\(track.album)"
        if let cached = cache[key] {
            return cached
        }

        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: "\(track.artist) \(track.title)"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "1")
        ]
        guard let url = components.url else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(SearchResponse.self, from: data)
            guard let artworkURLString = response.results.first?.artworkUrl100,
                  let artworkURL = URL(string: artworkURLString.replacingOccurrences(
                    of: "100x100bb.jpg",
                    with: "600x600bb.jpg"
                  )) else {
                cache.updateValue(nil, forKey: key)
                return nil
            }

            let (imageData, _) = try await URLSession.shared.data(from: artworkURL)
            cache.updateValue(imageData, forKey: key)
            return imageData
        } catch {
            cache.updateValue(nil, forKey: key)
            return nil
        }
    }
}

private struct SearchResponse: Decodable {
    struct Track: Decodable {
        let artworkUrl100: String
    }

    let results: [Track]
}
