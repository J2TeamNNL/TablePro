//
//  AISchemaContext.swift
//  TablePro
//
//  Builds AI system prompt context from current database connection schema.
//

import Foundation
import TableProAutocomplete
import TableProPluginKit
import TableProSQLGrammar

/// One table as the schema context describes it. The producer joins each table to its own columns
/// and foreign keys, because a lookup by name cannot tell two schemas' tables of the same name apart.
struct AISchemaTable: Sendable {
    let table: TableInfo
    let columns: [ColumnInfo]
    let foreignKeys: [ForeignKeyInfo]

    init(table: TableInfo, columns: [ColumnInfo] = [], foreignKeys: [ForeignKeyInfo] = []) {
        self.table = table
        self.columns = columns
        self.foreignKeys = foreignKeys
    }
}

struct AISchemaContext {
    static let maxQueryLength = 2_000

    // MARK: - Public

    static func buildSystemPrompt(
        databaseType: DatabaseType,
        databaseName: String,
        tables: [AISchemaTable],
        defaultSchema: String?,
        currentQuery: String?,
        queryResults: String?,
        settings: AISettings,
        identifierQuote: String = "\"",
        editorLanguage: EditorLanguage,
        queryLanguageName: String,
        connectionRules: String? = nil
    ) -> String {
        var parts: [String] = []

        parts.append(
            "You are a helpful database assistant for TablePro, a macOS database client."
        )
        parts.append(
            "The user is connected to a \(databaseType.rawValue) database"
            + " named \"\(databaseName)\"."
        )

        if settings.includeSchema {
            let schemaContext = buildSchemaSection(
                tables: tables,
                defaultSchema: defaultSchema,
                maxTables: settings.maxSchemaTables,
                identifierQuote: identifierQuote
            )
            if !schemaContext.isEmpty {
                parts.append("\n## Database Schema\n\(schemaContext)")
            }
        }

        if settings.includeCurrentQuery,
           let query = currentQuery,
           !query.isEmpty {
            let lang = editorLanguage.codeBlockTag
            let carried = carriedQuery(query)
            let truncated = carried.utf16.count < query.utf16.count ? carried + "\n-- ... truncated" : query
            parts.append("\n## Current Query\n```\(lang)\n\(truncated)\n```")
        }

        if settings.includeQueryResults,
           let results = queryResults,
           !results.isEmpty {
            parts.append("\n## Recent Query Results\n\(results)")
        }

        if let rules = connectionRules?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rules.isEmpty {
            parts.append("\n## Connection-Specific Rules\n\(rules)")
        }

        let langTag = editorLanguage.codeBlockTag

        switch editorLanguage {
        case .sql:
            parts.append(
                "\nProvide SQL queries appropriate for"
                + " \(databaseType.rawValue) syntax when applicable."
            )
            parts.append(
                "When writing SQL, use the correct identifier quoting"
                + " for \(databaseType.rawValue)."
            )
        default:
            parts.append(
                "\nProvide \(queryLanguageName) queries using `\(langTag)` fenced code blocks."
            )
            parts.append(
                "Use \(queryLanguageName) syntax, not SQL."
            )
        }

        return parts.joined(separator: "\n")
    }

    // MARK: - Private

    /// A table outside `defaultSchema` is named with its schema, so two tables that share a name
    /// read as two tables rather than one listed twice.
    static func buildSchemaSection(
        tables: [AISchemaTable],
        defaultSchema: String?,
        maxTables: Int,
        identifierQuote: String
    ) -> String {
        let selectedTables = tables.prefix(maxTables)
        guard !selectedTables.isEmpty else { return "" }

        var lines: [String] = []
        let q = identifierQuote

        for entry in selectedTables {
            let tableName = SchemaQualifiedName.render(
                name: entry.table.name,
                schema: entry.table.schema,
                implicitSchemaName: defaultSchema,
                quote: { "\(q)\($0)\(q)" }
            )
            var tableLine = "- \(tableName)"
            if let rowCount = entry.table.rowCount {
                tableLine += " (~\(rowCount) rows)"
            }
            lines.append(tableLine)

            for column in entry.columns {
                var colDesc = "  - \(column.name) \(column.dataType)"
                if column.isPrimaryKey { colDesc += " PK" }
                if !column.isNullable { colDesc += " NOT NULL" }
                if let def = column.defaultValue {
                    colDesc += " DEFAULT \(def)"
                }
                lines.append(colDesc)
            }

            for fk in entry.foreignKeys {
                lines.append(
                    "  FK: \(fk.column) -> "
                    + "\(fk.referencedTable).\(fk.referencedColumn)"
                )
            }
        }

        if tables.count > maxTables {
            lines.append(
                "\n… and \(tables.count - maxTables) more tables (not shown)"
            )
        }

        return lines.joined(separator: "\n")
    }

    // The editor's tables come first, since the model is reading that query; the question's matches
    // follow, best first.
    static func relevantTableNames(
        in tables: [TableInfo],
        columnsByTable: [String: [ColumnInfo]],
        question: String,
        queryReferences: [TableReference] = [],
        defaultSchema: String? = nil,
        maxTables: Int
    ) -> [String] {
        guard tables.count > maxTables else { return [] }
        var names = indices(of: queryReferences, in: tables, defaultSchema: defaultSchema).map { tables[$0].name }
        // Columns count only once every table has them, or a table loaded on an earlier turn would
        // outrank a better match whose columns were never read.
        let columns = tables.allSatisfy { columnsByTable[$0.name] != nil } ? columnsByTable : [:]
        let documents = tables.map { table in
            var details = (columns[table.name] ?? []).flatMap { [$0.name, $0.comment ?? ""] }
            if let comment = table.comment { details.append(comment) }
            return SchemaRelevanceDocument(name: table.name, details: details)
        }
        var seen = Set(names)
        for offset in SchemaRelevanceRanker.rank(documents, for: question) where seen.insert(tables[offset].name).inserted {
            names.append(tables[offset].name)
        }
        return names
    }

    static func carriedQuery(_ query: String) -> String {
        let nsQuery = query as NSString
        return nsQuery.length > maxQueryLength ? nsQuery.substring(to: maxQueryLength) : query
    }

    // A CTE or subquery has no table of its own, so it is left out.
    static func referencedTables(in query: String, grammar: SQLLexicalGrammar) -> [TableReference] {
        let analyzer = SQLContextAnalyzer()
        return SQLStatementScanner.allStatements(in: query, grammar: grammar).flatMap { statement in
            analyzer.tableReferences(in: statement, grammar: grammar).filter { $0.derivedColumns == nil }
        }
    }

    // In the order the query names them, each table once. A bare name means the default schema's
    // table, as it does when the query runs.
    static func indices(of references: [TableReference], in tables: [TableInfo], defaultSchema: String? = nil) -> [Int] {
        var result: [Int] = []
        for reference in references {
            let named = tables.indices.filter {
                tables[$0].name.caseInsensitiveCompare(reference.tableName) == .orderedSame
            }
            let schema = reference.schema ?? defaultSchema
            let inSchema = named.first { offset in
                guard let schema, let tableSchema = tables[offset].schema else { return false }
                return tableSchema.caseInsensitiveCompare(schema) == .orderedSame
            }
            let unscoped = named.first { tables[$0].schema == nil }
            let match = inSchema ?? unscoped ?? (reference.schema == nil ? named.first : nil)
            if let match, !result.contains(match) {
                result.append(match)
            }
        }
        return result
    }
}
