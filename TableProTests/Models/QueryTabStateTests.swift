import Foundation
@testable import TablePro
import Testing

@Suite("Query tab state")
struct QueryTabStateTests {
    @Test("Persisted ER diagram tab preserves focused table")
    func persistedERDiagramTabPreservesFocusedTable() throws {
        let original = PersistedTab(
            id: UUID(),
            title: "ER: orders",
            query: "",
            tabType: .erDiagram,
            tableName: nil,
            databaseName: "shop",
            erDiagramSchemaKey: "shop.default",
            erDiagramFocusedTable: "orders"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PersistedTab.self, from: data)

        #expect(decoded.erDiagramSchemaKey == "shop.default")
        #expect(decoded.erDiagramFocusedTable == "orders")
    }

    @Test("Display state equality includes ER diagram routing fields")
    func displayStateEqualityIncludesERDiagramRoutingFields() {
        var lhs = TabDisplayState()
        var rhs = TabDisplayState()

        lhs.erDiagramSchemaKey = "shop.default"
        rhs.erDiagramSchemaKey = "shop.default"
        lhs.erDiagramFocusedTable = "orders"
        rhs.erDiagramFocusedTable = "orders"

        #expect(lhs == rhs)

        rhs.erDiagramFocusedTable = "customers"
        #expect(lhs != rhs)

        rhs.erDiagramFocusedTable = "orders"
        rhs.erDiagramSchemaKey = "analytics.default"
        #expect(lhs != rhs)
    }
}
