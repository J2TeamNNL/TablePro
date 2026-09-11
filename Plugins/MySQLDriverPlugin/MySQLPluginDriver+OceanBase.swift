import Foundation
import TableProPluginKit

extension MySQLPluginDriver {
    func rewriteOceanBaseQueryIfNeeded(_ query: String) async -> String {
        guard flavor.isOceanBase else { return query }
        if let table = OceanBaseSQL.simpleSelectStarTable(from: query) {
            let hidden = await oceanbaseHiddenPrimaryKeyColumns(for: table)
            return OceanBaseSQL.projectingHiddenPrimaryKeys(
                sql: query,
                hiddenColumns: hidden,
                quote: quoteIdentifier
            )
        }
        return OceanBaseSQL.withHiddenColumnVisibilityHint(query)
    }

    func attachingOceanBaseHiddenPrimaryKeys(
        to columns: [PluginColumnInfo],
        table: String
    ) async throws -> [PluginColumnInfo] {
        let indexes = try await fetchIndexes(table: table, schema: nil)
        let primaryColumns = indexes.first(where: \.isPrimary)?.columns ?? []
        var attached = OceanBaseHiddenPrimaryKey.attaching(
            to: columns,
            primaryIndexColumns: primaryColumns
        )
        let visibleNames = Set(columns.map(\.name))
        if attached.count == columns.count, !columns.contains(where: \.isPrimaryKey) {
            for name in OceanBaseSQL.documentedHiddenNames where !visibleNames.contains(name) {
                if await oceanbaseColumnExists(name, table: table) {
                    attached.append(OceanBaseHiddenPrimaryKey.synthesizedColumn(named: name))
                }
            }
        }
        let hiddenNames = attached.compactMap { column in
            visibleNames.contains(column.name) ? nil : column.name
        }
        rememberOceanBaseHiddenPrimaryKeys(hiddenNames, for: table)
        return attached
    }

    func attachingOceanBaseHiddenPrimaryKeys(
        to allColumns: [String: [PluginColumnInfo]],
        primaryColumnsByTable: [String: [String]]
    ) -> [String: [PluginColumnInfo]] {
        var merged = allColumns
        for (table, columns) in allColumns {
            let attached = OceanBaseHiddenPrimaryKey.attaching(
                to: columns,
                primaryIndexColumns: primaryColumnsByTable[table] ?? []
            )
            merged[table] = attached
            let hiddenNames = attached.compactMap { column in
                columns.contains(where: { $0.name == column.name }) ? nil : column.name
            }
            rememberOceanBaseHiddenPrimaryKeys(hiddenNames, for: table)
        }
        return merged
    }

    private func oceanbaseHiddenPrimaryKeyColumns(for table: String) async -> [String] {
        if let cached = cachedOceanBaseHiddenPrimaryKeys(for: table) {
            return cached
        }
        do {
            _ = try await fetchColumns(table: table, schema: nil)
        } catch {
            return []
        }
        return cachedOceanBaseHiddenPrimaryKeys(for: table) ?? []
    }

    private func oceanbaseColumnExists(_ column: String, table: String) async -> Bool {
        do {
            _ = try await execute(query: OceanBaseSQL.documentedHiddenColumnProbe(
                table: table,
                column: column,
                quote: quoteIdentifier
            ))
            return true
        } catch {
            return false
        }
    }
}
