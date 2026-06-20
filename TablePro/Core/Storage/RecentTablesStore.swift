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

        var id: String { schema.map { "\($0).\(name)" } ?? name }
    }

    private var entriesByKey: [Key: [Entry]] = [:]
    private let cap = 10

    init() {}

    func push(connectionID: UUID, database: String?, table: TableInfo) {
        let key = Key(connectionID: connectionID, database: database)
        let entry = Entry(name: table.name, schema: table.schema, type: table.type)
        var list = entriesByKey[key] ?? []
        list.removeAll { $0.id == entry.id }
        list.insert(entry, at: 0)
        if list.count > cap {
            list = Array(list.prefix(cap))
        }
        entriesByKey[key] = list
        NotificationCenter.default.post(name: .recentTablesDidChange, object: nil)
    }

    func entries(connectionID: UUID, database: String?) -> [Entry] {
        entriesByKey[Key(connectionID: connectionID, database: database)] ?? []
    }
}
