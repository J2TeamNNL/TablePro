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

    init() {
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

    func profile(
        for scope: DatabaseScope,
        databaseType: DatabaseType,
        driver: DatabaseDriver
    ) async -> QueryCompletionProfile {
        let base = baseProfile(for: databaseType, serverVersion: driver.serverVersion)
        return await resolve(
            scope: scope,
            databaseType: databaseType,
            serverVersion: driver.serverVersion,
            base: base
        ) {
            try await driver.resolveQueryCompletionProfile(
                databaseTypeId: databaseType.rawValue,
                base: base
            )
        }
    }

    func resolve(
        scope: DatabaseScope,
        databaseType: DatabaseType,
        serverVersion: String?,
        base: QueryCompletionProfile,
        resolver: @escaping () async throws -> QueryCompletionProfile
    ) async -> QueryCompletionProfile {
        let key = CacheKey(scope: scope, databaseType: databaseType, serverVersion: serverVersion)
        if let profile = profiles[key] {
            return profile
        }
        if let task = inFlight[key] {
            return await task.value
        }
        let generation = generations[key, default: 0]
        let task = Task { @MainActor in
            (try? await resolver()) ?? base
        }
        inFlight[key] = task
        let profile = await task.value
        if generations[key, default: 0] == generation {
            inFlight.removeValue(forKey: key)
            profiles[key] = profile
        }
        return profile
    }

    func invalidate(scope: DatabaseScope) {
        revisions[scope, default: 0] &+= 1
        let profileKeys = profiles.keys.filter { $0.scope == scope }
        let taskKeys = inFlight.keys.filter { $0.scope == scope }
        for key in profileKeys {
            generations[key, default: 0] &+= 1
        }
        for key in taskKeys {
            generations[key, default: 0] &+= 1
            inFlight[key]?.cancel()
            inFlight.removeValue(forKey: key)
        }
        profiles = profiles.filter { $0.key.scope != scope }
    }

    func invalidate(connectionId: UUID) {
        let scopes = Set(profiles.keys.map(\.scope) + inFlight.keys.map(\.scope))
            .filter { $0.connectionId == connectionId }
        for scope in scopes {
            revisions[scope, default: 0] &+= 1
        }
        let profileKeys = profiles.keys.filter { $0.scope.connectionId == connectionId }
        let taskKeys = inFlight.keys.filter { $0.scope.connectionId == connectionId }
        for key in profileKeys {
            generations[key, default: 0] &+= 1
        }
        for key in taskKeys {
            generations[key, default: 0] &+= 1
            inFlight[key]?.cancel()
            inFlight.removeValue(forKey: key)
        }
        profiles = profiles.filter { $0.key.scope.connectionId != connectionId }
    }

    private func baseProfile(
        for databaseType: DatabaseType,
        serverVersion: String?
    ) -> QueryCompletionProfile {
        QueryCompletionProfile(
            resolvedDialect: PluginManager.shared.sqlDialect(for: databaseType),
            statementCompletions: PluginManager.shared.statementCompletions(for: databaseType),
            tokenCasingPolicy: .preserveTypedToken,
            revision: [databaseType.rawValue, serverVersion ?? "unknown", "base"].joined(separator: ":")
        )
    }
}
