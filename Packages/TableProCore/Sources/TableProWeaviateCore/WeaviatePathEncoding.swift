import Foundation

public enum WeaviatePathEncoding {
    private static let allowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-_")
        return set
    }()

    public static func segment(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    public static func resolve(_ path: String, query: [String: String] = [:], against base: URL) -> URL? {
        guard path.hasPrefix("/"), !path.contains("://") else { return nil }
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = path
        if query.isEmpty {
            components.queryItems = nil
        } else {
            components.queryItems = query.keys.sorted().map { URLQueryItem(name: $0, value: query[$0]) }
        }
        return components.url
    }
}
