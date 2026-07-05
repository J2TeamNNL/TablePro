import Foundation
import TableProPluginKit

struct RecentTableEntry: Codable, Equatable, Identifiable {
    let database: String?
    let schema: String?
    let name: String
    let openedAt: Date

    static func identityKey(schema: String?, name: String) -> String {
        "\(schema ?? "")\u{1}\(name)"
    }

    var scopeKey: String { database ?? "" }

    var identityKey: String { Self.identityKey(schema: schema, name: name) }

    var id: String { "\(scopeKey)\u{1}\(identityKey)" }
}

struct RecentTableRow: Identifiable {
    let table: TableInfo

    var id: String { "recent\u{1}\(table.id)" }
}

@MainActor
final class RecentTablesStore {
    static let shared = RecentTablesStore()

    static let perDatabaseCap = 10

    private let defaults: UserDefaults
    private let keyPrefix = "RecentTables.v1."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func entries(connectionId: UUID) -> [RecentTableEntry] {
        guard let data = defaults.data(forKey: storageKey(connectionId)) else { return [] }
        return (try? JSONDecoder().decode([RecentTableEntry].self, from: data)) ?? []
    }

    @discardableResult
    func record(connectionId: UUID, database: String?, schema: String?, name: String, at date: Date = Date()) -> [RecentTableEntry] {
        let entry = RecentTableEntry(database: database, schema: schema, name: name, openedAt: date)
        let updated = Self.merged(entry, into: entries(connectionId: connectionId))
        persist(updated, connectionId: connectionId)
        return updated
    }

    @discardableResult
    func remove(connectionId: UUID, entry: RecentTableEntry) -> [RecentTableEntry] {
        let updated = entries(connectionId: connectionId).filter { $0.id != entry.id }
        persist(updated, connectionId: connectionId)
        return updated
    }

    func clear(connectionId: UUID) {
        defaults.removeObject(forKey: storageKey(connectionId))
    }

    static func merged(_ entry: RecentTableEntry, into existing: [RecentTableEntry]) -> [RecentTableEntry] {
        var result = existing.filter { $0.id != entry.id }
        result.insert(entry, at: 0)
        var perScopeCount: [String: Int] = [:]
        return result.filter { candidate in
            let count = perScopeCount[candidate.scopeKey, default: 0]
            guard count < perDatabaseCap else { return false }
            perScopeCount[candidate.scopeKey] = count + 1
            return true
        }
    }

    private func persist(_ entries: [RecentTableEntry], connectionId: UUID) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: storageKey(connectionId))
    }

    private func storageKey(_ connectionId: UUID) -> String {
        keyPrefix + connectionId.uuidString
    }
}
