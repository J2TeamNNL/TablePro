import TableProTrinoCore
import Testing

struct TrinoIntrospectionSQLTests {
    @Test("A schema set is listed in one query that names each schema and projects it")
    func schemaSetListing() {
        let statement = TrinoIntrospectionSQL.listTables(catalog: "hive", inSchemas: ["sales", "o'brien"])
        #expect(statement.contains("FROM \"hive\".information_schema.tables"))
        #expect(statement.contains("WHERE table_schema IN ('sales', 'o''brien')"))
        #expect(statement.contains("SELECT table_name, table_type, table_schema"))
        #expect(TrinoIntrospectionSQL.listTables(catalog: "hive", inSchemas: []).contains("WHERE false"))
    }

    @Test("A schema set's materialized views come from one query that projects the schema")
    func schemaSetMaterializedViews() {
        let statement = TrinoIntrospectionSQL.listMaterializedViews(catalog: "iceberg", inSchemas: ["a", "b"])
        #expect(statement.contains("SELECT name, schema_name FROM system.metadata.materialized_views"))
        #expect(statement.contains("catalog_name = 'iceberg' AND schema_name IN ('a', 'b')"))
    }

    @Test("A quote that a combining mark follows is still doubled")
    func combiningMarkCannotHideAQuote() {
        #expect(TrinoIntrospectionSQL.quoteLiteral("x'\u{301} OR true--") == "'x''\u{301} OR true--'")
        #expect(TrinoIntrospectionSQL.quoteIdentifier("a\"\u{301}") == "\"a\"\"\u{301}\"")
    }
}
