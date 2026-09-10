import Foundation
import os
import TableProPluginKit

internal struct SpannerStatementGenerator {
    private static let logger = Logger(subsystem: "com.TablePro", category: "SpannerStatementGenerator")

    let schema: String
    let tableName: String
    let columns: [String]
    let columnTypeNames: [String]
    let primaryKeyColumns: [String]
    let dialect: SpannerDialectKind

    private var fullyQualifiedTable: String {
        SpannerQueryBuilder.qualifiedTable(schema: schema, table: tableName, dialect: dialect)
    }

    func generateStatements(
        from changes: [PluginRowChange],
        insertedRowData: [Int: [PluginCellValue]],
        deletedRowIndices: Set<Int>,
        insertedRowIndices: Set<Int>
    ) -> [(statement: String, parameters: [PluginCellValue])] {
        var statements: [(statement: String, parameters: [PluginCellValue])] = []

        for change in changes {
            switch change.type {
            case .insert:
                guard insertedRowIndices.contains(change.rowIndex) else { continue }
                if let stmt = generateInsert(for: change, insertedRowData: insertedRowData) {
                    statements.append(stmt)
                }
            case .update:
                if let stmt = generateUpdate(for: change) {
                    statements.append(stmt)
                }
            case .delete:
                guard deletedRowIndices.contains(change.rowIndex) else { continue }
                if let stmt = generateDelete(for: change) {
                    statements.append(stmt)
                }
            }
        }

        return statements
    }

    private func generateInsert(
        for change: PluginRowChange,
        insertedRowData: [Int: [PluginCellValue]]
    ) -> (statement: String, parameters: [PluginCellValue])? {
        var values: [String: String?] = [:]

        if let rowData = insertedRowData[change.rowIndex] {
            for (index, column) in columns.enumerated() where index < rowData.count {
                values[column] = rowData[index].asText
            }
        } else {
            for cellChange in change.cellChanges {
                values[cellChange.columnName] = cellChange.newValue.asText
            }
        }

        var colNames: [String] = []
        var colValues: [String] = []

        for column in columns {
            guard let value = values[column] else { continue }
            let typeIndex = columns.firstIndex(of: column) ?? 0
            let typeName = typeIndex < columnTypeNames.count ? columnTypeNames[typeIndex] : "STRING"
            colNames.append(quote(column))
            colValues.append(formatValue(value, typeName: typeName))
        }

        guard !colNames.isEmpty else {
            Self.logger.warning("Skipping INSERT - no values provided")
            return nil
        }

        let statement = "INSERT INTO \(fullyQualifiedTable) (\(colNames.joined(separator: ", "))) "
            + "VALUES (\(colValues.joined(separator: ", ")))"
        return (statement: statement, parameters: [])
    }

    private func generateUpdate(
        for change: PluginRowChange
    ) -> (statement: String, parameters: [PluginCellValue])? {
        guard !change.cellChanges.isEmpty else { return nil }
        guard let whereClause = buildWhereClause(from: change) else {
            Self.logger.warning("Skipping UPDATE - cannot build WHERE clause")
            return nil
        }

        var setClauses: [String] = []
        for cellChange in change.cellChanges {
            let typeIndex = columns.firstIndex(of: cellChange.columnName) ?? 0
            let typeName = typeIndex < columnTypeNames.count ? columnTypeNames[typeIndex] : "STRING"
            let formattedValue = formatValue(cellChange.newValue.asText, typeName: typeName)
            setClauses.append("\(quote(cellChange.columnName)) = \(formattedValue)")
        }

        let statement = "UPDATE \(fullyQualifiedTable) SET \(setClauses.joined(separator: ", ")) WHERE \(whereClause)"
        return (statement: statement, parameters: [])
    }

    private func generateDelete(
        for change: PluginRowChange
    ) -> (statement: String, parameters: [PluginCellValue])? {
        guard let whereClause = buildWhereClause(from: change) else {
            Self.logger.warning("Skipping DELETE - cannot build WHERE clause")
            return nil
        }
        return (statement: "DELETE FROM \(fullyQualifiedTable) WHERE \(whereClause)", parameters: [])
    }

    private func buildWhereClause(from change: PluginRowChange) -> String? {
        guard let originalRow = change.originalRow else { return nil }
        let keyColumns = primaryKeyColumns.isEmpty ? columns : primaryKeyColumns
        var conditions: [String] = []

        for column in keyColumns {
            guard let index = columns.firstIndex(of: column), index < originalRow.count else { continue }
            let typeName = index < columnTypeNames.count ? columnTypeNames[index] : "STRING"
            if let value = originalRow[index].asText {
                let trimmed = value.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
                    continue
                }
                conditions.append("\(quote(column)) = \(formatValue(value, typeName: typeName))")
            } else {
                conditions.append("\(quote(column)) IS NULL")
            }
        }

        guard !conditions.isEmpty else { return nil }
        return conditions.joined(separator: " AND ")
    }

    private func formatValue(_ value: String?, typeName: String) -> String {
        guard let value else { return "NULL" }
        let upperType = typeName.uppercased()

        if ["INT64", "INTEGER", "INT8", "BIGINT", "FLOAT32", "FLOAT64", "FLOAT", "NUMERIC", "DECIMAL"].contains(upperType) {
            let isNumeric = value.range(
                of: #"^-?\d+(\.\d+)?([eE][+-]?\d+)?$"#,
                options: .regularExpression
            ) != nil
            if isNumeric { return value }
            return "'\(escapeString(value))'"
        }

        if upperType == "BOOL" || upperType == "BOOLEAN" {
            let lower = value.lowercased()
            if lower == "true" || lower == "1" { return "TRUE" }
            if lower == "false" || lower == "0" { return "FALSE" }
            return "'\(escapeString(value))'"
        }

        if value.lowercased() == "null" {
            return "NULL"
        }

        if upperType == "JSON" || upperType == "JSONB" {
            if dialect == .postgreSQL {
                return "'\(escapeString(value))'::jsonb"
            }
            return "JSON '\(escapeString(value))'"
        }

        if upperType.hasPrefix("ARRAY"), value.hasPrefix("[") {
            return value
        }

        if upperType == "BYTES" || upperType == "BYTEA" {
            if dialect == .postgreSQL {
                return "'\\x\(escapeString(value))'"
            }
            return "FROM_BASE64('\(escapeString(value))')"
        }

        if upperType == "TIMESTAMP" || upperType == "TIMESTAMPTZ" {
            return "TIMESTAMP '\(escapeString(value))'"
        }
        if upperType == "DATE" {
            return "DATE '\(escapeString(value))'"
        }

        return "'\(escapeString(value))'"
    }

    private func quote(_ name: String) -> String {
        SpannerQueryBuilder.quoteIdentifier(name, dialect: dialect)
    }

    private func escapeString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\0", with: "")
            .replacingOccurrences(of: "'", with: "''")
    }
}
