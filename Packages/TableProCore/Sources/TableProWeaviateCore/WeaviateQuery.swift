import Foundation

public struct WeaviateFilterSpec: Codable, Sendable, Equatable {
    public let column: String
    public let op: String
    public let value: String
    public let typeName: String

    public init(column: String, op: String, value: String, typeName: String = "text") {
        self.column = column
        self.op = op
        self.value = value
        self.typeName = typeName
    }
}

public struct WeaviateSortSpec: Codable, Sendable, Equatable {
    public let column: String
    public let ascending: Bool

    public init(column: String, ascending: Bool) {
        self.column = column
        self.ascending = ascending
    }
}

public struct WeaviateParsedSearch: Sendable, Equatable {
    public let collection: String
    public let offset: Int
    public let limit: Int
    public let sorts: [WeaviateSortSpec]
    public let filters: [WeaviateFilterSpec]
    public let logicMode: String
    public let propertyNames: [String]

    public init(
        collection: String,
        offset: Int,
        limit: Int,
        sorts: [WeaviateSortSpec],
        filters: [WeaviateFilterSpec],
        logicMode: String,
        propertyNames: [String]
    ) {
        self.collection = collection
        self.offset = offset
        self.limit = limit
        self.sorts = sorts
        self.filters = filters
        self.logicMode = logicMode
        self.propertyNames = propertyNames
    }

    public var usesGraphQL: Bool {
        !filters.isEmpty || !sorts.filter({ $0.column != WeaviateSchema.uuidColumn }).isEmpty
    }
}

public enum WeaviateBrowseQuery {
    public static let searchTag = "WEAVIATE_SEARCH:"

    public static func encode(
        collection: String,
        offset: Int,
        limit: Int,
        sorts: [WeaviateSortSpec],
        filters: [WeaviateFilterSpec],
        logicMode: String,
        propertyNames: [String]
    ) -> String {
        let payload: [String: Any] = [
            "collection": collection,
            "offset": offset,
            "limit": limit,
            "logicMode": logicMode,
            "sorts": sorts.map { ["column": $0.column, "ascending": $0.ascending] },
            "filters": filters.map {
                ["column": $0.column, "op": $0.op, "value": $0.value, "typeName": $0.typeName]
            },
            "properties": propertyNames
        ]
        let body = (try? WeaviateJSON.data(payload)) ?? Data()
        return searchTag + body.base64EncodedString()
    }

    public static func parse(_ query: String) -> WeaviateParsedSearch? {
        guard query.hasPrefix(searchTag) else { return nil }
        let encoded = String(query.dropFirst(searchTag.count))
        guard let data = Data(base64Encoded: encoded),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let collection = json["collection"] as? String
        else { return nil }
        let sortsJSON = json["sorts"] as? [[String: Any]] ?? []
        let filtersJSON = json["filters"] as? [[String: Any]] ?? []
        let properties = json["properties"] as? [String] ?? []
        return WeaviateParsedSearch(
            collection: collection,
            offset: json["offset"] as? Int ?? 0,
            limit: json["limit"] as? Int ?? 25,
            sorts: sortsJSON.compactMap { item in
                guard let column = item["column"] as? String else { return nil }
                return WeaviateSortSpec(column: column, ascending: item["ascending"] as? Bool ?? true)
            },
            filters: filtersJSON.compactMap { item in
                guard let column = item["column"] as? String, let op = item["op"] as? String else {
                    return nil
                }
                return WeaviateFilterSpec(
                    column: column,
                    op: op,
                    value: item["value"] as? String ?? "",
                    typeName: item["typeName"] as? String ?? "text"
                )
            },
            logicMode: json["logicMode"] as? String ?? "AND",
            propertyNames: properties
        )
    }

    public static func isTagged(_ query: String) -> Bool {
        query.hasPrefix(searchTag)
    }
}

public struct WeaviateWriteRequest: Sendable, Equatable {
    public let method: String
    public let path: String
    public let query: [String: String]
    public let body: String?

    public init(method: String, path: String, query: [String: String] = [:], body: String?) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
    }
}

public enum WeaviateWriteCodec {
    public static let writeTag = "WEAVIATE_WRITE:"

