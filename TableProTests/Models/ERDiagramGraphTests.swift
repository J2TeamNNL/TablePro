import Foundation
@testable import TablePro
import Testing

@Suite("ERDiagramGraph")
struct ERDiagramGraphTests {
    @Test("Focused subgraph includes direct incoming and outgoing relationships")
    func focusedSubgraphIncludesDirectRelationships() {
        let graph = Self.graph(
            tableNames: ["users", "orders", "line_items", "audit_logs"],
            edges: [
                Self.edge(from: "orders", to: "users"),
                Self.edge(from: "line_items", to: "orders"),
                Self.edge(from: "audit_logs", to: "users")
            ]
        )

        let focused = graph.subgraph(focusedOn: "orders")

        #expect(focused.nodes.map(\.tableName) == ["users", "orders", "line_items"])
        #expect(focused.edges.map { "\($0.fromTable)->\($0.toTable)" } == ["orders->users", "line_items->orders"])
        #expect(Set(focused.nodeIndex.keys) == Set(["users", "orders", "line_items"]))
    }

    @Test("Focused subgraph with isolated table keeps only that table")
    func focusedSubgraphKeepsIsolatedTable() {
        let graph = Self.graph(tableNames: ["users", "orders", "products"], edges: [
            Self.edge(from: "orders", to: "users")
        ])

        let focused = graph.subgraph(focusedOn: "products")

        #expect(focused.nodes.map(\.tableName) == ["products"])
        #expect(focused.edges.isEmpty)
        #expect(Set(focused.nodeIndex.keys) == Set(["products"]))
    }

    @Test("Focused subgraph with unknown table is empty")
    func focusedSubgraphUnknownTableIsEmpty() {
        let graph = Self.graph(tableNames: ["users", "orders"], edges: [
            Self.edge(from: "orders", to: "users")
        ])

        let focused = graph.subgraph(focusedOn: "missing")

        #expect(focused.nodes.isEmpty)
        #expect(focused.edges.isEmpty)
        #expect(focused.nodeIndex.isEmpty)
    }

    private static func graph(tableNames: [String], edges: [EREdge]) -> ERDiagramGraph {
        let nodes = tableNames.map { tableName in
            ERTableNode(id: UUID(), tableName: tableName, columns: [], displayColumns: [])
        }
        let nodeIndex = Dictionary(uniqueKeysWithValues: nodes.map { ($0.tableName, $0.id) })
        return ERDiagramGraph(nodes: nodes, edges: edges, nodeIndex: nodeIndex)
    }

    private static func edge(from fromTable: String, to toTable: String) -> EREdge {
        EREdge(
            id: UUID(),
            fkName: "fk_\(fromTable)_\(toTable)",
            fromTable: fromTable,
            fromColumn: "\(toTable)_id",
            toTable: toTable,
            toColumn: "id",
            cardinality: .manyToOne
        )
    }
}
