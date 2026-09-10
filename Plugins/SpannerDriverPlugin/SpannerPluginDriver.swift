import Foundation
import os
import TableProPluginKit

internal final class SpannerPluginDriver: PluginDatabaseDriver, @unchecked Sendable {
    private let config: DriverConnectionConfig
    private var _connection: SpannerConnection?
    private let lock = NSLock()
    private var _serverVersion: String?
    private var _currentSchema: String?
    private var _columnCache: [String: [String]] = [:]
    private var _columnTypeCache: [String: [String]] = [:]
    private var _primaryKeyCache: [String: [String]] = [:]
    private var _queryTimeoutSeconds: Int = 300
    private static let logger = Logger(subsystem: "com.TablePro", category: "SpannerPluginDriver")

    var connection: SpannerConnection? {
        lock.withLock { _connection }
    }

    var serverVersion: String? {
        lock.withLock { _serverVersion }
    }

    var supportsSchemas: Bool { true }

    var currentSchema: String? {
        lock.withLock { _currentSchema }
    }

    var supportsTransactions: Bool { true }

    var capabilities: PluginCapabilities {
        [
            .alterTableDDL,
            .multiSchema,
            .cancelQuery,
            .transactions,
            .dataCompare
        ]
    }

    init(config: DriverConnectionConfig) {
        self.config = config
    }

    func beginTransaction() async throws {
        guard let conn = connection else { throw SpannerError.notConnected }
        try await conn.beginReadWriteTransaction()
    }

    func commitTransaction() async throws {
        guard let conn = connection else { throw SpannerError.notConnected }
        try await conn.commitTransaction()
    }

    func rollbackTransaction() async throws {
        guard let conn = connection else { throw SpannerError.notConnected }
        try await conn.rollbackTransaction()
    }

    func quoteIdentifier(_ name: String) -> String {
        let dialect = connection?.dialect ?? .googleSQL
        return SpannerQueryBuilder.quoteIdentifier(name, dialect: dialect)
    }

    func escapeStringLiteral(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\0", with: "")
            .replacingOccurrences(of: "'", with: "''")
    }

    func castColumnToText(_ column: String) -> String {
        let dialect = connection?.dialect ?? .googleSQL
        return "CAST(\(column) AS \(dialect.textCastType))"
    }

    func defaultExportQuery(table: String) -> String? {
        defaultExportQuery(table: table, schema: nil)
    }

    func defaultExportQuery(table: String, schema: String?) -> String? {
        let dialect = connection?.dialect ?? .googleSQL
        let schemaName = schema ?? lock.withLock { _currentSchema } ?? dialect.defaultSchema
        return "SELECT * FROM \(SpannerQueryBuilder.qualifiedTable(schema: schemaName, table: table, dialect: dialect))"
    }

    func dropObjectStatement(name: String, objectType: String, schema: String?, cascade: Bool) -> String? {
        let dialect = connection?.dialect ?? .googleSQL
        let schemaName = schema ?? lock.withLock { _currentSchema } ?? dialect.defaultSchema
        let qualified = SpannerQueryBuilder.qualifiedTable(schema: schemaName, table: name, dialect: dialect)
        return "DROP \(objectType.uppercased()) \(qualified)"
    }

    func connect() async throws {
        let conn = try SpannerConnection(config: config)
        try await conn.connect()
        let dialect = conn.dialect
        lock.withLock {
            _connection = conn
            _serverVersion = dialect == .postgreSQL
                ? "Google Cloud Spanner (PostgreSQL)"
                : "Google Cloud Spanner (GoogleSQL)"
            _currentSchema = dialect.defaultSchema
        }

        do {
            let schemas = try await fetchSchemas()
            let usable = schemas.filter { !dialect.systemSchemas.contains($0) }
            if let first = usable.first {
                lock.withLock { _currentSchema = first }
            }
        } catch {
            Self.logger.info("Could not auto-select schema: \(error.localizedDescription)")
        }
    }

