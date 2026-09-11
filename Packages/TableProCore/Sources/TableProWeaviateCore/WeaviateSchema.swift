import Foundation

public struct WeaviateProperty: Sendable, Equatable {
    public let name: String
    public let dataType: String

    public init(name: String, dataType: String) {
        self.name = name
        self.dataType = dataType
    }

    public static func parse(_ json: [String: Any]) -> WeaviateProperty? {
        guard let name = json["name"] as? String, !name.isEmpty else { return nil }
        let types = json["dataType"] as? [String] ?? []
        let dataType = types.first ?? "text"
        return WeaviateProperty(name: name, dataType: dataType)
    }
}

public struct WeaviateCollection: Sendable, Equatable {
    public let name: String
    public let properties: [WeaviateProperty]
    public let vectorizer: String?

    public init(name: String, properties: [WeaviateProperty], vectorizer: String? = nil) {
        self.name = name
        self.properties = properties
        self.vectorizer = vectorizer
    }

    public static func parse(_ json: [String: Any]) -> WeaviateCollection? {
        guard let name = json["class"] as? String, !name.isEmpty else { return nil }
        let rawProperties = json["properties"] as? [[String: Any]] ?? []
        let properties = rawProperties.compactMap(WeaviateProperty.parse)
        return WeaviateCollection(
            name: name,
            properties: properties,
            vectorizer: json["vectorizer"] as? String
        )
    }
}

public enum WeaviateSchema {
    public static let uuidColumn = "uuid"
    public static let vectorColumn = "vector"
    public static let metaColumns: [String] = [uuidColumn, vectorColumn]
    public static let immutableColumns: [String] = [uuidColumn, vectorColumn]

    public static func collections(from json: Any) -> [WeaviateCollection] {
        let classes: [[String: Any]]
        if let object = json as? [String: Any] {
            classes = object["classes"] as? [[String: Any]] ?? []
        } else if let array = json as? [[String: Any]] {
            classes = array
        } else {
            return []
        }
        return classes.compactMap(WeaviateCollection.parse)
    }

    public static func columns(for collection: WeaviateCollection) -> [(name: String, type: String, isPrimaryKey: Bool)] {
        var result: [(name: String, type: String, isPrimaryKey: Bool)] = [
            (uuidColumn, "uuid", true)
        ]
        result += collection.properties.map { ($0.name, $0.dataType, false) }
        result.append((vectorColumn, "vector", false))
        return result
    }
}
