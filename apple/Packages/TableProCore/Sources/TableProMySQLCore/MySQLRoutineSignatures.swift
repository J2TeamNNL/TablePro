public struct MySQLRoutineSignatures: Sendable {
    private struct Identity: Hashable, Sendable {
        let schema: String
        let name: String
        let kind: String
    }

    private var parameters: [Identity: String] = [:]

    public init(rows: [[String?]]) {
        for row in rows {
            guard row.count >= 4,
                  let schema = row[0],
                  let name = row[1],
                  let kind = row[2],
                  let signature = row[3]
            else { continue }
            parameters[Identity(schema: schema, name: name, kind: kind.uppercased())] = signature
        }
    }

    public func parameterList(schema: String, name: String, kind: String) -> String {
        parameters[Identity(schema: schema, name: name, kind: kind.uppercased())] ?? ""
    }
}
