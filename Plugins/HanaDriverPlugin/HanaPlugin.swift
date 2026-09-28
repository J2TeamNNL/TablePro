import Foundation
import TableProPluginKit

final class HanaPlugin: NSObject, TableProPlugin, DriverPlugin {
    static let pluginName = "SAP HANA Driver"
    static let pluginVersion = "1.0.0"
    static let pluginDescription = "SAP HANA SQL support via SAP/go-hdb"
    static let capabilities: [PluginCapability] = [.databaseDriver]

    static let databaseTypeId = "SAP HANA"
    static let databaseDisplayName = "SAP HANA"
    static let iconName = "cylinder"
    static let defaultPort = 443
    static let additionalConnectionFields = HanaMetadata.connectionFields
    static let brandColorHex = HanaMetadata.brandColorHex
    static let isDownloadable = true
    static let supportsSSL = true
    static let supportsSSH = false
    static let supportsForeignKeys = false
    static let supportsSchemaEditing = false
    static let supportsAddColumn = false
    static let supportsModifyColumn = false
    static let supportsDropColumn = false
    static let supportsRenameColumn = false
    static let supportsAddIndex = false
    static let supportsDropIndex = false
    static let supportsModifyPrimaryKey = false
    static let supportsDatabaseSwitching = false
    static let supportsSchemaSwitching = true
    static let supportsImport = false
    static let supportsExport = true
    static let supportsHealthMonitor = true
    static let supportsReadOnlyMode = false
    static let supportsQueryProgress = false
    static let supportsCascadeDrop = false
    static let supportsForeignKeyDisable = false
    static let defaultSchemaName = HanaMetadata.defaultSchemaName
    static let schemaEntityName = HanaMetadata.schemaEntityName
    static let containerEntityName = HanaMetadata.containerEntityName
    static let databaseGroupingStrategy: GroupingStrategy = .hierarchicalSchema
    static let postConnectActions: [PostConnectAction] = [.selectSchemaFromLastSession]
    static let columnTypesByCategory = HanaMetadata.columnTypesByCategory
    static let statementCompletions = HanaMetadata.statementCompletions
    static let sqlDialect: SQLDialectDescriptor? = HanaMetadata.sqlDialect
    static let pathFieldRole: PathFieldRole = .database
    static let urlSchemes = ["hdb"]
    static let systemSchemaNames = ["SYS", "_SYS_BI", "_SYS_BIC", "_SYS_REPO", "_SYS_STATISTICS"]
    static let structureColumnFields: [StructureColumnField] = [.name, .type, .nullable, .defaultValue, .comment]
    static let explainVariants = [ExplainVariant(id: "plan", label: "Plan", sqlPrefix: "EXPLAIN PLAN FOR")]

    func createDriver(config: DriverConnectionConfig) -> any PluginDatabaseDriver {
        HanaPluginDriver(config: config)
    }
}

final class HanaPluginDriver: PluginDatabaseDriver, @unchecked Sendable {
    private let config: DriverConnectionConfig
    private let connection = HanaConnection()
    private let stateLock = NSLock()
    private var schema: String?
    private var connected = false

    init(config: DriverConnectionConfig) {
        self.config = config
        self.schema = config.database.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var capabilities: PluginCapabilities { [.cancelQuery] }
    var supportsSchemas: Bool { true }
    var supportsTransactions: Bool { false }
    var currentSchema: String? { stateLock.withLock { schema } }
    var serverVersion: String? { nil }

    func connect() async throws {
        guard (1...65_535).contains(config.port) else { throw HanaError.invalidPort }
        let options = HanaConnectOptions(
            host: config.host,
            port: config.port,
            username: config.username,
            password: config.password,
            schema: currentSchema ?? "",
            tlsMode: tlsMode,
            tlsServerName: config.additionalFields[HanaMetadata.tlsServerNameField] ?? "",
            caPath: config.ssl.caCertificatePath
        )
        try await connection.connect(options: options)
        stateLock.withLock { connected = true }
        if currentSchema == nil, let detected = try? await scalarText("SELECT CURRENT_SCHEMA FROM DUMMY") {
            stateLock.withLock { schema = detected }
        }
    }

    func disconnect() {
        stateLock.withLock { connected = false; schema = nil }
        connection.disconnect()
    }

    func ping() async throws {
        try await connection.ping()
    }

    func cancelQuery() throws {
        connection.cancel()
    }

    func applyQueryTimeout(_ seconds: Int) async throws {}

    func execute(query: String) async throws -> PluginQueryResult {
        try await executeUserQuery(query: query, rowCap: nil, parameters: nil)
    }

    func executeUserQuery(
        query: String,
        rowCap: Int?,
        parameters: [PluginCellValue]?
    ) async throws -> PluginQueryResult {
        guard parameters?.isEmpty ?? true else {
            throw HanaError.unsupported(String(localized: "Parameterized SAP HANA queries are not available in this driver."))
        }
        guard stateLock.withLock({ connected }) else {
            throw HanaError.bridge(String(localized: "The SAP HANA connection is closed."))
        }
        return try await connection.execute(query, rowCap: rowCap).pluginResult
    }

    func executeParameterized(query: String, parameters: [PluginCellValue]) async throws -> PluginQueryResult {
        guard parameters.isEmpty else {
            throw HanaError.unsupported(String(localized: "Parameterized SAP HANA queries are not available in this driver."))
        }
        return try await execute(query: query)
    }

    func fetchSchemas() async throws -> [String] {
        let result = try await execute(query: "SELECT SCHEMA_NAME FROM SYS.SCHEMAS ORDER BY SCHEMA_NAME")
        return result.rows.compactMap { $0.first?.asText }
    }

    func switchSchema(to schema: String) async throws {
        let normalized = schema.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw HanaError.unsupported(String(localized: "The SAP HANA schema name cannot be empty."))
        }
        _ = try await execute(query: "SET SCHEMA \(quoteIdentifier(normalized))")
        stateLock.withLock { self.schema = normalized }
    }

