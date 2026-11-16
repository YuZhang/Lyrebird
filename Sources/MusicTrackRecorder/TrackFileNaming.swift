import Foundation

enum TrackFileNaming {
    static let forbiddenCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        .union(.controlCharacters)

    static func sanitizedTitle(_ title: String) -> String {
        let cleaned = title
            .components(separatedBy: forbiddenCharacters)
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "音轨" : String(cleaned.prefix(80))
    }

    static func albumDirectoryName(for metadata: TrackMetadata, isCompilation: Bool = false) -> String {
        let album = metadata.album.isEmpty ? "未知专辑" : metadata.album
        if isCompilation || metadata.isCompilation {
            return "合集-\(sanitizedTitle(album))"
        }
        let artist = metadata.artist.isEmpty ? metadata.albumArtist : metadata.artist
        return [
            sanitizedTitle(artist.isEmpty ? "未知歌手" : artist),
            sanitizedTitle(album)
        ].joined(separator: "-")
    }

    static func fileName(for metadata: TrackMetadata) -> String {
        var prefix = ""
        if metadata.discNumber > 0 {
            prefix += "Disk\(metadata.discNumber)-"
        }
        if metadata.trackNumber > 0 {
            prefix += "\(metadata.trackNumber)-"
        }
        return "\(prefix)\(sanitizedTitle(metadata.title)).m4a"
    }

    static func makeURL(metadata: TrackMetadata, directory: URL) -> URL {
        let albumDirectory = directory.appendingPathComponent(
            albumDirectoryName(for: metadata),
            isDirectory: true
        )
        let name = fileName(for: metadata)
        let base = (name as NSString).deletingPathExtension
        var candidate = albumDirectory.appendingPathComponent(name)
        var suffix = 2

        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = albumDirectory
                .appendingPathComponent("\(base)-\(suffix)")
                .appendingPathExtension("m4a")
            suffix += 1
        }
        return candidate
    }

    static func makeURL(title: String, date: Date = Date(), directory: URL) -> URL {
        let base = sanitizedTitle(title)
        var candidate = directory.appendingPathComponent(base).appendingPathExtension("m4a")
        var suffix = 2

        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory
                .appendingPathComponent("\(base)-\(suffix)")
                .appendingPathExtension("m4a")
            suffix += 1
        }
        return candidate
    }

    static func temporaryURL(for finalURL: URL) -> URL {
        finalURL.appendingPathExtension("tmp")
    }

    static func elapsedText(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainder = seconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, remainder)
    }

    static func shortTime(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainder = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainder)
        }
        return String(format: "%d:%02d", minutes, remainder)
    }
}
