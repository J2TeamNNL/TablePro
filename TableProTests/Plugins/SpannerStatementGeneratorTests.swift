import Foundation
import TableProPluginKit
import Testing

@Suite("Spanner statement generator")
struct SpannerStatementGeneratorTests {
    @Test("UPDATE WHERE uses primary key columns only")
    func updateUsesPrimaryKey() {
        let generator = SpannerStatementGenerator(
            schema: "",
            tableName: "Singers",
            columns: ["SingerId", "Name", "Bio"],
            columnTypeNames: ["INT64", "STRING", "STRING"],
            primaryKeyColumns: ["SingerId"],
            dialect: .googleSQL
        )
        let change = PluginRowChange(
            rowIndex: 0,
            type: .update,
            cellChanges: [
                (columnIndex: 1, columnName: "Name", oldValue: "Ada", newValue: "Ada Lovelace")
            ],
            originalRow: ["1", "Ada", "old"]
        )
        let statements = generator.generateStatements(
            from: [change],
            insertedRowData: [:],
            deletedRowIndices: [],
            insertedRowIndices: []
        )
        #expect(statements.count == 1)
        #expect(statements[0].statement == "UPDATE `Singers` SET `Name` = 'Ada Lovelace' WHERE `SingerId` = 1")
    }

    @Test("PostgreSQL INSERT quotes the public schema")
    func postgresInsert() {
        let generator = SpannerStatementGenerator(
            schema: "public",
            tableName: "singers",
            columns: ["id", "name"],
            columnTypeNames: ["INT64", "STRING"],
            primaryKeyColumns: ["id"],
            dialect: .postgreSQL
        )
        let change = PluginRowChange(
            rowIndex: 0,
            type: .insert,
            cellChanges: [
                (columnIndex: 0, columnName: "id", oldValue: nil, newValue: "2"),
                (columnIndex: 1, columnName: "name", oldValue: nil, newValue: "Grace")
            ],
            originalRow: nil
        )
        let statements = generator.generateStatements(
            from: [change],
            insertedRowData: [:],
            deletedRowIndices: [],
            insertedRowIndices: [0]
        )
        #expect(statements.count == 1)
        #expect(
            statements[0].statement
                == "INSERT INTO \"public\".\"singers\" (\"id\", \"name\") VALUES (2, 'Grace')"
        )
    }
}

@Suite("Spanner SQL classification")
struct SpannerSQLClassificationTests {
    @Test("Keywords map to query, DML, DDL, and transaction kinds")
    func classify() {
        #expect(SpannerSQLClassification.classify("SELECT 1") == .query)
        #expect(SpannerSQLClassification.classify("  insert into t values (1)") == .dml)
        #expect(SpannerSQLClassification.classify("CREATE TABLE t (id INT64) PRIMARY KEY (id)") == .ddl)
        #expect(SpannerSQLClassification.classify("BEGIN") == .begin)
        #expect(SpannerSQLClassification.classify("COMMIT") == .commit)
        #expect(SpannerSQLClassification.classify("ROLLBACK") == .rollback)
        #expect(SpannerSQLClassification.classify("EXPLAIN SELECT 1") == .query)
    }

    @Test("EXPLAIN prefix is stripped")
    func stripExplain() {
        let stripped = SpannerSQLClassification.stripExplainPrefix("EXPLAIN SELECT 1")
        #expect(stripped.isExplain)
        #expect(stripped.sql == "SELECT 1")
    }
}