    func disconnect() {
        lock.withLock {
            _connection?.disconnect()
            _connection = nil
            _columnCache.removeAll()
            _columnTypeCache.removeAll()
            _primaryKeyCache.removeAll()
            _currentSchema = nil
        }
    }

    func ping() async throws {
        guard let conn = connection else { throw SpannerError.notConnected }
        try await conn.ping()
    }

    func fetchSchemas() async throws -> [String] {
        guard let conn = connection else { throw SpannerError.notConnected }
        let dialect = conn.dialect
        let excluded = dialect.systemSchemas.map { "'\($0)'" }.joined(separator: ", ")
        let sql = """
        SELECT DISTINCT table_schema
        FROM information_schema.tables
        WHERE table_schema NOT IN (\(excluded))
        ORDER BY table_schema
        """
        let result = try await conn.executeReadOnly(sql)
        let names = result.rows.compactMap { row -> String? in
            guard let first = row.first else { return nil }
            return first.asText
        }
        if names.isEmpty {
            return [dialect.defaultSchema]
        }
        return names
    }

    func switchSchema(to schema: String) async throws {
        lock.withLock { _currentSchema = schema }
    }

    func execute(query: String) async throws -> PluginQueryResult {
        let startTime = Date()
        guard let conn = connection else { throw SpannerError.notConnected }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased() == "select 1" {
            try await conn.ping()
            return PluginQueryResult(
                columns: ["ok"],
                columnTypeNames: ["INT64"],
                rows: [[.text("1")]],
                rowsAffected: 0,
                executionTime: Date().timeIntervalSince(startTime)
            )
        }

        if SpannerQueryBuilder.isTaggedQuery(trimmed) {
            return try await executeTaggedQuery(trimmed, conn: conn, startTime: startTime)
        }

        let stripped = SpannerSQLClassification.stripExplainPrefix(trimmed)
        let result = try await conn.execute(
            stripped.sql,
            queryMode: stripped.isExplain ? "PLAN" : nil
        )
        return queryResult(from: result, started: startTime)
    }

    func cancelQuery() throws {
        connection?.cancelCurrentRequest()
    }

    func applyQueryTimeout(_ seconds: Int) async throws {
        lock.withLock { _queryTimeoutSeconds = max(seconds, 30) }
        connection?.setQueryTimeout(lock.withLock { _queryTimeoutSeconds })
    }

    func fetchTables(schema: String?) async throws -> [PluginTableInfo] {
        guard let conn = connection else { throw SpannerError.notConnected }
        let dialect = conn.dialect
        let schemaName = schema ?? lock.withLock { _currentSchema } ?? dialect.defaultSchema
        let escaped = escapeStringLiteral(schemaName)
        let sql = """
        SELECT table_name, table_type
        FROM information_schema.tables
        WHERE table_schema = '\(escaped)'
        ORDER BY table_name
        """
        let result = try await conn.executeReadOnly(sql)
        return result.rows.compactMap { row in
            guard let name = row.first?.asText else { return nil }
            let type = row.count > 1 ? (row[1].asText ?? "BASE TABLE") : "BASE TABLE"
            let mapped = type.uppercased().contains("VIEW") ? "VIEW" : "TABLE"
            return PluginTableInfo(name: name, type: mapped)
        }
    }

