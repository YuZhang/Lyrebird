import Foundation
import AVFoundation

actor MusicLibrary {
    private var songKeys: Set<String> = []
    private var unidentifiedFileNames: Set<String> = []
    private var observedFiles: Set<URL> = []
    private var songKeysByFile: [URL: String] = [:]
    private var unidentifiedNamesByFile: [URL: String] = [:]

    func prepare(in directory: URL) {
        let files = Self.audioFiles(in: directory)
        observedFiles = Set(files)
        songKeysByFile.removeAll()
        unidentifiedNamesByFile.removeAll()

        for url in files {
            indexFile(at: url)
        }
        rebuildIndexes()
    }

    func refreshIfNeeded(in directory: URL) {
        let currentFiles = Set(Self.audioFiles(in: directory))
        guard currentFiles != observedFiles else { return }

        for url in observedFiles.subtracting(currentFiles) {
            songKeysByFile.removeValue(forKey: url)
            unidentifiedNamesByFile.removeValue(forKey: url)
        }
        for url in currentFiles.subtracting(observedFiles) {
            indexFile(at: url)
        }
        observedFiles = currentFiles
        rebuildIndexes()
    }

    func contains(_ track: TrackMetadata) -> Bool {
        let key = Self.key(title: track.title, artist: track.artist, album: track.album)
        if songKeys.contains(key) { return true }

        let fileName = Self.normalize((TrackFileNaming.fileName(for: track) as NSString).deletingPathExtension)
        let legacyFileName = Self.normalize(TrackFileNaming.sanitizedTitle(track.fileTitle))
        return unidentifiedFileNames.contains {
            $0 == fileName || $0.hasPrefix(fileName + "-")
                || $0 == legacyFileName || $0.hasPrefix(legacyFileName + "-")
        }
    }

    func register(_ track: TrackMetadata, at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        observedFiles.insert(url)
        unidentifiedNamesByFile.removeValue(forKey: url)
        songKeysByFile[url] = Self.key(title: track.title, artist: track.artist, album: track.album)
        rebuildIndexes()
    }

    private func indexFile(at url: URL) {
        let asset = AVAsset(url: url)
        let metadata = asset.commonMetadata
        if let title = Self.value(for: .commonKeyTitle, in: metadata), !title.isEmpty {
            let artist = Self.value(for: .commonKeyArtist, in: metadata) ?? ""
            let album = Self.value(for: .commonKeyAlbumName, in: metadata) ?? ""
            songKeysByFile[url] = Self.key(title: title, artist: artist, album: album)
        } else {
            unidentifiedNamesByFile[url] = Self.normalize(url.deletingPathExtension().lastPathComponent)
        }
    }

    private func rebuildIndexes() {
        songKeys = Set(songKeysByFile.values)
        unidentifiedFileNames = Set(unidentifiedNamesByFile.values)
    }

    private static func audioFiles(in directory: URL) -> [URL] {
        let audioExtensions: Set<String> = ["m4a", "mp3", "aac", "wav", "aif", "aiff", "flac"]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter {
            audioExtensions.contains($0.pathExtension.lowercased())
        }
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
        let equivalentCharacters = TrackFileNaming.forbiddenCharacters
            .union(CharacterSet(charactersIn: "_"))
        return value
            .components(separatedBy: equivalentCharacters)
            .joined(separator: "-")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
