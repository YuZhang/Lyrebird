import Foundation
import AVFoundation

actor MusicLibrary {
    private var songKeys: Set<String> = []
    private var unidentifiedFileNames: Set<String> = []
    private var observedFiles: Set<URL> = []

    func prepare(in directory: URL) {
        songKeys.removeAll()
        unidentifiedFileNames.removeAll()

        let files = Self.audioFiles(in: directory)
        observedFiles = Set(files)

        for url in files {
            let asset = AVAsset(url: url)
            let metadata = asset.commonMetadata
            if let title = Self.value(for: .commonKeyTitle, in: metadata), !title.isEmpty {
                let artist = Self.value(for: .commonKeyArtist, in: metadata) ?? ""
                let album = Self.value(for: .commonKeyAlbumName, in: metadata) ?? ""
                songKeys.insert(Self.key(title: title, artist: artist, album: album))
            } else {
                unidentifiedFileNames.insert(Self.normalize(url.deletingPathExtension().lastPathComponent))
            }
        }
    }

    func refreshIfNeeded(in directory: URL) {
        guard Set(Self.audioFiles(in: directory)) != observedFiles else { return }
        prepare(in: directory)
    }

    func contains(_ track: TrackMetadata) -> Bool {
        let key = Self.key(title: track.title, artist: track.artist, album: track.album)
        if songKeys.contains(key) { return true }

        let fileName = Self.normalize(TrackFileNaming.sanitizedTitle(track.fileTitle))
        return unidentifiedFileNames.contains {
            $0 == fileName || $0.hasPrefix(fileName + "-")
        }
    }

    func register(_ track: TrackMetadata) {
        songKeys.insert(Self.key(title: track.title, artist: track.artist, album: track.album))
    }

    private static func audioFiles(in directory: URL) -> [URL] {
        let audioExtensions: Set<String> = ["m4a", "mp3", "aac", "wav", "aif", "aiff", "flac"]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return urls.filter { audioExtensions.contains($0.pathExtension.lowercased()) }
    }

    private static func value(
        for key: AVMetadataKey,
        in metadata: [AVMetadataItem]
    ) -> String? {
        metadata.first {
            $0.commonKey == key || ($0.key as? NSString) == key as NSString
        }?.value as? String
    }

    private static func key(title: String, artist: String, album: String) -> String {
        [normalize(title), normalize(artist), normalize(album)].joined(separator: "\u{1F}")
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
