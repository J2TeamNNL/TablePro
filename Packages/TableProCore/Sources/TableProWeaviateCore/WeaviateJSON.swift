import Foundation

public enum WeaviateJSON {
    public static func object(from data: Data) throws -> Any {
        do {
            return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw WeaviateError.malformedResponse(error.localizedDescription)
        }
    }

    public static func dictionary(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    public static func data(_ object: Any, pretty: Bool = false) throws -> Data {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw WeaviateError.malformedResponse("Request body is not valid JSON.")
        }
        var options: JSONSerialization.WritingOptions = [.sortedKeys]
        if pretty {
            options.insert(.prettyPrinted)
        }
        return try JSONSerialization.data(withJSONObject: object, options: options)
    }

    public static func text(_ object: Any, pretty: Bool = false) throws -> String {
        let encoded = try data(object, pretty: pretty)
        return String(data: encoded, encoding: .utf8) ?? "{}"
    }

    public static func displayText(_ value: Any?) -> String? {
        switch value {
        case nil, is NSNull:
            return nil
        case let text as String:
            return text
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        case let object as [String: Any]:
            return (try? text(object)) ?? nil
        case let object as [Any]:
            return (try? text(object)) ?? nil
        default:
            return String(describing: value as Any)
        }
    }

    public static func parsedValue(_ text: String, typeName: String) -> Any {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = typeName.lowercased()
        if lowered == "boolean" || lowered == "bool" {
            if trimmed.lowercased() == "true" { return true }
            if trimmed.lowercased() == "false" { return false }
        }
        if lowered == "int" || lowered == "int[]" || lowered.hasPrefix("int") {
            if let intVal = Int(trimmed) { return intVal }
        }
        if lowered == "number" || lowered == "number[]" {
            if let doubleVal = Double(trimmed) { return doubleVal }
        }
        if let data = trimmed.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) {
            if parsed is [Any] { return parsed }
            if parsed is [String: Any] { return parsed }
        }
        return text
    }
}
