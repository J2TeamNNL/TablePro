import Foundation
import TableProPluginKit

enum HanaMetadata {
    static let displayName = "SAP HANA"
    static let iconName = "cylinder"
    static let brandColorHex = "#0FAAFF"
    static let defaultPort = 443
    static let schemaEntityName = "Schema"
    static let containerEntityName = "Schema"
    static let defaultSchemaName = ""
    static let tlsServerNameField = "hanaTLSServerName"

    static let connectionFields: [ConnectionField] = [
        ConnectionField(
            id: tlsServerNameField,
            label: String(localized: "TLS Server Name"),
            placeholder: String(localized: "Leave empty to use the host"),
            section: .advanced
        )
    ]

    static let columnTypesByCategory: [String: [String]] = [
        "Integer": ["TINYINT", "SMALLINT", "INTEGER", "BIGINT"],
        "Float": ["DECIMAL", "SMALLDECIMAL", "REAL", "DOUBLE"],
        "String": ["CHAR", "NCHAR", "VARCHAR", "NVARCHAR", "CLOB", "NCLOB"],
        "Date": ["DATE", "TIME", "SECONDDATE", "TIMESTAMP"],
        "Binary": ["BLOB", "VARBINARY"],
        "Boolean": ["BOOLEAN"],
        "Other": ["ALPHANUM", "SHORTTEXT", "TEXT", "ST_GEOMETRY"]
    ]

    static let statementCompletions = [
        CompletionEntry(label: "SELECT", insertText: "SELECT * FROM \"SCHEMA\".\"TABLE\""),
        CompletionEntry(label: "CREATE TABLE", insertText: "CREATE TABLE \"SCHEMA\".\"TABLE\" (\n    \"id\" INTEGER\n)"),
        CompletionEntry(label: "ALTER TABLE", insertText: "ALTER TABLE \"SCHEMA\".\"TABLE\""),
        CompletionEntry(label: "EXPLAIN PLAN", insertText: "EXPLAIN PLAN SET STATEMENT_NAME = 'plan' FOR SELECT 1"),
        CompletionEntry(label: "SELECT TOP", insertText: "SELECT TOP 100 * FROM \"SCHEMA\".\"TABLE\"")
    ]

    static let sqlDialect = SQLDialectDescriptor(
        identifierQuote: "\"",
        keywords: [
            "SELECT", "FROM", "WHERE", "JOIN", "INNER", "LEFT", "RIGHT", "FULL", "OUTER", "CROSS",
            "ON", "USING", "AND", "OR", "NOT", "IN", "LIKE", "BETWEEN", "IS", "NULL", "AS",
            "ORDER", "BY", "GROUP", "HAVING", "LIMIT", "TOP", "OFFSET", "UNION", "ALL", "DISTINCT",
            "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE", "MERGE", "CREATE", "ALTER", "DROP",
            "TABLE", "VIEW", "INDEX", "SCHEMA", "PRIMARY", "KEY", "FOREIGN", "REFERENCES", "UNIQUE",
            "CONSTRAINT", "ADD", "COLUMN", "RENAME", "CASE", "WHEN", "THEN", "ELSE", "END", "WITH",
            "EXPLAIN", "PLAN", "FOR", "BEGIN", "COMMIT", "ROLLBACK"
        ],
        functions: [
            "COUNT", "SUM", "AVG", "MIN", "MAX", "COALESCE", "NULLIF", "CAST", "CONVERT", "TO_DATE",
            "TO_TIMESTAMP", "CURRENT_DATE", "CURRENT_TIME", "CURRENT_TIMESTAMP", "CURRENT_SCHEMA", "LENGTH",
            "SUBSTRING", "LOWER", "UPPER", "TRIM", "REPLACE", "ROUND", "ABS"
        ],
        dataTypes: Set(columnTypesByCategory.values.flatMap { $0 }),
        tableOptions: ["PARTITION BY", "UNLOAD PRIORITY", "AUTO MERGE"],
        regexSyntax: .regexpLike,
        booleanLiteralStyle: .truefalse,
        likeEscapeStyle: .explicit,
        paginationStyle: .limit,
        autoLimitStyle: .limit
    )
}
