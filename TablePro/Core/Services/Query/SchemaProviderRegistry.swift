//
//  SchemaProviderRegistry.swift
//  TablePro
//
//  Manages shared SQLSchemaProvider instances across connections.
//  Ref-counted with grace period removal to avoid redundant schema loads.
//

import Combine
import Foundation
import os

@MainActor
final class SchemaProviderRegistry {
    nonisolated private static let logger = Logger(subsystem: "com.TablePro", category: "SchemaProviderRegistry")

    static let shared = SchemaProviderRegistry()

    private var providers: [DatabaseScope: SQLSchemaProvider] = [:]
    private var refCounts: [UUID: Int] = [:]
    private var removalTasks: [UUID: Task<Void, Never>] = [:]
    private var cancellables: Set<AnyCancellable> = []
    private let metadataDriverProvider: any ScopedMetadataProviding

    #if DEBUG
    /// Test-only init for `@testable` tests in DEBUG builds; release builds must use `.shared`.
    internal init(metadataDriverProvider: any ScopedMetadataProviding = DatabaseManager.shared) {
        self.metadataDriverProvider = metadataDriverProvider
        subscribeToRefreshSignal()
    }
    #else
    private init(metadataDriverProvider: any ScopedMetadataProviding = DatabaseManager.shared) {
        self.metadataDriverProvider = metadataDriverProvider
        subscribeToRefreshSignal()
    }
    #endif

    private func subscribeToRefreshSignal() {
        AppCommands.shared.refreshData
            .sink { [weak self] request in
                self?.refresh(request: request)
            }
            .store(in: &cancellables)
    }

    func getOrCreate(for connectionId: UUID) -> SQLSchemaProvider {
        guard let scope = metadataDriverProvider.browseScope(for: connectionId) else {
            let fallback = DatabaseScope(connectionId: connectionId, database: "", schema: nil)
            return getOrCreate(for: fallback)
        }
        return getOrCreate(for: scope)
    }

    func provider(for scope: DatabaseScope) -> SQLSchemaProvider? {
        providers[scope]
    }

    func getOrCreate(for scope: DatabaseScope) -> SQLSchemaProvider {
        let connectionId = scope.connectionId
        if let removalTask = removalTasks[connectionId] {
            removalTask.cancel()
            removalTasks.removeValue(forKey: connectionId)
        }
        if let existing = providers[scope] {
            return existing
        }
        let metadataProvider = metadataDriverProvider
        let source = SQLSchemaProvider.ColumnMetadataSource(
            fetchColumns: { table, schema in
                try await metadataProvider.withMetadataDriver(scope: scope) { driver in
                    if let schema {
                        return try await driver.fetchColumns(table: table, schema: schema)
                    }
                    return try await driver.fetchColumns(table: table)
                }
            },
            fetchAllColumns: {
                try await metadataProvider.withMetadataDriver(scope: scope, workload: .bulk) { driver in
                    try await driver.fetchAllColumns()
                }
            },
            fetchSchemaTables: { schema in
                try await metadataProvider.withMetadataDriver(scope: scope) { driver in
                    try await driver.fetchTables(schema: schema)
                }
            },
            sampleFieldPaths: { table, limit in
                try await DatabaseManager.shared.withBrowseMetadataDriver(connectionId: connectionId) { driver in
                    try await driver.sampleFieldPaths(table: table, limit: limit)
                }
            }
        )
        let provider = SQLSchemaProvider(metadataSource: source)
        providers[scope] = provider
        Task {
            try? await metadataDriverProvider.withMetadataDriver(scope: scope) { driver in
                await provider.loadSchema(using: driver)
            }
        }
        return provider
    }

    func prepare(for scope: DatabaseScope) async -> SQLSchemaProvider {
        let provider = getOrCreate(for: scope)
        try? await metadataDriverProvider.withMetadataDriver(scope: scope) { driver in
            await provider.loadSchema(using: driver)
        }
        return provider
    }

    func refresh(request: DataRefreshRequest) {
        let matchingProviders = providers.filter { scope, _ in
            scope.connectionId == request.connectionId && (request.scope == nil || request.scope == scope)
        }
        for (scope, provider) in matchingProviders {
            Task {
                try? await metadataDriverProvider.withMetadataDriver(scope: scope) { driver in
                    await provider.clearColumnCache()
                    await provider.loadSchema(using: driver)
                }
            }
        }
    }

    func retain(for connectionId: UUID) {
        removalTasks[connectionId]?.cancel()
        removalTasks.removeValue(forKey: connectionId)
        refCounts[connectionId, default: 0] += 1
    }

    func release(for connectionId: UUID) {
        guard var count = refCounts[connectionId] else { return }
        count -= 1
        if count <= 0 {
            refCounts.removeValue(forKey: connectionId)
            removalTasks[connectionId] = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self, !Task.isCancelled else { return }
                self.providers = self.providers.filter { $0.key.connectionId != connectionId }
                self.removalTasks.removeValue(forKey: connectionId)
            }
        } else {
            refCounts[connectionId] = count
        }
    }

    func clear(for connectionId: UUID) {
        providers = providers.filter { $0.key.connectionId != connectionId }
        refCounts.removeValue(forKey: connectionId)
        removalTasks[connectionId]?.cancel()
        removalTasks.removeValue(forKey: connectionId)
    }

    func purgeUnused() {
        let orphanedIds = Set(providers.keys.map(\.connectionId)).filter { connectionId in
            let count = refCounts[connectionId] ?? 0
            let hasPendingRemoval = removalTasks[connectionId] != nil
            return count <= 0 && !hasPendingRemoval
        }
        for connectionId in orphanedIds {
            Self.logger.info("Purging orphaned schema provider for connection \(connectionId)")
            providers = providers.filter { $0.key.connectionId != connectionId }
            refCounts.removeValue(forKey: connectionId)
        }
    }
}
