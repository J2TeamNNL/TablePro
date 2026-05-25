@testable import TablePro
import TableProPluginKit
import Testing

@Suite("Sidebar table ordering")
struct SidebarTableOrderingTests {
    @Test("Favorite tables are pinned while preserving section order")
    func favoritesPinnedWithStableOrder() {
        let tables = ["accounts", "orders", "users", "products"].map {
            TestFixtures.makeTableInfo(name: $0)
        }

        let sorted = SidebarTableOrdering.sortedByFavorite(
            tables,
            favoriteTables: ["users", "orders"]
        )

        #expect(sorted.map(\.name) == ["orders", "users", "accounts", "products"])
    }

    @Test("Table order is unchanged when there are no favorites")
    func unchangedWithoutFavorites() {
        let tables = ["accounts", "orders", "users"].map {
            TestFixtures.makeTableInfo(name: $0)
        }

        let sorted = SidebarTableOrdering.sortedByFavorite(tables, favoriteTables: [])

        #expect(sorted.map(\.name) == ["accounts", "orders", "users"])
    }
}
