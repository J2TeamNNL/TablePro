import TableProPluginKit

enum SidebarTableOrdering {
    static func sortedByFavorite(_ tables: [TableInfo], favoriteTables: Set<String>) -> [TableInfo] {
        guard !favoriteTables.isEmpty else { return tables }
        let pinned = tables.filter { favoriteTables.contains($0.name) }
        let unpinned = tables.filter { !favoriteTables.contains($0.name) }
        return pinned + unpinned
    }
}
