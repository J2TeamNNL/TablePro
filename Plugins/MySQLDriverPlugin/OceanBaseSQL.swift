import Foundation

internal enum OceanBaseSQL {
    static let visibilityHint = "/*+ opt_param('hidden_column_visible','true') */"
    static let incrementColumn = "__pk_increment"
    static let clusterColumn = "__pk_cluster_column"
    static let documentedHiddenNames = [incrementColumn, clusterColumn]

    private static let hintedVerbs: Set<String> = [
        "SELECT", "UPDATE", "DELETE", "INSERT", "REPLACE"
    ]

    static func isDocumentedHiddenName(_ name: String) -> Bool {
        documentedHiddenNames.contains(name)
    }

    static func hiddenPrimaryKeyColumns(
        primaryIndexColumns: [String],
        visibleColumnNames: Set<String>
    ) -> [String] {
        var seen = Set<String>()
        var hidden: [String] = []
        for column in primaryIndexColumns where !visibleColumnNames.contains(column) {
            guard seen.insert(column).inserted else { continue }
            hidden.append(column)
        }
        return hidden
    }

    static func withHiddenColumnVisibilityHint(_ sql: String) -> String {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return sql }
        if trimmed.contains("hidden_column_visible") { return sql }
        guard let verbEnd = firstKeywordEnd(in: trimmed) else { return sql }
        let verb = String(trimmed[trimmed.startIndex..<verbEnd]).uppercased()
        guard hintedVerbs.contains(verb) else { return sql }
        return "\(trimmed[trimmed.startIndex..<verbEnd]) \(visibilityHint)\(trimmed[verbEnd...])"
    }

    static func projectingHiddenPrimaryKeys(
        sql: String,
        hiddenColumns: [String],
        quote: (String) -> String
    ) -> String {
        let hinted = withHiddenColumnVisibilityHint(sql)
        guard !hiddenColumns.isEmpty else { return hinted }
        guard simpleSelectStarTable(from: hinted) != nil else { return hinted }
        let extras = hiddenColumns.map(quote).joined(separator: ", ")
        guard let regex = try? NSRegularExpression(
            pattern: #"(?is)^(SELECT(?:\s+/\*\+[^*]*\*/)?)\s+\*\s+FROM\b"#
        ) else {
            return hinted
        }
        let nsSQL = hinted as NSString
        guard let match = regex.firstMatch(in: hinted, range: NSRange(location: 0, length: nsSQL.length)),
              match.numberOfRanges > 1
        else {
            return hinted
        }
        let prefix = nsSQL.substring(with: match.range(at: 1))
        let afterFrom = nsSQL.substring(from: match.range.upperBound)
        return "\(prefix) *, \(extras) FROM\(afterFrom)"
    }

    static func simpleSelectStarTable(from sql: String) -> String? {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(
            pattern: #"(?is)^SELECT(?:\s+/\*\+[^*]*\*/)?\s+\*\s+FROM\s+"#
        ) else {
            return nil
        }
        let nsSQL = trimmed as NSString
        guard let match = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: nsSQL.length)) else {
            return nil
        }
        var rest = nsSQL.substring(from: match.range.upperBound)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rest.hasPrefix("(") else { return nil }
        return trailingQualifiedIdentifier(from: &rest)
    }

    static func documentedHiddenColumnProbe(table: String, column: String, quote: (String) -> String) -> String {
        "SELECT \(visibilityHint) \(quote(column)) FROM \(quote(table)) LIMIT 0"
    }

    private static func firstKeywordEnd(in sql: String) -> String.Index? {
        var index = sql.startIndex
        while index < sql.endIndex, sql[index].isWhitespace {
            sql.formIndex(after: &index)
        }
        guard index < sql.endIndex, sql[index].isLetter else { return nil }
        while index < sql.endIndex, sql[index].isLetter {
            sql.formIndex(after: &index)
        }
        return index
    }

    private static func trailingQualifiedIdentifier(from rest: inout String) -> String? {
        var parts: [String] = []
        while let ident = parseLeadingIdentifier(from: &rest) {
            parts.append(ident)
            rest = rest.trimmingCharacters(in: .whitespacesAndNewlines)
            guard rest.hasPrefix(".") else { break }
            rest.removeFirst()
            rest = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return parts.last
    }

    private static func parseLeadingIdentifier(from rest: inout String) -> String? {
        rest = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = rest.first else { return nil }
        if first == "`" {
            rest.removeFirst()
            guard let end = rest.firstIndex(of: "`") else { return nil }
            let value = String(rest[..<end])
            rest = String(rest[rest.index(after: end)...])
            return value.replacingOccurrences(of: "``", with: "`")
        }
        if first == "\"" {
            rest.removeFirst()
            guard let end = rest.firstIndex(of: "\"") else { return nil }
            let value = String(rest[..<end])
            rest = String(rest[rest.index(after: end)...])
            return value.replacingOccurrences(of: "\"\"", with: "\"")
        }
        var index = rest.startIndex
        while index < rest.endIndex {
            let character = rest[index]
            if character.isLetter || character.isNumber || character == "_" {
                rest.formIndex(after: &index)
                continue
            }
            break
        }
        guard index > rest.startIndex else { return nil }
        let value = String(rest[..<index])
        rest = String(rest[index...])
        return value
    }
}