    func fetchTables(schema: String?) async throws -> [PluginTableInfo] {
        let owner = try effectiveSchema(schema)
        let literal = quoteLiteral(owner)
        let result = try await execute(query: """
            SELECT TABLE_NAME, 'TABLE' AS OBJECT_TYPE
            FROM SYS.TABLES
            WHERE SCHEMA_NAME = \(literal)
            UNION ALL
            SELECT VIEW_NAME, 'VIEW'
            FROM SYS.VIEWS
            WHERE SCHEMA_NAME = \(literal)
            ORDER BY 1
            """)
        return result.rows.compactMap { row in
            guard let name = row[safe: 0]?.asText else { return nil }
            return PluginTableInfo(name: name, type: row[safe: 1]?.asText ?? "TABLE", schema: owner, comment: nil)
        }
    }

    func fetchColumns(table: String, schema: String?) async throws -> [PluginColumnInfo] {
        let owner = try effectiveSchema(schema)
        let result = try await execute(query: """
            SELECT COLUMN_NAME, DATA_TYPE_NAME, IS_NULLABLE, DEFAULT_VALUE, COMMENTS
            FROM SYS.TABLE_COLUMNS
            WHERE SCHEMA_NAME = \(quoteLiteral(owner))
              AND TABLE_NAME = \(quoteLiteral(table))
            ORDER BY POSITION
            """)
        return result.rows.compactMap { row in
            guard let name = row[safe: 0]?.asText else { return nil }
            return PluginColumnInfo(
                name: name,
                dataType: row[safe: 1]?.asText ?? "",
                isNullable: row[safe: 2]?.asText?.caseInsensitiveCompare("TRUE") == .orderedSame,
                defaultValue: row[safe: 3]?.asText?.nilIfEmpty,
                comment: row[safe: 4]?.asText?.nilIfEmpty
            )
        }
    }

    func fetchIndexes(table: String, schema: String?) async throws -> [PluginIndexInfo] {
        let owner = try effectiveSchema(schema)
        let result = try await execute(query: """
            SELECT INDEX_NAME, COLUMN_NAME, CONSTRAINT
            FROM SYS.INDEX_COLUMNS
            WHERE SCHEMA_NAME = \(quoteLiteral(owner))
              AND TABLE_NAME = \(quoteLiteral(table))
            ORDER BY INDEX_NAME, POSITION
            """)
        var grouped: [String: (columns: [String], unique: Bool, primary: Bool)] = [:]
        for row in result.rows {
            guard let name = row[safe: 0]?.asText, let column = row[safe: 1]?.asText else { continue }
            let constraint = row[safe: 2]?.asText?.uppercased().replacingOccurrences(of: " ", with: "_") ?? ""
            var index = grouped[name] ?? ([], false, false)
            index.columns.append(column)
            index.unique = index.unique || constraint.contains("UNIQUE") || constraint == "PRIMARY_KEY"
            index.primary = index.primary || constraint == "PRIMARY_KEY"
            grouped[name] = index
        }
        return grouped.keys.sorted().compactMap { name -> PluginIndexInfo? in
            guard let index = grouped[name] else { return nil }
            return PluginIndexInfo(name: name, columns: index.columns, isUnique: index.unique, isPrimary: index.primary)
        }
    }

    func fetchForeignKeys(table: String, schema: String?) async throws -> [PluginForeignKeyInfo] { [] }

    func fetchTableMetadata(table: String, schema: String?) async throws -> PluginTableMetadata {
        PluginTableMetadata(tableName: table)
    }

    func fetchTableDDL(table: String, schema: String?) async throws -> String {
        let owner = try effectiveSchema(schema)
        let columns = try await fetchColumns(table: table, schema: owner)
        let body = columns.map { column in
            "    \(quoteIdentifier(column.name)) \(column.dataType)\(column.isNullable ? "" : " NOT NULL")"
        }.joined(separator: ",\n")
        return "CREATE TABLE \(quoteIdentifier(owner)).\(quoteIdentifier(table)) (\n\(body)\n)"
    }

    func fetchViewDefinition(view: String, schema: String?) async throws -> String {
        let owner = try effectiveSchema(schema)
        let result = try await execute(query: "SELECT DEFINITION FROM SYS.VIEWS WHERE SCHEMA_NAME = \(quoteLiteral(owner)) AND VIEW_NAME = \(quoteLiteral(view))")
        guard let definition = result.rows.first?.first?.asText else {
            throw HanaError.bridge(String(localized: "SAP HANA returned no definition for this view."))
        }
        return definition
    }

    private var tlsMode: Int {
        switch config.ssl.mode {
        case .disabled: return 0
        case .preferred, .required: return 1
        case .verifyCa: return 3
        case .verifyIdentity: return 4
        }
    }

    private func effectiveSchema(_ requested: String?) throws -> String {
        let value = requested?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? currentSchema
        guard let value else {
            throw HanaError.unsupported(String(localized: "Choose a SAP HANA schema first."))
        }
        return value
    }

    private func scalarText(_ query: String) async throws -> String {
        let result = try await execute(query: query)
        guard let text = result.rows.first?.first?.asText else {
            throw HanaError.bridge(String(localized: "SAP HANA returned an empty metadata result."))
        }
        return text
    }

    static func quoteIdentifier(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    static func quoteLiteral(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }

    private func quoteIdentifier(_ value: String) -> String { Self.quoteIdentifier(value) }
    private func quoteLiteral(_ value: String) -> String { Self.quoteLiteral(value) }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
