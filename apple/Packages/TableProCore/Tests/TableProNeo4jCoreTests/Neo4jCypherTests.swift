import Foundation
@testable import TableProNeo4jCore
import Testing

struct Neo4jCypherTests {
    @Test("Identifiers are backtick-quoted with embedded backticks doubled")
    func quoting() {
        #expect(Neo4jCypher.quote("Person") == "`Person`")
        #expect(Neo4jCypher.quote("we`ird") == "`we``ird`")
        #expect(Neo4jCypher.literal(#"it's \ ok"#) == #"'it\'s \\ ok'"#)
    }

    @Test("A label browse pages, sorts and carries the marker the driver reads back")
    func labelBrowse() throws {
        let query = try Neo4jCypher.browseQuery(
            kind: .node,
            name: "Person",
            sort: [(column: "name", ascending: false), (column: "<id>", ascending: true)],
            limit: 200,
            offset: 400
        )
        #expect(query == """
        // TablePro browse: node
        MATCH (n:`Person`)
        RETURN n
        ORDER BY n.`name` DESC, elementId(n) ASC
        SKIP 400 LIMIT 200
        """)
        #expect(Neo4jCypher.browseKind(of: query) == .node)
        #expect(Neo4jCypher.browseKind(of: "MATCH (n) RETURN n") == nil)
    }

    @Test("A relationship browse matches directed relationships of one type")
    func relationshipBrowse() throws {
        let query = try Neo4jCypher.browseQuery(kind: .relationship, name: "KNOWS", limit: 10, offset: 0, usesElementId: false)
        #expect(query.contains("MATCH ()-[n:`KNOWS`]->()"))
        #expect(Neo4jCypher.browseKind(of: query) == .relationship)
    }

    @Test("Filters become a WHERE clause joined by the logic mode")
    func filters() throws {
        let query = try Neo4jCypher.browseQuery(
            kind: .node,
            name: "Person",
            filters: [
                Neo4jFilter(column: "age", op: ">=", value: "30"),
                Neo4jFilter(column: "name", op: "CONTAINS", value: "an", isCaseSensitive: false)
            ],
            matchesAll: false,
            limit: 10,
            offset: 0
        )
        #expect(query.contains("WHERE (n.`age` >= 30) OR (toLower(n.`name`) CONTAINS 'an')"))
    }

    @Test("Equality on a number also matches the same text stored as a string")
    func untypedEquality() throws {
        let clause = try Neo4jCypher.condition(for: Neo4jFilter(column: "zip", op: "=", value: "123"), usesElementId: true)
        #expect(clause == "(n.`zip` = 123 OR n.`zip` = '123')")
        let text = try Neo4jCypher.condition(for: Neo4jFilter(column: "name", op: "=", value: "Ann"), usesElementId: true)
        #expect(text == "n.`name` = 'Ann'")
        let id = try Neo4jCypher.condition(for: Neo4jFilter(column: "<id>", op: "=", value: "4:x:1"), usesElementId: true)
        #expect(id == "elementId(n) = '4:x:1'")
    }

    @Test("An unknown operator is refused")
    func unknownOperator() {
        #expect(throws: Neo4jCypherError.unsupportedOperator("~~")) {
            try Neo4jCypher.condition(for: Neo4jFilter(column: "a", op: "~~", value: "x"), usesElementId: true)
        }
    }

    @Test("Schema names map back to entity kinds")
    func kinds() {
        #expect(Neo4jEntityKind(schemaName: "Labels") == .node)
        #expect(Neo4jEntityKind(schemaName: "Relationship Types") == .relationship)
        #expect(Neo4jEntityKind(schemaName: "public") == nil)
    }
}
