//
//  AISchemaContextRelevanceTests.swift
//  TableProTests
//
//  A schema with more tables than the prompt's column budget spends that budget on the tables
//  the question names, and still tells the model what the other tables are called.
//

import Foundation
@testable import TablePro
import TableProPluginKit
import Testing

struct AISchemaContextRelevanceTests {
    private static let tables: [TableInfo] = [
        TestFixtures.makeTableInfo(name: "audit_log"),
        TestFixtures.makeTableInfo(name: "customers"),
        TestFixtures.makeTableInfo(name: "invoices"),
        TableInfo(name: "tbl_x", type: .table, rowCount: 0, comment: "Monthly revenue snapshots"),
        TestFixtures.makeTableInfo(name: "orders")
    ]

    @Test("Tables that match the question come first, best first")
    func matchingTablesComeFirst() {
        let names = AISchemaContext.relevantTableNames(
            in: Self.tables,
            columnsByTable: [:],
            question: "How many orders did each customer place?",
            maxTables: 2
        )
        #expect(Array(names.prefix(2)).sorted() == ["customers", "orders"])
    }

    @Test("A table comment and loaded columns count as matches")
    func commentAndColumnsMatch() {
        let columns = ["invoices": [TestFixtures.makeColumnInfo(name: "due_date")]]
        #expect(AISchemaContext.relevantTableNames(
            in: Self.tables, columnsByTable: columns, question: "revenue by month", maxTables: 2
        ).first == "tbl_x")
        #expect(AISchemaContext.relevantTableNames(
            in: Self.tables, columnsByTable: columns, question: "unpaid past the due date", maxTables: 2
        ).first == "invoices")
    }

    @Test("Nothing is reordered when every table fits")
    func everyTableFits() {
        let names = AISchemaContext.relevantTableNames(
            in: Self.tables,
            columnsByTable: [:],
            question: "orders",
            maxTables: Self.tables.count
        )
        #expect(names.isEmpty)
    }

    @Test("Tables past the budget are named without their columns")
    func hiddenTablesAreNamed() {
        let entries = Self.tables.map { AISchemaTable(table: $0) }
        let section = AISchemaContext.buildSchemaSection(
            tables: entries,
            defaultSchema: nil,
            maxTables: 2,
            identifierQuote: "\""
        )
        #expect(section.contains("Other tables (columns not shown): \"invoices\", \"tbl_x\", \"orders\""))
        #expect(!section.contains("more tables (not shown)"))
    }

    @Test("A long tail of hidden tables is cut with a count")
    func longTailIsCounted() {
        let many = (0..<(AISchemaContext.maxListedHiddenTables + 3)).map {
            AISchemaTable(table: TestFixtures.makeTableInfo(name: "t\($0)"))
        }
        let section = AISchemaContext.buildSchemaSection(
            tables: many,
            defaultSchema: nil,
            maxTables: 1,
            identifierQuote: "\""
        )
        #expect(section.hasSuffix(", … and 2 more"))
    }
}