    func fetchColumns(table: String, schema: String?) async throws -> [PluginColumnInfo] {
        guard let conn = connection else { throw SpannerError.notConnected }
        let dialect = conn.dialect
        let schemaName = schema ?? lock.withLock { _currentSchema } ?? dialect.defaultSchema
        let typeColumn = dialect == .postgreSQL ? "spanner_type" : "spanner_type"
        let sql = """
        SELECT column_name, \(typeColumn), is_nullable, column_default, is_generated
        FROM information_schema.columns
        WHERE table_schema = '\(escapeStringLiteral(schemaName))'
          AND table_name = '\(escapeStringLiteral(table))'
        ORDER BY ordinal_position
        """
        let result = try await conn.executeReadOnly(sql)
        let primaryKeys = try await fetchPrimaryKeyColumns(table: table, schema: schemaName, conn: conn)

        let columns = result.rows.compactMap { row -> PluginColumnInfo? in
            guard let name = row.first?.asText else { return nil }
            let typeName = row.count > 1 ? (row[1].asText ?? "STRING") : "STRING"
            let nullableRaw = row.count > 2 ? (row[2].asText ?? "YES") : "YES"
            let isNullable = !["NO", "FALSE", "0"].contains(nullableRaw.uppercased())
            let defaultValue = row.count > 3 ? row[3].asText : nil
            let generatedRaw = row.count > 4 ? (row[4].asText ?? "") : ""
            let isGenerated = ["YES", "TRUE", "ALWAYS"].contains(generatedRaw.uppercased())
            return PluginColumnInfo(
                name: name,
                dataType: typeName,
                isNullable: isNullable,
                isPrimaryKey: primaryKeys.contains(name),
                defaultValue: defaultValue,
                isGenerated: isGenerated
            )
        }

        lock.withLock {
            let key = "\(schemaName).\(table)"
            _columnCache[key] = columns.map(\.name)
            _columnTypeCache[key] = columns.map(\.dataType)
            _primaryKeyCache[key] = primaryKeys
        }
        return columns
    }

    func fetchIndexes(table: String, schema: String?) async throws -> [PluginIndexInfo] {
        guard let conn = connection else { throw SpannerError.notConnected }
        let dialect = conn.dialect
        let schemaName = schema ?? lock.withLock { _currentSchema } ?? dialect.defaultSchema
        let uniqueColumn = dialect == .postgreSQL ? "is_unique" : "is_unique"
        let sql = """
        SELECT i.index_name, i.index_type, i.\(uniqueColumn), ic.column_name, ic.ordinal_position
        FROM information_schema.indexes AS i
        JOIN information_schema.index_columns AS ic
          ON i.table_schema = ic.table_schema
         AND i.table_name = ic.table_name
         AND i.index_name = ic.index_name
        WHERE i.table_schema = '\(escapeStringLiteral(schemaName))'
          AND i.table_name = '\(escapeStringLiteral(table))'
        ORDER BY i.index_name, ic.ordinal_position
        """
        let result = try await conn.executeReadOnly(sql)
        var grouped: [String: (type: String, unique: Bool, columns: [String])] = [:]
        for row in result.rows {
            guard let name = row.first?.asText, let column = row.count > 3 ? row[3].asText : nil else { continue }
            if row.count > 4, row[4].asText == nil { continue }
            let type = row.count > 1 ? (row[1].asText ?? "INDEX") : "INDEX"
            let uniqueRaw = row.count > 2 ? (row[2].asText ?? "") : ""
            let unique = ["YES", "TRUE", "1"].contains(uniqueRaw.uppercased())
            var entry = grouped[name] ?? (type, unique, [])
            entry.columns.append(column)
            grouped[name] = entry
        }
        return grouped.map { name, value in
            PluginIndexInfo(
                name: name,
                columns: value.columns,
                isUnique: value.unique || value.type.uppercased() == "PRIMARY_KEY",
                isPrimary: value.type.uppercased() == "PRIMARY_KEY",
                type: value.type
            )
        }.sorted { $0.name < $1.name }
    }

