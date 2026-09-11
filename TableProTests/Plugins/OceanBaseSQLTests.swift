import Foundation
import Testing

@Suite("OceanBase SQL rewrite")
struct OceanBaseSQLTests {
    private func quote(_ name: String) -> String {
        "`\(name.replacingOccurrences(of: "`", with: "``"))`"
    }

    @Test("The visibility hint sits after the first verb")
    func hintFollowsTheVerb() {
        #expect(
            OceanBaseSQL.withHiddenColumnVisibilityHint("SELECT * FROM t")
                == "SELECT \(OceanBaseSQL.visibilityHint) * FROM t"
        )
        #expect(
            OceanBaseSQL.withHiddenColumnVisibilityHint("UPDATE t SET a = 1 WHERE b = 2")
                == "UPDATE \(OceanBaseSQL.visibilityHint) t SET a = 1 WHERE b = 2"
        )
        #expect(
            OceanBaseSQL.withHiddenColumnVisibilityHint("DELETE FROM t WHERE id = 1")
                == "DELETE \(OceanBaseSQL.visibilityHint) FROM t WHERE id = 1"
        )
    }

    @Test("SHOW, SET and KILL are left alone")
    func sessionCommandsAreNotHinted() {
        for sql in ["SHOW FULL COLUMNS FROM t", "SET SESSION max_execution_time = 1000", "KILL QUERY 42"] {
            #expect(OceanBaseSQL.withHiddenColumnVisibilityHint(sql) == sql)
        }
    }

    @Test("A statement that already carries the hint is not hinted again")
    func existingHintIsKept() {
        let sql = "SELECT \(OceanBaseSQL.visibilityHint) `__pk_increment` FROM t LIMIT 0"
        #expect(OceanBaseSQL.withHiddenColumnVisibilityHint(sql) == sql)
    }

    @Test("SELECT * from a table expands with hidden primary key columns")
    func selectStarProjectsHiddenKeys() {
        let rewritten = OceanBaseSQL.projectingHiddenPrimaryKeys(
            sql: "SELECT * FROM orders",
            hiddenColumns: ["__pk_increment"],
            quote: quote
        )
        #expect(rewritten == "SELECT \(OceanBaseSQL.visibilityHint) *, `__pk_increment` FROM orders")
    }

    @Test("SELECT * from a subquery is not expanded")
    func subquerySelectStarIsNotExpanded() {
        let sql = "SELECT * FROM (SELECT 1) AS x"
        #expect(OceanBaseSQL.simpleSelectStarTable(from: sql) == nil)
        #expect(
            OceanBaseSQL.projectingHiddenPrimaryKeys(sql: sql, hiddenColumns: ["__pk_increment"], quote: quote)
                == "SELECT \(OceanBaseSQL.visibilityHint) * FROM (SELECT 1) AS x"
        )
    }

    @Test("A qualified identifier keeps the table name, not the schema")
    func qualifiedTableName() {
        #expect(OceanBaseSQL.simpleSelectStarTable(from: "SELECT * FROM `test`.`orders`") == "orders")
        #expect(OceanBaseSQL.simpleSelectStarTable(from: "select * from orders WHERE 1") == "orders")
    }

    @Test("Hidden primary key names are the ones SHOW INDEX lists that SHOW COLUMNS omits")
    func hiddenNamesComeFromThePrimaryIndex() {
        #expect(
            OceanBaseSQL.hiddenPrimaryKeyColumns(
                primaryIndexColumns: ["__pk_increment"],
                visibleColumnNames: ["id", "name"]
            ) == ["__pk_increment"]
        )
        #expect(
            OceanBaseSQL.hiddenPrimaryKeyColumns(
                primaryIndexColumns: ["id"],
                visibleColumnNames: ["id", "name"]
            ).isEmpty
        )
        #expect(
            OceanBaseSQL.hiddenPrimaryKeyColumns(
                primaryIndexColumns: ["__pk_increment", "__pk_cluster_column"],
                visibleColumnNames: ["name"]
            ) == ["__pk_increment", "__pk_cluster_column"]
        )
    }

    @Test("The documented probe names a hidden column under the visibility hint")
    func documentedProbe() {
        #expect(
            OceanBaseSQL.documentedHiddenColumnProbe(table: "orders", column: "__pk_increment", quote: quote)
                == "SELECT \(OceanBaseSQL.visibilityHint) `__pk_increment` FROM `orders` LIMIT 0"
        )
    }
}
