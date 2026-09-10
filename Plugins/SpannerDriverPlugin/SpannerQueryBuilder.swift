import Foundation
import TableProPluginKit

internal enum SpannerDialectKind: String, Codable, Sendable {
    case googleSQL
    case postgreSQL

    var identifierQuote: Character {
        self == .postgreSQL ? "\"" : "`"
    }

    var textCastType: String {
        self == .postgreSQL ? "TEXT" : "STRING"
    }

    var defaultSchema: String {
        self == .postgreSQL ? "public" : ""
    }

    var systemSchemas: Set<String> {
        switch self {
        case .googleSQL:
            return ["information_schema", "SPANNER_SYS", "spanner_sys"]
        case .postgreSQL:
            return ["information_schema", "pg_catalog", "spanner_sys"]
        }
    }

    static func parse(_ raw: String?) -> SpannerDialectKind {
        switch raw?.uppercased() {
        case "POSTGRESQL":
            return .postgreSQL
        default:
            return .googleSQL
        }
    }
}

internal struct SpannerQueryParams: Codable {
    let table: String
    let schema: String
    let sortColumns: [SortColumn]?
    let limit: Int
    let offset: Int
    let filters: [SpannerFilterSpec]?
    let logicMode: String?
    let searchText: String?
    let searchColumns: [String]?
    let dialect: SpannerDialectKind?

    struct SortColumn: Codable {
        let columnIndex: Int
        let ascending: Bool
    }
}

internal struct SpannerFilterSpec: Codable {
    let column: String
    let op: String
    let value: String
    var kind: String?
    var caseSensitive: Bool?

    var columnKind: PluginColumnKind? {
        guard let kind else { return nil }
        return PluginColumnKind(rawValue: kind)
    }

    var folding: PluginSQLCaseFolding {
        PluginSQLCaseFolding.resolve(
            style: .caseFoldFunction,
            isCaseSensitive: caseSensitive ?? true
        )
    }
}

internal struct SpannerQueryBuilder {
    static let browseTag = "SPANNER_BROWSE:"
    static let filterTag = "SPANNER_FILTER:"
    static let searchTag = "SPANNER_SEARCH:"
    static let combinedTag = "SPANNER_COMBINED:"

    static func encodeBrowseQuery(
        table: String,
        schema: String,
        dialect: SpannerDialectKind,
        sortColumns: [(columnIndex: Int, ascending: Bool)],
        limit: Int,
        offset: Int
    ) -> String {
        let params = SpannerQueryParams(
            table: table,
            schema: schema,
            sortColumns: sortColumns.map { .init(columnIndex: $0.columnIndex, ascending: $0.ascending) },
            limit: limit,
            offset: offset,
            filters: nil,
            logicMode: nil,
            searchText: nil,
            searchColumns: nil,
            dialect: dialect
        )
        return browseTag + encodeParams(params)
    }

    static func encodeFilteredQuery(
        table: String,
        schema: String,
        dialect: SpannerDialectKind,
        filters: [PluginQueryFilter],
        logicMode: String,
        sortColumns: [(columnIndex: Int, ascending: Bool)],
        limit: Int,
        offset: Int,
        columnKinds: [String: PluginColumnKind] = [:]
    ) -> String {
        let params = SpannerQueryParams(
            table: table,
            schema: schema,
            sortColumns: sortColumns.map { .init(columnIndex: $0.columnIndex, ascending: $0.ascending) },
            limit: limit,
            offset: offset,
            filters: filters.map {
                SpannerFilterSpec(
                    column: $0.column, op: $0.op, value: $0.value,
                    kind: columnKinds[$0.column]?.rawValue,
                    caseSensitive: $0.isCaseSensitive
                )
            },
            logicMode: logicMode,
            searchText: nil,
            searchColumns: nil,
            dialect: dialect
        )
        return filterTag + encodeParams(params)
    }

    static func decode(_ query: String) -> SpannerQueryParams? {
        let tags = [browseTag, filterTag, searchTag, combinedTag]
        guard let tag = tags.first(where: { query.hasPrefix($0) }) else { return nil }
        return decodeParams(String(query.dropFirst(tag.count)))
    }

    static func isTaggedQuery(_ query: String) -> Bool {
        query.hasPrefix(browseTag)
            || query.hasPrefix(filterTag)
            || query.hasPrefix(searchTag)
            || query.hasPrefix(combinedTag)
    }

