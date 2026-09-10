import Foundation
import TableProPluginKit
import Testing

@Suite("Spanner query builder")
struct SpannerQueryBuilderTests {
    @Test("Browse SQL uses backticks on GoogleSQL and empty schema")
    func googleSQLBrowse() throws {
        let tagged = SpannerQueryBuilder.encodeBrowseQuery(
            table: "Singers",
            schema: "",
            dialect: .googleSQL,
            sortColumns: [(columnIndex: 0, ascending: true)],
            limit: 50,
            offset: 10
        )
        #expect(SpannerQueryBuilder.isTaggedQuery(tagged))
        let params = try #require(SpannerQueryBuilder.decode(tagged))
        let sql = SpannerQueryBuilder.buildSQL(from: params, columns: ["SingerId", "Name"])
        #expect(sql == "SELECT * FROM `Singers` ORDER BY `SingerId` ASC LIMIT 50 OFFSET 10")
    }

    @Test("Browse SQL quotes public schema on PostgreSQL dialect")
    func postgreSQLBrowse() throws {
        let tagged = SpannerQueryBuilder.encodeBrowseQuery(
            table: "singers",
            schema: "public",
            dialect: .postgreSQL,
            sortColumns: [],
            limit: 20,
            offset: 0
        )
        let params = try #require(SpannerQueryBuilder.decode(tagged))
        let sql = SpannerQueryBuilder.buildSQL(from: params, columns: ["id"])
        #expect(sql == "SELECT * FROM \"public\".\"singers\" LIMIT 20 OFFSET 0")
    }

    @Test("Filter equality becomes a WHERE clause")
    func filterEquals() throws {
        let tagged = SpannerQueryBuilder.encodeFilteredQuery(
            table: "Singers",
            schema: "",
            dialect: .googleSQL,
            filters: [PluginQueryFilter(column: "Name", op: "=", value: "Ada")],
            logicMode: "AND",
            sortColumns: [],
            limit: 10,
            offset: 0
        )
        let params = try #require(SpannerQueryBuilder.decode(tagged))
        let sql = SpannerQueryBuilder.buildSQL(from: params, columns: ["Name"])
        #expect(sql.contains("WHERE `Name` = 'Ada'"))
        #expect(sql.contains("LIMIT 10 OFFSET 0"))
    }

    @Test("Dialect parse maps POSTGRESQL and defaults to GoogleSQL")
    func dialectParse() {
        #expect(SpannerDialectKind.parse("POSTGRESQL") == .postgreSQL)
        #expect(SpannerDialectKind.parse("GOOGLE_STANDARD_SQL") == .googleSQL)
        #expect(SpannerDialectKind.parse(nil) == .googleSQL)
    }
}
