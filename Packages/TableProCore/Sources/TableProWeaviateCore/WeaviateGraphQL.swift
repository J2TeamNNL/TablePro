import Foundation

public enum WeaviateFilterBuilder {
    public static func graphQLWhere(
        filters: [WeaviateFilterSpec],
        logicMode: String
    ) -> String? {
        let operands = filters.compactMap(operand(for:))
        guard !operands.isEmpty else { return nil }
        if operands.count == 1 {
            return operands[0]
        }
        let joined = operands.joined(separator: " ")
        let op = logicMode.uppercased() == "OR" ? "Or" : "And"
        return "{ operator: \(op) operands: [\(joined)] }"
    }

    public static func operand(for filter: WeaviateFilterSpec) -> String? {
        if WeaviateSchema.immutableColumns.contains(filter.column), filter.column != WeaviateSchema.uuidColumn {
            return nil
        }
        let path = filter.column == WeaviateSchema.uuidColumn ? "id" : filter.column
        let operatorName: String
        var value = filter.value
        switch filter.op.uppercased() {
        case "=", "EQUAL", "EQ":
            operatorName = "Equal"
        case "!=", "<>", "NOT EQUAL":
            operatorName = "NotEqual"
        case ">":
            operatorName = "GreaterThan"
        case ">=":
            operatorName = "GreaterThanEqual"
        case "<":
            operatorName = "LessThan"
        case "<=":
            operatorName = "LessThanEqual"
        case "CONTAINS", "LIKE":
            operatorName = "Like"
            if !value.contains("*") {
                value = "*\(value)*"
            }
        case "STARTS WITH":
            operatorName = "Like"
            if !value.hasSuffix("*") {
                value += "*"
            }
        case "IS NULL":
            return "{ path: [\"\(escape(path))\"] operator: IsNull valueBoolean: true }"
        case "IS NOT NULL":
            return "{ path: [\"\(escape(path))\"] operator: IsNull valueBoolean: false }"
        default:
            return nil
        }
        return "{ path: [\"\(escape(path))\"] operator: \(operatorName) \(valueField(filter.typeName)): \(literal(value, typeName: filter.typeName)) }"
    }

    private static func valueField(_ typeName: String) -> String {
        switch typeName.lowercased() {
        case "int":
            return "valueInt"
        case "number":
            return "valueNumber"
        case "boolean", "bool":
            return "valueBoolean"
        default:
            return "valueText"
        }
    }

    private static func literal(_ value: String, typeName: String) -> String {
        switch typeName.lowercased() {
        case "int":
            return Int(value).map(String.init) ?? "0"
        case "number":
            return Double(value).map { String($0) } ?? "0"
        case "boolean", "bool":
            return value.lowercased() == "true" ? "true" : "false"
        default:
            return "\"\(escape(value))\""
        }
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

public enum WeaviateGraphQL {
    public static func getQuery(
        collection: String,
        properties: [String],
        limit: Int,
        offset: Int,
        sorts: [WeaviateSortSpec],
        filters: [WeaviateFilterSpec],
        logicMode: String
    ) -> String {
        let fields = properties
            .filter { $0 != WeaviateSchema.uuidColumn && $0 != WeaviateSchema.vectorColumn }
            .joined(separator: " ")
        var args: [String] = ["limit: \(max(limit, 0))", "offset: \(max(offset, 0))"]
        if let whereClause = WeaviateFilterBuilder.graphQLWhere(filters: filters, logicMode: logicMode) {
            args.append("where: \(whereClause)")
        }
        let sortArgs = sorts.compactMap { sort -> String? in
            let path = sort.column == WeaviateSchema.uuidColumn ? "id" : sort.column
            if path == WeaviateSchema.vectorColumn { return nil }
            return "{ path: [\"\(path)\"] order: \(sort.ascending ? "asc" : "desc") }"
        }
        if !sortArgs.isEmpty {
            args.append("sort: [\(sortArgs.joined(separator: " "))]")
        }
        let argumentList = args.joined(separator: ", ")
        return """
        { Get { \(collection)(\(argumentList)) { \(fields) _additional { id vector } } } }
        """
    }

    public static func looksLikeGraphQL(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") { return true }
        let lowered = trimmed.lowercased()
        return lowered.hasPrefix("query") || lowered.hasPrefix("mutation") || lowered.hasPrefix("subscription")
            || lowered.hasPrefix("fragment")
    }

    public static func isMutation(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("mutation")
    }

    public static func requestBody(query: String) throws -> Data {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           object["query"] != nil {
            return try WeaviateJSON.data(object)
        }
        return try WeaviateJSON.data(["query": trimmed])
    }
}

public struct WeaviateConsoleRequest: Sendable, Equatable {
    public let method: String
    public let path: String
    public let body: String?

    public init(method: String, path: String, body: String?) {
        self.method = method
        self.path = path
        self.body = body
    }
}

public enum WeaviateConsoleParser {
    public static func parse(_ input: String) -> WeaviateConsoleRequest? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let newline = trimmed.firstIndex(where: \.isNewline) else {
            return parseHeader(trimmed, body: nil)
        }
        let header = String(trimmed[..<newline])
        let rest = trimmed[trimmed.index(after: newline)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return parseHeader(header, body: rest.isEmpty ? nil : rest)
    }

    private static func parseHeader(_ header: String, body: String?) -> WeaviateConsoleRequest? {
        let parts = header.split(whereSeparator: { $0.isWhitespace })
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0]).uppercased()
        guard ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD"].contains(method) else {
            return nil
        }
        let rawPath = String(parts[1])
        guard rawPath.hasPrefix("/") else { return nil }
        var path = rawPath
        if !path.hasPrefix("/v1") && path != "/" {
            if path.hasPrefix("/objects") || path.hasPrefix("/schema") || path.hasPrefix("/graphql")
                || path.hasPrefix("/meta") {
                path = "/v1" + path
            }
        }
        return WeaviateConsoleRequest(method: method, path: path, body: body)
    }
}
