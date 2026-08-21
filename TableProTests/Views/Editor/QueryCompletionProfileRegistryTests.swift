import Foundation
@testable import TablePro
import TableProPluginKit
import Testing

@MainActor
private final class LeaseCountingMetadataProvider: ScopedMetadataProviding {
    private let driver: MockDatabaseDriver
    private let scope: DatabaseScope
    private(set) var leaseCount = 0

    init(driver: MockDatabaseDriver, browseScope: DatabaseScope) {
        self.driver = driver
        self.scope = browseScope
    }

    func withMetadataDriver<T: Sendable>(
        scope: DatabaseScope,
        workload: MetadataConnectionPool.Workload,
        _ body: @Sendable @escaping (DatabaseDriver) async throws -> T
    ) async throws -> T {
        leaseCount += 1
        return try await body(driver)
    }

    func browseScope(for connectionId: UUID) -> DatabaseScope? { scope }
}

@Suite("Query completion profile registry")
@MainActor
struct QueryCompletionProfileRegistryTests {
    actor Counter {
        private(set) var value = 0

        func increment() {
            value += 1
        }
    }

    nonisolated private static func base(revision: String = "base") -> QueryCompletionProfile {
        QueryCompletionProfile(
            resolvedDialect: nil,
            statementCompletions: [CompletionEntry(label: "SELECT", insertText: "SELECT")],
            tokenCasingPolicy: .preserveTypedToken,
            revision: revision
        )
    }

    @Test("a cached profile is served without leasing a metadata driver")
    func cachedProfileSkipsTheDriverLease() async {
        let registry = QueryCompletionProfileRegistry()
        let connectionId = UUID()
        let scope = DatabaseScope(connectionId: connectionId, database: "shop", schema: nil)
        let metadataProvider = LeaseCountingMetadataProvider(
            driver: MockDatabaseDriver(),
            browseScope: scope
        )

        _ = await registry.profile(
            for: scope,
            databaseType: .postgresql,
            serverVersion: "15.2",
            metadataProvider: metadataProvider
        )
        _ = await registry.profile(
            for: scope,
            databaseType: .postgresql,
            serverVersion: "15.2",
            metadataProvider: metadataProvider
        )

        #expect(metadataProvider.leaseCount == 1)

        registry.invalidate(scope: scope)
        _ = await registry.profile(
            for: scope,
            databaseType: .postgresql,
            serverVersion: "15.2",
            metadataProvider: metadataProvider
        )

        #expect(metadataProvider.leaseCount == 2)
    }

    @Test("cache keys include scope, database type, and server version")
    func cacheKeyIncludesEveryRuntimeDimension() async {
        let registry = QueryCompletionProfileRegistry()
        let connectionId = UUID()
        let firstScope = DatabaseScope(connectionId: connectionId, database: "first", schema: "public")
        let secondScope = DatabaseScope(connectionId: connectionId, database: "second", schema: "public")
        let resolutions = Counter()

        _ = await registry.resolve(
            scope: firstScope,
            databaseType: .postgresql,
            serverVersion: "15.2",
            base: Self.base()
        ) {
            await resolutions.increment()
            return Self.base(revision: "first")
        }
        _ = await registry.resolve(
            scope: firstScope,
            databaseType: .postgresql,
            serverVersion: "15.2",
            base: Self.base()
        ) {
            await resolutions.increment()
            return Self.base(revision: "cached")
        }
        _ = await registry.resolve(
            scope: secondScope,
            databaseType: .postgresql,
            serverVersion: "15.2",
            base: Self.base()
        ) {
            await resolutions.increment()
            return Self.base(revision: "second")
        }
        _ = await registry.resolve(
            scope: firstScope,
            databaseType: .cockroachdb,
            serverVersion: "15.2",
            base: Self.base()
        ) {
            await resolutions.increment()
            return Self.base(revision: "type")
        }
        _ = await registry.resolve(
            scope: firstScope,
            databaseType: .postgresql,
            serverVersion: "16.1",
            base: Self.base()
        ) {
            await resolutions.increment()
            return Self.base(revision: "version")
        }

        #expect(await resolutions.value == 4)
    }

    @Test("resolution errors return and cache the conservative base profile")
    func resolutionFailureReturnsBase() async {
        let registry = QueryCompletionProfileRegistry()
        let scope = DatabaseScope(connectionId: UUID(), database: "shop", schema: nil)
        let conservative = Self.base(revision: "unknown-base")

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
        let resolutions = Counter()

        async let first = registry.resolve(
            scope: scope,
            databaseType: .mysql,
            serverVersion: "8.0",
            base: Self.base()
        ) {
            await resolutions.increment()
            await Task.yield()
            return Self.base(revision: "resolved")
        }
        async let second = registry.resolve(
            scope: scope,
            databaseType: .mysql,
            serverVersion: "8.0",
            base: Self.base()
        ) {
            await resolutions.increment()
            return Self.base(revision: "duplicate")
        }

        let revisions = await [first.revision, second.revision]
        #expect(await resolutions.value == 1)
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
            base: Self.base()
        ) {
            try? await Task.sleep(nanoseconds: 10_000_000)
            return Self.base(revision: "old")
        }
        await Task.yield()
        registry.invalidate(scope: scope)
        let current = await registry.resolve(
            scope: scope,
            databaseType: .mysql,
            serverVersion: "8.0",
            base: Self.base()
        ) {
            Self.base(revision: "current")
        }
        _ = await old
        let cached = await registry.resolve(
            scope: scope,
            databaseType: .mysql,
            serverVersion: "8.0",
            base: Self.base()
        ) {
            Self.base(revision: "unexpected")
        }

        #expect(current.revision == "current")
        #expect(cached.revision == "current")
    }
}
