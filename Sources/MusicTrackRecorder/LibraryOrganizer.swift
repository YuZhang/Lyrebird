import Foundation
import AVFoundation

struct LibraryOrganizationReport {
    var moved = 0
    var unchanged = 0
    var skipped = 0
    var messages: [String] = []
    var history: LibraryOrganizationHistory?

    var summary: String {
        "Organization complete: moved \(moved), organized \(unchanged), skipped \(skipped)"
    }
}

actor LibraryOrganizer {
    func organize(in directory: URL) async -> LibraryOrganizationReport {
        let plan = await plan(in: directory)
        return await execute(plan)
    }

    func plan(in directory: URL) async -> LibraryOrganizationPlan {
        var messages: [String] = []
        var planItems: [LibraryOrganizationPlan.Item] = []
        let files = Self.audioFiles(in: directory)
        var items: [(source: URL, metadata: TrackMetadata)] = []

        for source in files {
            guard source.pathExtension.lowercased() == "m4a" else {
                planItems.append(.init(
                    kind: .skipped,
                    source: source,
                    destination: source,
                    reason: "Non-M4A file not organized"
                ))
                continue
            }
            do {
                items.append((source, try Self.metadata(for: source)))
            } catch {
                planItems.append(.init(
                    kind: .skipped,
                    source: source,
                    destination: source,
                    reason: error.localizedDescription
                ))
            }
        }

        let allTracks = items.map(\.metadata)
        for item in items {
            let source = item.source
            var metadata = item.metadata
            if metadata.needsCatalogEnrichment {
                do {
                    let duration = AVAsset(url: source).duration.seconds
                    let enriched = try await CatalogMetadataStore.shared.enrich(
                        metadata,
                        duration: duration.isFinite ? duration : 0
                    )
                    if enriched != metadata {
                        messages.append("Catalog metadata enriched: \(metadata.displayText)")
                    }
                    metadata = enriched
                } catch {
                    messages.append("Enrichment failed; using existing metadata: \(metadata.displayText)")
                }
            }

            let directoryInfo = Self.directoryMetadata(for: metadata, allTracks: allTracks)
            let destination = Self.destination(
                for: directoryInfo.metadata,
                in: directory,
                isCompilation: directoryInfo.isCompilation
            )
            if source.standardizedFileURL.path == destination.standardizedFileURL.path {
                planItems.append(.init(
                    kind: .unchanged,
                    source: source,
                    destination: destination,
                    reason: "Already organized"
                ))
            } else if FileManager.default.fileExists(atPath: destination.path) {
                planItems.append(.init(
                    kind: .conflict,
                    source: source,
                    destination: destination,
                    reason: "A file with the same name exists at the destination; not overwritten"
                ))
            } else {
                planItems.append(.init(
                    kind: .move,
                    source: source,
                    destination: destination,
                    reason: "To move"
                ))
            }
        }
        return LibraryOrganizationPlan(directory: directory, items: planItems, messages: messages)
    }

    func execute(_ plan: LibraryOrganizationPlan) async -> LibraryOrganizationReport {
        var report = LibraryOrganizationReport(
            moved: 0,
            unchanged: plan.unchangedCount,
            skipped: 0,
            messages: plan.messages,
            history: nil
        )
        var moves: [LibraryOrganizationMove] = []

        for item in plan.items {
            switch item.kind {
            case .unchanged:
                continue
            case .skipped:
                report.skipped += 1
                report.messages.append("Not organized: \(item.source.lastPathComponent): \(item.reason)")
            case .conflict where !item.keepBoth:
                report.skipped += 1
                report.messages.append("Not organized: \(item.source.lastPathComponent): \(item.reason)")
            case .move, .conflict:
                let destination = item.kind == .conflict
                    ? Self.availableDestination(for: item.destination)
                    : item.destination
                do {
                    let actual = try Self.moveFile(
                        source: item.source,
                        destination: destination,
                        root: plan.directory
                    )
                    report.moved += 1
                    moves.append(.init(source: item.source, destination: actual))
                    report.messages.append(
                        "Organized: \(Self.relativePath(item.source, root: plan.directory)) → \(Self.relativePath(actual, root: plan.directory))"
                    )
                } catch {
                    report.skipped += 1
                    report.messages.append("Not organized: \(item.source.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }
        if !moves.isEmpty {
            report.history = LibraryOrganizationHistory(
                directory: plan.directory,
                date: Date(),
                moves: moves
            )
        }
        return report
    }

    func undo(_ history: LibraryOrganizationHistory) async -> LibraryOrganizationUndoReport {
        var report = LibraryOrganizationUndoReport()
        for move in history.moves.reversed() {
            guard FileManager.default.fileExists(atPath: move.destination.path) else {
                report.skipped += 1
                report.remainingMoves.append(move)
                report.messages.append("Could not undo; organized file is missing: \(move.destination.lastPathComponent)")
                continue
            }
            guard !FileManager.default.fileExists(atPath: move.source.path) else {
                report.skipped += 1
                report.remainingMoves.append(move)
                report.messages.append("Could not undo; a file already exists at the original location: \(move.source.lastPathComponent)")
                continue
            }
            do {
                try FileManager.default.createDirectory(
                    at: move.source.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try FileManager.default.moveItem(at: move.destination, to: move.source)
                Self.removeEmptySourceDirectory(
                    move.destination.deletingLastPathComponent(),
                    root: history.directory
                )
                report.restored += 1
                report.messages.append("Restored: \(move.source.lastPathComponent)")
            } catch {
                report.skipped += 1
                report.remainingMoves.append(move)
                report.messages.append("Could not undo \(move.source.lastPathComponent): \(error.localizedDescription)")
            }
        }
        report.remainingMoves.reverse()
        return report
    }

    static func organizeFile(
        at source: URL,
        metadata: TrackMetadata,
        directory: URL,
        isCompilation: Bool = false
    ) throws -> URL {
        let destination = destination(for: metadata, in: directory, isCompilation: isCompilation)
        return try moveFile(source: source, destination: destination, root: directory)
    }

    static func moveFile(source: URL, destination: URL, root: URL) throws -> URL {
        if source.standardizedFileURL.path == destination.standardizedFileURL.path {
            return source
        }
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw LibraryOrganizationError.sourceMissing
        }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw LibraryOrganizationError.destinationExists
        }

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(at: source, to: destination)
        removeEmptySourceDirectory(source.deletingLastPathComponent(), root: root)
        return destination
    }

    static func availableDestination(for destination: URL) -> URL {
        guard FileManager.default.fileExists(atPath: destination.path) else { return destination }
        let base = destination.deletingPathExtension().lastPathComponent
        let ext = destination.pathExtension
        var suffix = 2
        while true {
            let candidate = destination.deletingLastPathComponent()
                .appendingPathComponent("\(base)-\(suffix)")
                .appendingPathExtension(ext)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            suffix += 1
        }
    }

    static func destination(
        for metadata: TrackMetadata,
        in directory: URL,
        isCompilation: Bool = false
    ) -> URL {
        directory
            .appendingPathComponent(
                TrackFileNaming.albumDirectoryName(for: metadata, isCompilation: isCompilation),
                isDirectory: true
            )
            .appendingPathComponent(TrackFileNaming.fileName(for: metadata))
    }

    static func shouldUseCompilationDirectory(
        for track: TrackMetadata,
        allTracks: [TrackMetadata]
    ) -> Bool {
        directoryTreatment(for: track, allTracks: allTracks).isCompilation
    }

    static func directoryMetadata(
        for track: TrackMetadata,
        allTracks: [TrackMetadata]
    ) -> (metadata: TrackMetadata, isCompilation: Bool) {
        let treatment = directoryTreatment(for: track, allTracks: allTracks)
        guard let artist = treatment.artist,
              CatalogMetadataEnricher.normalize(artist) != CatalogMetadataEnricher.normalize(track.artist) else {
            return (track, treatment.isCompilation)
        }
        return (TrackMetadata(
            title: track.title,
            artist: artist,
            albumArtist: track.albumArtist,
            album: track.album,
            genre: track.genre,
            composer: track.composer,
            year: track.year,
            trackNumber: track.trackNumber,
            discNumber: track.discNumber,
            artworkData: track.artworkData
        ), treatment.isCompilation)
    }

    private static func directoryTreatment(
        for track: TrackMetadata,
        allTracks: [TrackMetadata]
    ) -> (isCompilation: Bool, artist: String?) {
        if track.isCompilation { return (true, nil) }
        guard !track.album.isEmpty else { return (false, nil) }
        let albumName = CatalogMetadataEnricher.normalize(track.album)
        let albumTracks = allTracks.filter {
            CatalogMetadataEnricher.normalize($0.album) == albumName
        }
        if albumTracks.contains(where: { $0.isCompilation }) { return (true, nil) }
        if !track.albumArtist.isEmpty {
            return (false, track.albumArtist)
        }

        var uniqueTracks: [String: TrackMetadata] = [:]
        for candidate in albumTracks where candidate.albumArtist.isEmpty {
            let artist = CatalogMetadataEnricher.normalize(candidate.artist)
            guard !artist.isEmpty else { continue }
            let key = artist + "\u{1F}" + CatalogMetadataEnricher.normalize(candidate.title)
            uniqueTracks[key] = candidate
        }
        let tracks = Array(uniqueTracks.values)
        let counts = Dictionary(grouping: tracks, by: {
            CatalogMetadataEnricher.normalize($0.artist)
        }).mapValues { $0.count }
        guard counts.count > 1 else {
            return (false, tracks.first?.artist)
        }
        if let dominant = counts.max(by: { $0.value < $1.value }),
           dominant.value * 2 > tracks.count,
           let owner = tracks.first(where: {
               CatalogMetadataEnricher.normalize($0.artist) == dominant.key
           })?.artist {
            return (false, owner)
        }

        for primary in counts.keys.sorted() {
            let isOwner = counts.keys.allSatisfy { other in
                other == primary || tracks.contains { candidate in
                    CatalogMetadataEnricher.normalize(candidate.artist) == other
                        && isCollaborationVariant(primary: primary, candidate: candidate)
                }
            }
            if isOwner,
               let owner = tracks.first(where: {
                   CatalogMetadataEnricher.normalize($0.artist) == primary
               })?.artist {
                return (false, owner)
            }
        }
        return (true, nil)
    }

    private static func isCollaborationVariant(primary: String, candidate: TrackMetadata) -> Bool {
        let rawArtist = candidate.artist.lowercased()
        let markers = ["&", "feat", "with", "和", "合唱", "、", "，", ",", "×"]
        guard markers.contains(where: { rawArtist.contains($0) }) else { return false }
        let other = CatalogMetadataEnricher.normalize(candidate.artist)
        return " \(other) ".contains(" \(primary) ")
    }

    static func metadata(for url: URL) throws -> TrackMetadata {
        let asset = AVAsset(url: url)
        let common = asset.commonMetadata
        let iTunes = asset.metadata(forFormat: .iTunesMetadata)
        guard let title = string(for: .commonKeyTitle, in: common), !title.isEmpty else {
            throw LibraryOrganizationError.missingTitle
        }
        return TrackMetadata(
            title: title,
            artist: string(for: .commonKeyArtist, in: common) ?? "",
            albumArtist: string(for: .iTunesMetadataKeyAlbumArtist, in: iTunes) ?? "",
            album: string(for: .commonKeyAlbumName, in: common) ?? "",
            genre: "",
            composer: "",
            year: integer(for: .iTunesMetadataKeyReleaseDate, in: iTunes)
                ?? integer(for: .commonKeyCreationDate, in: common)
                ?? 0,
            trackNumber: integer(for: .iTunesMetadataKeyTrackNumber, in: iTunes) ?? 0,
            discNumber: integer(for: .iTunesMetadataKeyDiscNumber, in: iTunes) ?? 0
        )
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

    private static func string(for key: AVMetadataKey, in items: [AVMetadataItem]) -> String? {
        guard let value = item(for: key, in: items)?.value else { return nil }
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func integer(for key: AVMetadataKey, in items: [AVMetadataItem]) -> Int? {
        guard let value = item(for: key, in: items)?.value else { return nil }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String {
            return Int(string.prefix(4))
        }
        if let data = value as? NSData {
            let bytes = data as Data
            guard bytes.count >= 4 else { return nil }
            return Int(bytes[2]) << 8 | Int(bytes[3])
        }
        return nil
    }

    private static func item(for key: AVMetadataKey, in items: [AVMetadataItem]) -> AVMetadataItem? {
        items.first {
            if $0.commonKey == key || ($0.key as? NSString) == key as NSString {
                return true
            }
            guard let number = $0.key as? NSNumber,
                  let code = fourCharCode(for: key) else { return false }
            return number.int32Value == Int32(bitPattern: code)
        }
    }

    private static func fourCharCode(for key: AVMetadataKey) -> UInt32? {
        let scalars = key.rawValue.unicodeScalars
        guard scalars.count == 4, scalars.allSatisfy({ $0.value <= 0xFF }) else { return nil }
        var values = scalars.map(\.value)
        if values[0] == 0x40 {
            values[0] = 0xA9
        }
        return values.reduce(UInt32(0)) { ($0 << 8) | $1 }
    }

    private static func removeEmptySourceDirectory(_ sourceDirectory: URL, root: URL) {
        let rootPath = root.standardizedFileURL.path
        var current = sourceDirectory.standardizedFileURL
        while current.path != rootPath, current.path.hasPrefix(rootPath + "/") {
            guard let contents = try? FileManager.default.contentsOfDirectory(atPath: current.path),
                  contents.isEmpty else { return }
            try? FileManager.default.removeItem(at: current)
            current = current.deletingLastPathComponent()
        }
    }

    static func relativePath(_ url: URL, root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else { return url.lastPathComponent }
        return String(path.dropFirst(rootPath.count + 1))
    }
}

enum LibraryOrganizationError: LocalizedError {
    case missingTitle
    case sourceMissing
    case destinationExists

    var errorDescription: String? {
        switch self {
        case .missingTitle:
            return "The file has no title metadata"
        case .sourceMissing:
            return "The source file no longer exists"
        case .destinationExists:
            return "A file with the same name exists at the destination; not overwritten"
        }
    }
}