    static func buildSQL(from params: SpannerQueryParams, columns: [String]) -> String {
        let dialect = params.dialect ?? .googleSQL
        let fqTable = qualifiedTable(schema: params.schema, table: params.table, dialect: dialect)
        var sql = "SELECT * FROM \(fqTable)"
        var whereClauses: [String] = []

        if let filters = params.filters, !filters.isEmpty {
            let logicMode = (params.logicMode ?? "AND").uppercased() == "OR" ? "OR" : "AND"
            let filterClauses = filters.compactMap { buildFilterClause($0, dialect: dialect) }
            if !filterClauses.isEmpty {
                whereClauses.append(filterClauses.joined(separator: " \(logicMode) "))
            }
        }

        if let searchText = params.searchText, !searchText.isEmpty {
            let searchCols = params.searchColumns.flatMap { $0.isEmpty ? nil : $0 } ?? columns
            let escapedSearch = searchText.replacingOccurrences(of: "'", with: "''")
            let searchClauses = searchCols.map { col in
                "CAST(\(quoteIdentifier(col, dialect: dialect)) AS \(dialect.textCastType)) LIKE '%\(escapedSearch)%'"
            }
            if !searchClauses.isEmpty {
                whereClauses.append("(\(searchClauses.joined(separator: " OR ")))")
            }
        }

        if !whereClauses.isEmpty {
            sql += " WHERE " + whereClauses.joined(separator: " AND ")
        }

        if let sortColumns = params.sortColumns, !sortColumns.isEmpty {
            let orderClauses = sortColumns.compactMap { sort -> String? in
                guard sort.columnIndex < columns.count else { return nil }
                return "\(quoteIdentifier(columns[sort.columnIndex], dialect: dialect)) \(sort.ascending ? "ASC" : "DESC")"
            }
            if !orderClauses.isEmpty {
                sql += " ORDER BY " + orderClauses.joined(separator: ", ")
            }
        }

        sql += " LIMIT \(params.limit) OFFSET \(params.offset)"
        return sql
    }

    static func buildCountSQL(from params: SpannerQueryParams, columns: [String]) -> String {
        let dialect = params.dialect ?? .googleSQL
        let fqTable = qualifiedTable(schema: params.schema, table: params.table, dialect: dialect)
        var sql = "SELECT COUNT(*) FROM \(fqTable)"
        var whereClauses: [String] = []

        if let filters = params.filters, !filters.isEmpty {
            let logicMode = (params.logicMode ?? "AND").uppercased() == "OR" ? "OR" : "AND"
            let filterClauses = filters.compactMap { buildFilterClause($0, dialect: dialect) }
            if !filterClauses.isEmpty {
                whereClauses.append(filterClauses.joined(separator: " \(logicMode) "))
            }
        }

        if let searchText = params.searchText, !searchText.isEmpty {
            let searchCols = params.searchColumns.flatMap { $0.isEmpty ? nil : $0 } ?? columns
            let escapedSearch = searchText.replacingOccurrences(of: "'", with: "''")
            let searchClauses = searchCols.map { col in
                "CAST(\(quoteIdentifier(col, dialect: dialect)) AS \(dialect.textCastType)) LIKE '%\(escapedSearch)%'"
            }
            if !searchClauses.isEmpty {
                whereClauses.append("(\(searchClauses.joined(separator: " OR ")))")
            }
        }

        if !whereClauses.isEmpty {
            sql += " WHERE " + whereClauses.joined(separator: " AND ")
        }
        return sql
    }

    static func qualifiedTable(schema: String, table: String, dialect: SpannerDialectKind) -> String {
        let quotedTable = quoteIdentifier(table, dialect: dialect)
        if schema.isEmpty {
            return quotedTable
        }
        return "\(quoteIdentifier(schema, dialect: dialect)).\(quotedTable)"
    }

