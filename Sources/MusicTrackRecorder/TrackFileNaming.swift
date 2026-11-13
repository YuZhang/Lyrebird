import Foundation

enum TrackFileNaming {
    static func sanitizedTitle(_ title: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = title
            .components(separatedBy: forbidden)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "音轨" : String(cleaned.prefix(80))
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
