//
//  DatabaseSearchColumnPlanner.swift
//  TablePro
//

import Foundation
import TableProPluginKit

internal enum DatabaseSearchColumnPlanner {
    internal struct Column: Equatable, Sendable {
        internal let name: String
        internal let type: ColumnType

        internal init(name: String, type: ColumnType) {
            self.name = name
            self.type = type
        }
    }

    private struct Match {
        let filterOperator: FilterOperator
        let isCaseSensitive: Bool
    }

    internal static func filters(for columns: [Column], options: DatabaseSearchOptions) -> [TableFilter] {
        let term = options.trimmedTerm
        guard !term.isEmpty else { return [] }
        return columns.compactMap { column in
            guard let match = match(for: column.type, term: term, options: options) else { return nil }
            return TableFilter(
                columnName: column.name,
                filterOperator: match.filterOperator,
                value: term,
                isCaseSensitive: match.isCaseSensitive
            )
        }
    }

    private static func match(for type: ColumnType, term: String, options: DatabaseSearchOptions) -> Match? {
        let textMatch = Match(filterOperator: options.matchMode.textOperator, isCaseSensitive: options.isCaseSensitive)
        // A typed comparison keeps the column's own type and its index, so it never folds case.
        let typedMatch = Match(filterOperator: .equal, isCaseSensitive: true)

        switch type {
        case .text(let rawType):
            if type.isUUIDType {
                return UUID(uuidString: term) != nil ? typedMatch : nil
            }
            guard type.hasEmptyValue else { return nil }
            if options.matchMode.usesPattern {
                return patternRefusingTypes.contains(baseTypeName(rawType)) ? nil : textMatch
            }
            guard ColumnTypeSQLQuoting.hasEqualityOperator(type),
                  ColumnTypeSQLQuoting.isCharacterType(.text(rawType: unwrappedTypeName(rawType)))
            else { return nil }
            return textMatch
        case .enumType, .set:
            if options.matchMode.usesPattern { return textMatch }
            // An engine refuses `=` against a label its enum does not declare; a SET value is a list of them.
            guard let labels = type.enumValues else { return nil }
            let parts = type.isSetType
                ? term.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
                : [term]
            let declared = parts.allSatisfy { part in labels.contains { matchesLabel($0, part, options) } }
            return declared ? textMatch : nil
        case .json:
            return options.matchMode.usesPattern ? textMatch : nil
        case .integer:
            return RowValueCopyFormatter.isIntegerLiteral(term) ? typedMatch : nil
        case .decimal:
            return PluginNumericLiteral.isValid(term) ? typedMatch : nil
        case .date:
            guard !type.isTimeOnly else { return nil }
            return DatabaseSearchTermParser.isDate(term) ? typedMatch : nil
        case .timestamp, .datetime:
            guard !type.isTimeOnly else { return nil }
            return DatabaseSearchTermParser.isDateTime(term) ? typedMatch : nil
        case .blob:
            guard options.includesBinaryColumns, options.matchMode.usesPattern else { return nil }
            return textMatch
        case .boolean, .spatial, .array:
            return nil
        }
    }

    private static func matchesLabel(_ label: String, _ term: String, _ options: DatabaseSearchOptions) -> Bool {
        options.isCaseSensitive ? label == term : label.caseInsensitiveCompare(term) == .orderedSame
    }

    // SQL Server and Oracle refuse LIKE on XML, and Oracle on LONG.
    private static let patternRefusingTypes: Set<String> = ["XML", "XMLTYPE", "LONG"]

    private static let typeWrappers = ["NULLABLE(", "LOWCARDINALITY("]

    private static func unwrappedTypeName(_ rawType: String?) -> String? {
        guard var name = rawType?.trimmingCharacters(in: .whitespaces) else { return nil }
        while let wrapper = typeWrappers.first(where: { name.uppercased().hasPrefix($0) }), name.hasSuffix(")") {
            name = String(name.dropFirst(wrapper.count).dropLast())
        }
        return name
    }

    private static func baseTypeName(_ rawType: String?) -> String {
        guard let name = unwrappedTypeName(rawType) else { return "" }
        return name.prefix { $0 != "(" }.trimmingCharacters(in: .whitespaces).uppercased()
    }
}

internal enum DatabaseSearchTermParser {
    internal static func isDate(_ term: String) -> Bool {
        let characters = Array(term)
        guard characters.count == 10 else { return false }
        return isCalendarDate(characters)
    }

    // `yyyy-MM-dd HH:mm:ss` with an optional fraction, a space or `T` between: the one shape every engine,
    // Oracle's ANSI literal included, reads as a timestamp.
    internal static func isDateTime(_ term: String) -> Bool {
        let characters = Array(term)
        guard characters.count >= 19, characters[10] == " " || characters[10] == "T",
              isCalendarDate(Array(characters[0..<10])),
              let hour = number(characters, 11..<13), (0...23).contains(hour), characters[13] == ":",
              let minute = number(characters, 14..<16), (0...59).contains(minute), characters[16] == ":",
              let second = number(characters, 17..<19), (0...59).contains(second)
        else { return false }
        guard characters.count > 19 else { return true }
        let fraction = characters[20...]
        return characters[19] == "." && (1...9).contains(fraction.count) && fraction.allSatisfy(\.isASCIIDigit)
    }

    private static func isCalendarDate(_ characters: [Character]) -> Bool {
        guard characters.count == 10, characters[4] == "-", characters[7] == "-",
              let year = number(characters, 0..<4),
              let month = number(characters, 5..<7),
              let day = number(characters, 8..<10)
        else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return DateComponents(year: year, month: month, day: day).isValidDate(in: calendar)
    }

    private static func number(_ characters: [Character], _ range: Range<Int>) -> Int? {
        let slice = characters[range]
        guard slice.allSatisfy(\.isASCIIDigit) else { return nil }
        return Int(String(slice))
    }
}

private extension Character {
    var isASCIIDigit: Bool {
        isASCII && isNumber
    }
}