    func fetchForeignKeys(table: String, schema: String?) async throws -> [PluginForeignKeyInfo] {
        guard let conn = connection else { throw SpannerError.notConnected }
        let dialect = conn.dialect
        let schemaName = schema ?? lock.withLock { _currentSchema } ?? dialect.defaultSchema
        var keys: [PluginForeignKeyInfo] = []

        let parentSQL = """
        SELECT parent_table_name, on_delete_action, interleave_type
        FROM information_schema.tables
        WHERE table_schema = '\(escapeStringLiteral(schemaName))'
          AND table_name = '\(escapeStringLiteral(table))'
        """
        if let row = try await conn.executeReadOnly(parentSQL).rows.first,
           let parent = row.first?.asText, !parent.isEmpty
        {
            let onDelete = row.count > 1 ? (row[1].asText ?? "NO ACTION") : "NO ACTION"
            keys.append(PluginForeignKeyInfo(
                name: "INTERLEAVE",
                column: "",
                referencedTable: parent,
                referencedColumn: "",
                referencedSchema: schemaName,
                onDelete: onDelete
            ))
        }

        let fkSQL = """
        SELECT tc.constraint_name, kcu.column_name, ccu.table_name, ccu.column_name
        FROM information_schema.table_constraints AS tc
        JOIN information_schema.key_column_usage AS kcu
          ON tc.constraint_name = kcu.constraint_name
         AND tc.table_schema = kcu.table_schema
        JOIN information_schema.constraint_column_usage AS ccu
          ON ccu.constraint_name = tc.constraint_name
         AND ccu.table_schema = tc.table_schema
        WHERE tc.constraint_type = 'FOREIGN KEY'
          AND tc.table_schema = '\(escapeStringLiteral(schemaName))'
          AND tc.table_name = '\(escapeStringLiteral(table))'
        """
        if let result = try? await conn.executeReadOnly(fkSQL) {
            for row in result.rows {
                guard let name = row.first?.asText,
                      let column = row.count > 1 ? row[1].asText : nil,
                      let refTable = row.count > 2 ? row[2].asText : nil,
                      let refColumn = row.count > 3 ? row[3].asText : nil
                else { continue }
                keys.append(PluginForeignKeyInfo(
                    name: name,
                    column: column,
                    referencedTable: refTable,
                    referencedColumn: refColumn,
                    referencedSchema: schemaName
                ))
            }
        }
        return keys
    }

    func fetchApproximateRowCount(table: String, schema: String?) async throws -> Int? {
        nil
    }

    func fetchTableDDL(table: String, schema: String?) async throws -> String {
        guard let conn = connection else { throw SpannerError.notConnected }
        let statements = try await conn.fetchDDL()
        let needle = table.uppercased()
        if let match = statements.first(where: { $0.uppercased().contains("TABLE") && $0.uppercased().contains(needle) }) {
            return match
        }
        throw SpannerError.invalidResponse("No DDL found for table '\(table)'")
    }

    func fetchViewDefinition(view: String, schema: String?) async throws -> String {
        try await fetchTableDDL(table: view, schema: schema)
    }

    func fetchTableMetadata(table: String, schema: String?) async throws -> PluginTableMetadata {
        PluginTableMetadata(tableName: table, engine: connection?.dialect == .postgreSQL ? "PostgreSQL" : "GoogleSQL")
    }

    func fetchDatabases() async throws -> [String] {
        guard let conn = connection else { throw SpannerError.notConnected }
        return [conn.database]
    }

    func fetchDatabaseMetadata(_ database: String) async throws -> PluginDatabaseMetadata {
        PluginDatabaseMetadata(name: database)
    }

    func buildBrowseQuery(
        table: String,
        sortColumns: [(columnIndex: Int, ascending: Bool)],
        columns: [String],
        limit: Int,
        offset: Int
    ) -> String? {
        buildBrowseQuery(
            table: table, schema: nil, sortColumns: sortColumns,
            columns: columns, limit: limit, offset: offset
        )
    }

    func buildBrowseQuery(
        table: String,
        schema: String?,
        sortColumns: [(columnIndex: Int, ascending: Bool)],
        columns: [String],
        limit: Int,
        offset: Int
    ) -> String? {
        let dialect = connection?.dialect ?? .googleSQL
        let schemaName: String = lock.withLock {
            let name = schema ?? _currentSchema ?? dialect.defaultSchema
            _columnCache["\(name).\(table)"] = columns
            return name
        }
        return SpannerQueryBuilder.encodeBrowseQuery(
            table: table,
            schema: schemaName,
            dialect: dialect,
            sortColumns: sortColumns,
            limit: limit,
            offset: offset
        )
    }

