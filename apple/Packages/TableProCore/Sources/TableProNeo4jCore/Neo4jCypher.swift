import Foundation

public enum Neo4jEntityKind: String, Sendable, CaseIterable {
    case node
    case relationship

    /// The sidebar groups labels and relationship types as two schemas with these names.
    public var schemaName: String {
        switch self {
        case .node: "Labels"
        case .relationship: "Relationship Types"
        }
    }

    public init?(schemaName: String?) {
        guard let match = Self.allCases.first(where: { $0.schemaName == schemaName }) else { return nil }
        self = match
    }
}

public struct Neo4jFilter: Sendable, Equatable {
    public let column: String
    public let op: String
    public let value: String
    public let secondValue: String?
    public let isCaseSensitive: Bool

    public init(column: String, op: String, value: String, secondValue: String? = nil, isCaseSensitive: Bool = true) {
        self.column = column
        self.op = op
        self.value = value
        self.secondValue = secondValue
        self.isCaseSensitive = isCaseSensitive
    }
}

public enum Neo4jCypherError: Error, Equatable, Sendable, LocalizedError {
    case unsupportedOperator(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedOperator(let op):
            return String(format: String(localized: "The %@ filter is not available for Neo4j."), op)
        }
    }
}

public enum Neo4jCypher {
    public static let idColumn = "<id>"
    public static let labelsColumn = "<labels>"
    public static let startColumn = "<start>"
    public static let endColumn = "<end>"
    public static let rawFilterColumn = "__RAW__"

    /// A browse query starts with this comment. It stays valid Cypher, so a browse query pasted
    /// into the editor still runs, and it tells the driver to spread the entity into columns.
    public static let browseMarker = "// TablePro browse: "

    public static func quote(_ identifier: String) -> String {
        "`" + identifier.replacingOccurrences(of: "`", with: "``") + "`"
    }

    public static func literal(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        return "'" + escaped + "'"
    }

    public static func browseKind(of query: String) -> Neo4jEntityKind? {
        let trimmed = query.drop { $0.isWhitespace }
        guard trimmed.hasPrefix(browseMarker) else { return nil }
        let rest = trimmed.dropFirst(browseMarker.count).prefix { !$0.isNewline }
        return Neo4jEntityKind(rawValue: rest.trimmingCharacters(in: .whitespaces))
    }

    public static func fixedColumns(for kind: Neo4jEntityKind) -> [String] {
        switch kind {
        case .node: [idColumn, labelsColumn]
        case .relationship: [idColumn, startColumn, endColumn]
        }
    }

    public static func pattern(for kind: Neo4jEntityKind, name: String) -> String {
        switch kind {
        case .node: "MATCH (n:\(quote(name)))"
        case .relationship: "MATCH ()-[n:\(quote(name))]->()"
        }
    }

    public static func browseQuery(
        kind: Neo4jEntityKind,
        name: String,
        filters: [Neo4jFilter] = [],
        matchesAll: Bool = true,
        sort: [(column: String, ascending: Bool)] = [],
        limit: Int,
        offset: Int,
        usesElementId: Bool = true
    ) throws -> String {
        var lines = [browseMarker + kind.rawValue, pattern(for: kind, name: name)]
        let clauses = try filters.map { try condition(for: $0, usesElementId: usesElementId) }
        if !clauses.isEmpty {
            let joined = clauses.count == 1
                ? clauses[0]
                : clauses.map { "(\($0))" }.joined(separator: matchesAll ? " AND " : " OR ")
            lines.append("WHERE " + joined)
        }
        lines.append("RETURN n")
        if !sort.isEmpty {
            let keys = sort.map { expression(for: $0.column, usesElementId: usesElementId) + ($0.ascending ? " ASC" : " DESC") }
            lines.append("ORDER BY " + keys.joined(separator: ", "))
        }
        lines.append("SKIP \(max(0, offset)) LIMIT \(max(0, limit))")
        return lines.joined(separator: "\n")
    }