    public static func encode(_ request: WeaviateWriteRequest) -> String {
        let payload: [String: Any] = [
            "method": request.method,
            "path": request.path,
            "query": request.query,
            "body": request.body ?? ""
        ]
        let data = (try? WeaviateJSON.data(payload)) ?? Data()
        return writeTag + data.base64EncodedString()
    }

    public static func decode(_ statement: String) -> WeaviateWriteRequest? {
        guard statement.hasPrefix(writeTag) else { return nil }
        let encoded = String(statement.dropFirst(writeTag.count))
        guard let data = Data(base64Encoded: encoded),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = json["method"] as? String,
              let path = json["path"] as? String
        else { return nil }
        let query = json["query"] as? [String: String] ?? [:]
        let body = json["body"] as? String
        return WeaviateWriteRequest(
            method: method,
            path: path,
            query: query,
            body: (body?.isEmpty ?? true) ? nil : body
        )
    }

    public static func isTagged(_ statement: String) -> Bool {
        statement.hasPrefix(writeTag)
    }
}

public struct WeaviateCellChange: Sendable, Equatable {
    public let column: String
    public let newText: String?

    public init(column: String, newText: String?) {
        self.column = column
        self.newText = newText
    }
}

public struct WeaviateTrackedChange: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case insert
        case update
        case delete
    }

    public let kind: Kind
    public let uuid: String?
    public let values: [String: String?]
    public let cellChanges: [WeaviateCellChange]

    public init(
        kind: Kind,
        uuid: String?,
        values: [String: String?],
        cellChanges: [WeaviateCellChange]
    ) {
        self.kind = kind
        self.uuid = uuid
        self.values = values
        self.cellChanges = cellChanges
    }
}

public enum WeaviateStatementGenerator {
    public static func generate(
        collection: String,
        columns: [String],
        typeNames: [String],
        changes: [WeaviateTrackedChange]
    ) -> [WeaviateWriteRequest] {
        let types = Dictionary(uniqueKeysWithValues: zip(columns, typeNames))
        return changes.compactMap { change in
            switch change.kind {
            case .insert:
                return insert(collection: collection, types: types, change: change)
            case .update:
                return update(collection: collection, types: types, change: change)
            case .delete:
                return delete(collection: collection, change: change)
            }
        }
    }

    private static func insert(
        collection: String,
        types: [String: String],
        change: WeaviateTrackedChange
    ) -> WeaviateWriteRequest? {
        var payload: [String: Any] = [
            "class": collection,
            "properties": properties(from: change.values, types: types)
        ]
        if let uuid = change.uuid, !uuid.isEmpty {
            payload["id"] = uuid
        }
        guard let body = try? WeaviateJSON.text(payload) else { return nil }
        return WeaviateWriteRequest(method: "POST", path: "/v1/objects", body: body)
    }

    private static func update(
        collection: String,
        types: [String: String],
        change: WeaviateTrackedChange
    ) -> WeaviateWriteRequest? {
        guard let uuid = change.uuid, !uuid.isEmpty else { return nil }
        var patch: [String: String?] = [:]
        for cell in change.cellChanges where !WeaviateSchema.immutableColumns.contains(cell.column) {
            patch[cell.column] = cell.newText
        }
        guard !patch.isEmpty else { return nil }
        let payload: [String: Any] = [
            "class": collection,
            "properties": properties(from: patch, types: types)
        ]
        guard let body = try? WeaviateJSON.text(payload) else { return nil }
        return WeaviateWriteRequest(
            method: "PATCH",
            path: "/v1/objects/\(WeaviatePathEncoding.segment(uuid))",
            query: ["class": collection],
            body: body
        )
    }

    private static func delete(collection: String, change: WeaviateTrackedChange) -> WeaviateWriteRequest? {
        guard let uuid = change.uuid, !uuid.isEmpty else { return nil }
        return WeaviateWriteRequest(
            method: "DELETE",
            path: "/v1/objects/\(WeaviatePathEncoding.segment(uuid))",
            query: ["class": collection],
            body: nil
        )
    }

    private static func properties(from values: [String: String?], types: [String: String]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (column, text) in values {
            if WeaviateSchema.immutableColumns.contains(column) { continue }
            if column.hasPrefix("_") { continue }
            if let text {
                result[column] = WeaviateJSON.parsedValue(text, typeName: types[column] ?? "text")
            } else {
                result[column] = NSNull()
            }
        }
        return result
    }
}
