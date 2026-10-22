import Foundation
@testable import TableProAutocomplete
import TableProSQLGrammar
import Testing

struct SQLContextAnalyzerTableReferenceTests {
    private let analyzer = SQLContextAnalyzer()

    private func tables(_ statement: String) -> [String] {
        analyzer.tableReferences(in: statement, grammar: .ansi).map(\.tableName)
    }

    @Test("A statement that ends in a comment still names its tables")
    func trailingComment() {
        #expect(tables("SELECT * FROM orders -- recent orders") == ["orders"])
        #expect(tables("SELECT * FROM orders /* recent */") == ["orders"])
        #expect(analyzer.analyze(query: "SELECT * FROM orders -- recent", cursorPosition: 30).tableReferences.isEmpty)
    }

    @Test("A statement that ends in a string still names its tables")
    func trailingLiteral() {
        #expect(tables("SELECT * FROM orders WHERE note = 'open") == ["orders"])
    }

    @Test("Joined, updated and altered tables are named")
    func everyClause() {
        #expect(tables("SELECT * FROM orders o JOIN customers c ON c.id = o.customer_id") == ["orders", "customers"])
        #expect(tables("UPDATE customers SET name = 'x'").contains("customers"))
        #expect(tables("ALTER TABLE invoices ADD COLUMN due DATE") == ["invoices"])
    }
}
