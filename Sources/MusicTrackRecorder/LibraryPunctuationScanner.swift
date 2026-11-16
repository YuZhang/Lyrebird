import Foundation
import AVFoundation

actor LibraryPunctuationScanner {
    struct Item {
        let metadata: TrackMetadata
        let path: String
    }

    struct Group {
        let normalizedTitle: String
        let items: [Item]
    }

    func scan(in directory: URL) async -> String {
        var items: [Item] = []
        var unreadable: [String] = []
        var total = 0
        if let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            while let url = enumerator.nextObject() as? URL {
                guard url.pathExtension.lowercased() == "m4a" else { continue }
                total += 1
                do {
                    items.append(Item(
                        metadata: try LibraryOrganizer.metadata(for: url),
                        path: url.path
                    ))
                } catch {
                    unreadable.append(url.path)
                }
            }
        }

        let groups = Self.conflictGroups(for: items)
        var lines = [
            "Punctuation Conflict Scan",
            "Folder: \(directory.path)",
            "Files scanned: \(total)",
            "Unreadable: \(unreadable.count)",
            ""
        ]
        if groups.isEmpty {
            lines.append("No songs in the same album differ only by punctuation.")
        } else {
            lines.append("Found \(groups.count) punctuation variant groups:")
            for (index, group) in groups.enumerated() {
                guard let first = group.items.first else { continue }
                lines.append("")
                lines.append("\(index + 1). \(group.items.map { $0.metadata.title }.joined(separator: " / "))")
                lines.append("   Artist: \(first.metadata.artist)")
                lines.append("   Album: \(first.metadata.album)")
                lines.append("   Normalized title: \(group.normalizedTitle)")
                for item in group.items {
                    lines.append("   \(item.metadata.title)")
                    lines.append("   \(item.path)")
                }
            }
        }
        if !unreadable.isEmpty {
            lines.append("")
            lines.append("Unreadable files:")
            lines.append(contentsOf: unreadable.map { "   \($0)" })
        }
        return lines.joined(separator: "\n")
    }

    static func conflictGroups(for items: [Item]) -> [Group] {
        let grouped = Dictionary(grouping: items) { item -> String in
            let components = [
                item.metadata.title,
                item.metadata.artist,
                item.metadata.albumArtist,
                item.metadata.album
            ]
            return components
                .map { CatalogMetadataEnricher.normalize($0) }
                .joined(separator: "\u{1F}")
        }
        let variants = grouped.values.filter {
            Set($0.map { $0.metadata.title }).count > 1
        }
        return variants.map { items in
            Group(
                normalizedTitle: CatalogMetadataEnricher.normalize(items[0].metadata.title),
                items: items.sorted {
                    if $0.metadata.title == $1.metadata.title {
                        return $0.path < $1.path
                    }
                    return $0.metadata.title < $1.metadata.title
                }
            )
        }
        .sorted { $0.normalizedTitle < $1.normalizedTitle }
    }
}
