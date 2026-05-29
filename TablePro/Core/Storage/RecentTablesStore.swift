import Foundation

extension Notification.Name {
    static let recentTablesDidChange = Notification.Name("RecentTablesDidChange")
}

@MainActor
final class RecentTablesStore {
    static let shared = RecentTablesStore()

    struct Key: Hashable {
        let connectionID: UUID
        let database: String?
    }

    struct Entry: Hashable, Identifiable {
        let name: String
        let schema: String?
        let type: TableInfo.TableType
        let lastAccessedAt: Date

        var id: String { schema.map { "\($0).\(name)" } ?? name }
    }

    private var entriesByKey: [Key: [Entry]] = [:]
    private let cap = 10

    init() {}

    func push(connectionID: UUID, database: String?, table: TableInfo) {
        let key = Key(connectionID: connectionID, database: database)
        var list = entriesByKey[key] ?? []
        let newEntryId = entryId(name: table.name, schema: table.schema)
        list.removeAll { $0.id == newEntryId }
        list.insert(
            Entry(
                name: table.name,
                schema: table.schema,
                type: table.type,
                lastAccessedAt: Date()
            ),
            at: 0
        )
        if list.count > cap {
            list = Array(list.prefix(cap))
        }
        entriesByKey[key] = list
        NotificationCenter.default.post(name: .recentTablesDidChange, object: nil)
    }

    func entries(connectionID: UUID, database: String?) -> [Entry] {
        entriesByKey[Key(connectionID: connectionID, database: database)] ?? []
    }

    func clear(connectionID: UUID, database: String?) {
        entriesByKey.removeValue(forKey: Key(connectionID: connectionID, database: database))
        NotificationCenter.default.post(name: .recentTablesDidChange, object: nil)
    }

    func clearAll() {
        entriesByKey.removeAll()
        NotificationCenter.default.post(name: .recentTablesDidChange, object: nil)
    }

    var cappedSize: Int { cap }

    private func entryId(name: String, schema: String?) -> String {
        schema.map { "\($0).\(name)" } ?? name
    }
}
