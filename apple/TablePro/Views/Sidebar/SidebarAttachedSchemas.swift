//
//  SidebarAttachedSchemas.swift
//  TablePro
//

import Foundation

internal enum SidebarAttachedSchemas {
    /// During a search, an attached database not read yet stays out until its read lands.
    internal static func visible(
        attached: [String],
        database: String,
        searchText: String,
        loadedContent: (String) -> DatabaseTreeObjectBuckets?
    ) -> [String] {
        guard !searchText.isEmpty else { return attached }
        return attached.filter { schema in
            DatabaseTreeFilter.schemaSearchVerdict(
                schema: schema,
                database: database,
                searchText: searchText,
                loadedContent: loadedContent(schema),
                listingMatches: nil,
                listingCoversSchema: false
            ) == .match
        }
    }
}

internal extension DatabaseTreeTableRef {
    @MainActor
    func isInAttachedDatabase(of databaseType: DatabaseType) -> Bool {
        qualifyingSchema != nil && PluginManager.shared.listsAttachedDatabases(for: databaseType)
    }
}
