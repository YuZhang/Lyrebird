import Foundation

struct LibraryOrganizationPlan: Identifiable {
    struct Item: Identifiable {
        enum Kind {
            case move
            case unchanged
            case conflict
            case skipped
        }

        let id = UUID()
        let kind: Kind
        let source: URL
        let destination: URL
        let reason: String
        var keepBoth = false
    }

    let id = UUID()
    let directory: URL
    let createdAt = Date()
    var items: [Item]
    let messages: [String]

    var moveCount: Int { items.filter { $0.kind == .move }.count }
    var unchangedCount: Int { items.filter { $0.kind == .unchanged }.count }
    var conflictCount: Int { items.filter { $0.kind == .conflict }.count }
    var skippedCount: Int { items.filter { $0.kind == .skipped }.count }
    var pendingMoveCount: Int {
        items.filter { $0.kind == .move || ($0.kind == .conflict && $0.keepBoth) }.count
    }
}

struct LibraryOrganizationMove: Codable, Equatable {
    let source: URL
    let destination: URL
}

struct LibraryOrganizationHistory: Codable, Equatable {
    let directory: URL
    let date: Date
    let moves: [LibraryOrganizationMove]
}

struct LibraryOrganizationHistoryStore {
    let defaults: UserDefaults
    let key: String

    init(defaults: UserDefaults = .standard, key: String = "lastLibraryOrganization.v1") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> LibraryOrganizationHistory? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(LibraryOrganizationHistory.self, from: data)
    }

    func save(_ history: LibraryOrganizationHistory) {
        guard let data = try? JSONEncoder().encode(history) else { return }
        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}

struct LibraryOrganizationUndoReport {
    var restored = 0
    var skipped = 0
    var messages: [String] = []
    var remainingMoves: [LibraryOrganizationMove] = []

    var summary: String {
        "Undo complete: restored \(restored), skipped \(skipped)"
    }
}