    func buildFilteredQuery(
        table: String,
        schema: String?,
        queryFilters: [PluginQueryFilter],
        logicMode: String,
        sortColumns: [(columnIndex: Int, ascending: Bool)],
        columns: [String],
        limit: Int,
        offset: Int,
        columnKinds: [String: PluginColumnKind]
    ) -> String? {
        let dialect = connection?.dialect ?? .googleSQL
        let schemaName: String = lock.withLock {
            let name = schema ?? _currentSchema ?? dialect.defaultSchema
            _columnCache["\(name).\(table)"] = columns
            return name
        }
        return SpannerQueryBuilder.encodeFilteredQuery(
            table: table,
            schema: schemaName,
            dialect: dialect,
            filters: queryFilters,
            logicMode: logicMode,
            sortColumns: sortColumns,
            limit: limit,
            offset: offset,
            columnKinds: columnKinds
        )
    }

    func generateStatements(
        table: String,
        schema: String?,
        columns: [String],
        primaryKeyColumns: [String],
        changes: [PluginRowChange],
        insertedRowData: [Int: [PluginCellValue]],
        deletedRowIndices: Set<Int>,
        insertedRowIndices: Set<Int>
    ) -> [(statement: String, parameters: [PluginCellValue])]? {
        let dialect = connection?.dialect ?? .googleSQL
        let schemaName = schema ?? lock.withLock { _currentSchema } ?? dialect.defaultSchema
        let cacheKey = "\(schemaName).\(table)"
        let typeNames = lock.withLock { _columnTypeCache[cacheKey] } ?? columns.map { _ in "STRING" }
        let keys = primaryKeyColumns.isEmpty
            ? (lock.withLock { _primaryKeyCache[cacheKey] } ?? [])
            : primaryKeyColumns
        let generator = SpannerStatementGenerator(
            schema: schemaName,
            tableName: table,
            columns: columns,
            columnTypeNames: typeNames,
            primaryKeyColumns: keys,
            dialect: dialect
        )
        return generator.generateStatements(
            from: changes,
            insertedRowData: insertedRowData,
            deletedRowIndices: deletedRowIndices,
            insertedRowIndices: insertedRowIndices
        )
    }

    private func executeTaggedQuery(
        _ query: String,
        conn: SpannerConnection,
        startTime: Date
    ) async throws -> PluginQueryResult {
        guard let params = SpannerQueryBuilder.decode(query) else {
            throw SpannerError.invalidResponse("Invalid tagged query")
        }
        let cacheKey = "\(params.schema).\(params.table)"
        let columns = lock.withLock { _columnCache[cacheKey] } ?? []
        let sql = SpannerQueryBuilder.buildSQL(from: params, columns: columns)
        let result = try await conn.executeReadOnly(sql)
        return queryResult(from: result, started: startTime)
    }

    private func queryResult(from result: SpannerExecuteResult, started: Date) -> PluginQueryResult {
        if result.fields.isEmpty {
            return PluginQueryResult(
                columns: ["Result"],
                columnTypeNames: ["STRING"],
                rows: [[.text("Statement executed")]],
                rowsAffected: result.rowsAffected,
                executionTime: Date().timeIntervalSince(started)
            )
        }
        return PluginQueryResult(
            columns: result.fields.map(\.name),
            columnTypeNames: SpannerTypeMapper.columnTypeNames(from: result.fields),
            rows: SpannerTypeMapper.flattenRows(result.rows, fields: result.fields),
            rowsAffected: result.rowsAffected,
            executionTime: Date().timeIntervalSince(started)
        )
    }

    private func fetchPrimaryKeyColumns(
        table: String,
        schema: String,
        conn: SpannerConnection
    ) async throws -> [String] {
        let sql = """
        SELECT ic.column_name
        FROM information_schema.index_columns AS ic
        JOIN information_schema.indexes AS i
          ON i.table_schema = ic.table_schema
         AND i.table_name = ic.table_name
         AND i.index_name = ic.index_name
        WHERE i.table_schema = '\(escapeStringLiteral(schema))'
          AND i.table_name = '\(escapeStringLiteral(table))'
          AND i.index_type = 'PRIMARY_KEY'
        ORDER BY ic.ordinal_position
        """
        let result = try await conn.executeReadOnly(sql)
        return result.rows.compactMap { $0.first?.asText }
    }
}