    static func quoteIdentifier(_ name: String, dialect: SpannerDialectKind) -> String {
        let quote = dialect.identifierQuote
        if dialect == .postgreSQL {
            let escaped = name.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        let sanitized = name.replacingOccurrences(of: String(quote), with: "")
        return "`\(sanitized)`"
    }

    private static func formatFilterValue(_ value: String, kind: PluginColumnKind?) -> String {
        guard let kind else { return legacyFormatFilterValue(value) }
        return PluginSQLLiteral.escapedLiteral(
            value,
            kind: kind,
            trueLiteral: "TRUE",
            falseLiteral: "FALSE",
            quote: { "'\($0.replacingOccurrences(of: "'", with: "''"))'" }
        )
    }

    private static func legacyFormatFilterValue(_ value: String) -> String {
        let lower = value.lowercased()
        if lower == "true" { return "TRUE" }
        if lower == "false" { return "FALSE" }
        if lower == "null" { return "NULL" }
        if Int64(value) != nil || (Double(value) != nil && value.contains(".")) {
            return value
        }
        return "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }

    private static func buildFilterClause(
        _ filter: SpannerFilterSpec,
        dialect: SpannerDialectKind
    ) -> String? {
        let col = quoteIdentifier(filter.column, dialect: dialect)
        let escaped = filter.value.replacingOccurrences(of: "'", with: "''")
        let kind = filter.columnKind
        let isNullKeyword = filter.value.lowercased() == "null" && !PluginSQLLiteral.isKnownTextLike(kind)
        let folding = filter.folding
        let foldedColumn = folding.foldingLikeOperand(col)

        switch filter.op.uppercased() {
        case "=":
            if isNullKeyword { return "\(col) IS NULL" }
            return comparisonClause(col, "=", filter.value, kind: kind, folding: folding)
        case "!=", "<>":
            if isNullKeyword { return "\(col) IS NOT NULL" }
            return comparisonClause(col, "!=", filter.value, kind: kind, folding: folding)
        case ">":
            return "\(col) > \(formatFilterValue(filter.value, kind: kind))"
        case ">=":
            return "\(col) >= \(formatFilterValue(filter.value, kind: kind))"
        case "<":
            return "\(col) < \(formatFilterValue(filter.value, kind: kind))"
        case "<=":
            return "\(col) <= \(formatFilterValue(filter.value, kind: kind))"
        case "LIKE":
            return "\(foldedColumn) \(folding.likeKeyword) \(folding.foldingLikeOperand("'\(escaped)'"))"
        case "NOT LIKE":
            return "\(foldedColumn) \(folding.notLikeKeyword) \(folding.foldingLikeOperand("'\(escaped)'"))"
        case "IN", "NOT IN":
            let values = filter.value.split(separator: ",").map { val in
                foldedLiteral(
                    formatFilterValue(val.trimmingCharacters(in: .whitespaces), kind: kind),
                    folding: folding
                )
            }
            let column = values.contains(where: { $0.hasPrefix(folding.foldFunction) })
                ? folding.fold(col) : col
            return "\(column) \(filter.op.uppercased()) (\(values.joined(separator: ", ")))"
        case "IS NULL":
            return "\(col) IS NULL"
        case "IS NOT NULL":
            return "\(col) IS NOT NULL"
        case "CONTAINS":
            let castColumn = "CAST(\(col) AS \(dialect.textCastType))"
            return "\(folding.foldingLikeOperand(castColumn)) \(folding.likeKeyword) "
                + folding.foldingLikeOperand("'%\(escaped)%'")
        default:
            return nil
        }
    }

    private static func comparisonClause(
        _ column: String,
        _ operatorText: String,
        _ value: String,
        kind: PluginColumnKind?,
        folding: PluginSQLCaseFolding
    ) -> String {
        let literal = formatFilterValue(value, kind: kind)
        let foldedValue = foldedLiteral(literal, folding: folding)
        guard foldedValue != literal else { return "\(column) \(operatorText) \(literal)" }
        return "\(folding.fold(column)) \(operatorText) \(foldedValue)"
    }

    private static func foldedLiteral(_ literal: String, folding: PluginSQLCaseFolding) -> String {
        guard folding.foldsComparisonOperands, literal.hasPrefix("'") else { return literal }
        return folding.fold(literal)
    }

    private static func encodeParams(_ params: SpannerQueryParams) -> String {
        guard let data = try? JSONEncoder().encode(params) else { return "" }
        return data.base64EncodedString()
    }

    private static func decodeParams(_ base64: String) -> SpannerQueryParams? {
        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONDecoder().decode(SpannerQueryParams.self, from: data)
    }
}
