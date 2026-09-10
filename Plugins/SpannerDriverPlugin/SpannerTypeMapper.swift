import Foundation
import TableProPluginKit

internal struct SpannerType: Decodable, Sendable, Equatable {
    let code: String
    let arrayElementType: SpannerType?
    let structType: SpannerStructType?
    let typeAnnotation: String?

    func displayName() -> String {
        let upper = code.uppercased()
        if upper == "ARRAY", let element = arrayElementType {
            return "ARRAY<\(element.displayName())>"
        }
        if upper == "STRUCT", let fields = structType?.fields {
            let inner = fields.map { "\($0.name) \($0.type.displayName())" }.joined(separator: ", ")
            return "STRUCT<\(inner)>"
        }
        switch typeAnnotation?.uppercased() {
        case "PG_JSONB":
            return "JSONB"
        default:
            return upper
        }
    }

    var isBytes: Bool {
        code.uppercased() == "BYTES"
    }
}

internal struct SpannerStructType: Decodable, Sendable, Equatable {
    let fields: [SpannerField]
}

internal struct SpannerField: Decodable, Sendable, Equatable {
    let name: String
    let type: SpannerType
}

internal enum SpannerJSONValue: Decodable, Sendable, Equatable {
    case null
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([SpannerJSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        if let flag = try? container.decode(Bool.self) {
            self = .bool(flag)
            return
        }
        if let text = try? container.decode(String.self) {
            self = .string(text)
            return
        }
        if let number = try? container.decode(Double.self) {
            self = .number(number)
            return
        }
        if let items = try? container.decode([SpannerJSONValue].self) {
            self = .array(items)
            return
        }
        self = .null
    }

    var asText: String? {
        switch self {
        case .null:
            return nil
        case .string(let text):
            return text
        case .number(let number):
            if number.rounded() == number, let exact = Int64(exactly: number) {
                return String(exact)
            }
            return String(number)
        case .bool(let flag):
            return flag ? "true" : "false"
        case .array(let items):
            return "[\(items.map { $0.asText ?? "null" }.joined(separator: ", "))]"
        }
    }
}

internal struct SpannerTypeMapper {
    static func flattenRows(
        _ rows: [[SpannerJSONValue]],
        fields: [SpannerField]
    ) -> [[PluginCellValue]] {
        rows.map { row in
            fields.enumerated().map { index, field in
                let value: SpannerJSONValue = index < row.count ? row[index] : .null
                return cellValue(value, type: field.type)
            }
        }
    }

    static func columnTypeNames(from fields: [SpannerField]) -> [String] {
        fields.map { $0.type.displayName() }
    }

    static func columnInfos(from fields: [SpannerField]) -> [PluginColumnInfo] {
        fields.map { field in
            PluginColumnInfo(
                name: field.name,
                dataType: field.type.displayName(),
                isNullable: true,
                isPrimaryKey: false
            )
        }
    }

    static func cellValue(_ value: SpannerJSONValue, type: SpannerType) -> PluginCellValue {
        switch value {
        case .null:
            return .null
        case .string(let text) where type.isBytes:
            if let data = Data(base64Encoded: text) {
                return .bytes(data)
            }
            return .text(text)
        case .array(let items) where type.code.uppercased() == "STRUCT" || type.code.uppercased() == "ARRAY":
            return .text(serializeJSON(items, type: type))
        default:
            return value.asText.map { .text($0) } ?? .null
        }
    }

    private static func serializeJSON(_ items: [SpannerJSONValue], type: SpannerType) -> String {
        if type.code.uppercased() == "STRUCT", let fields = type.structType?.fields {
            let pairs = fields.enumerated().map { index, field -> String in
                let value = index < items.count ? items[index] : .null
                return "\"\(escapeJSON(field.name))\":\(serializeAtom(value, type: field.type))"
            }
            return "{\(pairs.joined(separator: ","))}"
        }
        let element = type.arrayElementType
        let encoded = items.map { item in
            if let element {
                return serializeAtom(item, type: element)
            }
            return serializeAtom(item, type: SpannerType(code: "STRING", arrayElementType: nil, structType: nil, typeAnnotation: nil))
        }
        return "[\(encoded.joined(separator: ","))]"
    }

    private static func serializeAtom(_ value: SpannerJSONValue, type: SpannerType) -> String {
        switch value {
        case .null:
            return "null"
        case .bool(let flag):
            return flag ? "true" : "false"
        case .number(let number):
            if number.rounded() == number, let exact = Int64(exactly: number) {
                return String(exact)
            }
            return String(number)
        case .string(let text):
            switch type.code.uppercased() {
            case "INT64", "FLOAT32", "FLOAT64", "NUMERIC", "BOOL":
                return text
            default:
                return "\"\(escapeJSON(text))\""
            }
        case .array(let items):
            return serializeJSON(items, type: type)
        }
    }

    private static func escapeJSON(_ text: String) -> String {
        var result = ""
        result.reserveCapacity((text as NSString).length)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"":
                result.append("\\\"")
            case "\\":
                result.append("\\\\")
            case "\n":
                result.append("\\n")
            case "\r":
                result.append("\\r")
            case "\t":
                result.append("\\t")
            default:
                if scalar.value < 0x20 {
                    result.append(String(format: "\\u%04x", scalar.value))
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result
    }
}
