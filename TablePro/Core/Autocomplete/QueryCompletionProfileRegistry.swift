import Combine
import Foundation
import Observation
import TableProPluginKit

@MainActor
@Observable
final class QueryCompletionProfileRegistry {
    struct CacheKey: Hashable {
        let scope: DatabaseScope
        let databaseType: DatabaseType
        let serverVersion: String?
    }

    static let shared = QueryCompletionProfileRegistry()

    private var profiles: [CacheKey: QueryCompletionProfile] = [:]
    private var inFlight: [CacheKey: Task<QueryCompletionProfile, Never>] = [:]
    private var generations: [CacheKey: Int] = [:]
    private(set) var revisions: [DatabaseScope: Int] = [:]
    @ObservationIgnored private var cancellables: Set<AnyCancellable> = []

    #if DEBUG
    /// Test-only init for `@testable` tests in DEBUG builds; release builds must use `.shared`.
    /// A second instance in shipping code is a second profile cache no `invalidate` call reaches,
    /// plus a second permanent `refreshData` subscription.
    internal init() {
        subscribeToRefreshSignal()
    }
    #else
    private init() {
        subscribeToRefreshSignal()
    }
    #endif

    private func subscribeToRefreshSignal() {
        AppCommands.shared.refreshData
            .sink { [weak self] request in
                guard let self else { return }
                if let scope = request.scope {
                    self.invalidate(scope: scope)
                } else {
                    self.invalidate(connectionId: request.connectionId)
                }
            }
            .store(in: &cancellables)
    }

    func revision(for scope: DatabaseScope) -> Int {
        revisions[scope, default: 0]
    }

    /// The metadata driver is leased inside the resolver rather than around this call, so a
    /// cached profile costs nothing. An engine that cannot pool serves metadata from the
    /// session driver, and leasing that for a profile the cache already holds would queue
    /// behind, and ahead of, the statements the user is running.
    func profile(
        for scope: DatabaseScope,
        databaseType: DatabaseType,
        serverVersion: String?,
        metadataProvider: any ScopedMetadataProviding = DatabaseManager.shared
    ) async -> QueryCompletionProfile {
        let base = baseProfile(for: databaseType, serverVersion: serverVersion)
        return await resolve(
            scope: scope,
            databaseType: databaseType,
            serverVersion: serverVersion,
            base: base
        ) {
            try await metadataProvider.withMetadataDriver(scope: scope) { driver in
                try await driver.resolveQueryCompletionProfile(
                    databaseTypeId: databaseType.rawValue,
                    base: base
                )
            }
        }
    }

    func resolve(
        scope: DatabaseScope,
        databaseType: DatabaseType,
        serverVersion: String?,
        base: QueryCompletionProfile,
        resolver: @Sendable @escaping () async throws -> QueryCompletionProfile
    ) async -> QueryCompletionProfile {
        let key = CacheKey(scope: scope, databaseType: databaseType, serverVersion: serverVersion)
        if let profile = profiles[key] {
            return profile
        }
        let generation = generations[key, default: 0]
        if let task = inFlight[key] {
            let joined = await task.value
            guard generations[key, default: 0] == generation else { return base }
            return joined
        }
        let task = Task {
            (try? await resolver()) ?? base
        }
        inFlight[key] = task
        let profile = await task.value
        guard generations[key, default: 0] == generation else {
            /// An invalidation landed while this was running. The refusal to cache is not enough
            /// on its own: handing the caller the profile the refresh existed to replace would
            /// configure the editor with it. The base is the current answer for everything the
            /// app itself knows, and the revision bump re-runs the resolver behind it.
            return base
        }
        inFlight.removeValue(forKey: key)
        profiles[key] = profile
        return profile
    }

    func invalidate(scope: DatabaseScope) {
        revisions[scope, default: 0] &+= 1
        discardEntries { $0 == scope }
    }

    func invalidate(connectionId: UUID) {
        for scope in cachedScopes(of: connectionId) {
            revisions[scope, default: 0] &+= 1
        }
        discardEntries { $0.connectionId == connectionId }
    }

    /// Teardown, as opposed to invalidation. `revisions` has to stay monotonic while a connection
    /// is open, because `.task(id:)` in the editor keys on it and a value that went backwards
    /// would re-fire the wrong way round; once the session is gone there is nothing to key.
    func clear(connectionId: UUID) {
        discardEntries { $0.connectionId == connectionId }
        for key in Array(generations.keys) where key.scope.connectionId == connectionId {
            generations.removeValue(forKey: key)
        }
        for scope in Array(revisions.keys) where scope.connectionId == connectionId {
            revisions.removeValue(forKey: scope)
        }
    }

    private func cachedScopes(of connectionId: UUID) -> Set<DatabaseScope> {
        Set(profiles.keys.map(\.scope) + inFlight.keys.map(\.scope))
            .filter { $0.connectionId == connectionId }
    }

    /// The generation bump is what fences a resolution that is already running: it completes
    /// against a key whose generation moved, so it discards its own result instead of writing
    /// a profile the refresh was meant to replace.
    private func discardEntries(matching matches: (DatabaseScope) -> Bool) {
        for key in profiles.keys where matches(key.scope) {
            generations[key, default: 0] &+= 1
        }
        for key in Array(inFlight.keys) where matches(key.scope) {
            generations[key, default: 0] &+= 1
            inFlight.removeValue(forKey: key)?.cancel()
        }
        profiles = profiles.filter { !matches($0.key.scope) }
    }

    private func baseProfile(
        for databaseType: DatabaseType,
        serverVersion: String?
    ) -> QueryCompletionProfile {
        QueryCompletionProfile(
            resolvedDialect: PluginManager.shared.sqlDialect(for: databaseType),
            statementCompletions: PluginManager.shared.statementCompletions(for: databaseType),
            revision: [databaseType.rawValue, serverVersion ?? "unknown", "base"].joined(separator: ":")
        )
    }
}