    public static func countQuery(kind: Neo4jEntityKind, name: String) -> String {
        switch kind {
        case .node: "MATCH (n:\(quote(name))) RETURN count(n) AS count"
        case .relationship: "MATCH ()-[n:\(quote(name))]->() RETURN count(n) AS count"
        }
    }

    /// Property keys and one sample value each, from the first `sampleSize` entities. Bounded so
    /// the Structure tab stays fast on a large graph, unlike `db.schema.nodeTypeProperties()`.
    public static func propertySampleQuery(kind: Neo4jEntityKind, name: String, sampleSize: Int = 1_000) -> String {
        pattern(for: kind, name: name)
            + " WITH n LIMIT \(sampleSize) UNWIND keys(n) AS key"
            + " RETURN key, head(collect(n[key])) AS sample ORDER BY key"
    }

    public static func expression(for column: String, usesElementId: Bool) -> String {
        let idFunction = usesElementId ? "elementId" : "id"
        switch column {
        case idColumn: return "\(idFunction)(n)"
        case labelsColumn: return "labels(n)"
        case startColumn: return "\(idFunction)(startNode(n))"
        case endColumn: return "\(idFunction)(endNode(n))"
        default: return "n." + quote(column)
        }
    }

    static func condition(for filter: Neo4jFilter, usesElementId: Bool) throws -> String {
        if filter.column == rawFilterColumn { return filter.value }
        let target = expression(for: filter.column, usesElementId: usesElementId)
        let isIdentifier = [idColumn, startColumn, endColumn].contains(filter.column) && usesElementId
        let value = filter.value
        let text = filter.isCaseSensitive ? target : "toLower(\(target))"
        let needle = filter.isCaseSensitive ? literal(value) : literal(value.lowercased())

        switch filter.op.uppercased() {
        case "=":
            return isIdentifier ? "\(target) = \(literal(value))" : equality(target, value)
        case "!=", "<>":
            return isIdentifier ? "\(target) <> \(literal(value))" : "NOT (\(equality(target, value)))"
        case ">", ">=", "<", "<=":
            return "\(target) \(filter.op) \(typedLiteral(value))"
        case "BETWEEN":
            let upper = filter.secondValue ?? ""
            return "\(target) >= \(typedLiteral(value)) AND \(target) <= \(typedLiteral(upper))"
        case "CONTAINS":
            return "\(text) CONTAINS \(needle)"
        case "NOT CONTAINS":
            return "NOT (\(text) CONTAINS \(needle))"
        case "STARTS WITH":
            return "\(text) STARTS WITH \(needle)"
        case "ENDS WITH":
            return "\(text) ENDS WITH \(needle)"
        case "IS NULL":
            return "\(target) IS NULL"
        case "IS NOT NULL":
            return "\(target) IS NOT NULL"
        case "IS EMPTY":
            return "(\(target) IS NULL OR \(target) = '')"
        case "IS NOT EMPTY":
            return "(\(target) IS NOT NULL AND \(target) <> '')"
        case "IN", "NOT IN":
            let items = value.split(separator: ",").map { typedLiteral($0.trimmingCharacters(in: .whitespaces)) }
            let list = "\(target) IN [\(items.joined(separator: ", "))]"
            return filter.op.uppercased() == "IN" ? list : "NOT (\(list))"
        case "REGEX":
            return "\(target) =~ \(literal(filter.isCaseSensitive ? value : "(?i)" + value))"
        default:
            throw Neo4jCypherError.unsupportedOperator(filter.op)
        }
    }

    /// A property has no declared type, so a value that reads as a number or a boolean also
    /// matches the same text stored as a string.
    private static func equality(_ target: String, _ value: String) -> String {
        let typed = typedLiteral(value)
        guard typed != literal(value) else { return "\(target) = \(typed)" }
        return "(\(target) = \(typed) OR \(target) = \(literal(value)))"
    }

    static func typedLiteral(_ value: String) -> String {
        if Int64(value) != nil { return value }
        if let number = Double(value), number.isFinite, value.rangeOfCharacter(from: .letters) == nil { return value }
        switch value.lowercased() {
        case "true", "false": return value.lowercased()
        default: return literal(value)
        }
    }
}
