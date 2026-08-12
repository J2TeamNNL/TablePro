import Foundation
@testable import TablePro
import TableProPluginKit
import Testing

@Suite("Query completion profile registry")
@MainActor
struct QueryCompletionProfileRegistryTests {
    private func base(revision: String = "base") -> QueryCompletionProfile {
        QueryCompletionProfile(
            resolvedDialect: nil,
            statementCompletions: [CompletionEntry(label: "SELECT", insertText: "SELECT")],
            tokenCasingPolicy: .preserveTypedToken,
            revision: revision
        )
    }

    @Test("cache keys include scope, database type, and server version")
    func cacheKeyIncludesEveryRuntimeDimension() async {
        let registry = QueryCompletionProfileRegistry()
        let connectionId = UUID()
        let firstScope = DatabaseScope(connectionId: connectionId, database: "first", schema: "public")
        let secondScope = DatabaseScope(connectionId: connectionId, database: "second", schema: "public")
        var resolutions = 0

        _ = await registry.resolve(
            scope: firstScope,
            databaseType: .postgresql,
            serverVersion: "15.2",
            base: base()
        ) {
            resolutions += 1
            return base(revision: "first")
        }
        _ = await registry.resolve(
            scope: firstScope,
            databaseType: .postgresql,
            serverVersion: "15.2",
            base: base()
        ) {
            resolutions += 1
            return base(revision: "cached")
        }
        _ = await registry.resolve(
            scope: secondScope,
            databaseType: .postgresql,
            serverVersion: "15.2",
            base: base()
        ) {
            resolutions += 1
            return base(revision: "second")
        }
        _ = await registry.resolve(
            scope: firstScope,
            databaseType: .cockroachdb,
            serverVersion: "15.2",
            base: base()
        ) {
            resolutions += 1
            return base(revision: "type")
        }
        _ = await registry.resolve(
            scope: firstScope,
            databaseType: .postgresql,
            serverVersion: "16.1",
            base: base()
        ) {
            resolutions += 1
            return base(revision: "version")
        }

        #expect(resolutions == 4)
    }

    @Test("resolution errors return and cache the conservative base profile")
    func resolutionFailureReturnsBase() async {
        let registry = QueryCompletionProfileRegistry()
        let scope = DatabaseScope(connectionId: UUID(), database: "shop", schema: nil)
        let conservative = base(revision: "unknown-base")

        let resolved = await registry.resolve(
            scope: scope,
            databaseType: .mysql,
            serverVersion: nil,
            base: conservative
        ) {
            throw DatabaseError.connectionFailed("catalog denied")
        }

        #expect(resolved.revision == "unknown-base")
        #expect(resolved.statementCompletions.map(\.label) == ["SELECT"])
    }

    @Test("concurrent requests for one key join one resolution")
    func concurrentRequestsJoinOneResolution() async {
        let registry = QueryCompletionProfileRegistry()
        let scope = DatabaseScope(connectionId: UUID(), database: "shop", schema: nil)
        var resolutions = 0

        async let first = registry.resolve(
            scope: scope,
            databaseType: .mysql,
            serverVersion: "8.0",
            base: base()
        ) {
            resolutions += 1
            await Task.yield()
            return base(revision: "resolved")
        }
        async let second = registry.resolve(
            scope: scope,
            databaseType: .mysql,
            serverVersion: "8.0",
            base: base()
        ) {
            resolutions += 1
            return base(revision: "duplicate")
        }

        let revisions = await [first.revision, second.revision]
        #expect(resolutions == 1)
        #expect(revisions == ["resolved", "resolved"])
    }

    @Test("invalidation prevents an old resolution from replacing the next generation")
    func invalidationFencesOldResolution() async {
        let registry = QueryCompletionProfileRegistry()
        let scope = DatabaseScope(connectionId: UUID(), database: "shop", schema: nil)

        async let old = registry.resolve(
            scope: scope,
            databaseType: .mysql,
            serverVersion: "8.0",
            base: base()
        ) {
            try? await Task.sleep(nanoseconds: 10_000_000)
            return base(revision: "old")
        }
        await Task.yield()
        registry.invalidate(scope: scope)
        let current = await registry.resolve(
            scope: scope,
            databaseType: .mysql,
            serverVersion: "8.0",
            base: base()
        ) {
            base(revision: "current")
        }
        _ = await old
        let cached = await registry.resolve(
            scope: scope,
            databaseType: .mysql,
            serverVersion: "8.0",
            base: base()
        ) {
            base(revision: "unexpected")
        }

        #expect(current.revision == "current")
        #expect(cached.revision == "current")
    }
}
