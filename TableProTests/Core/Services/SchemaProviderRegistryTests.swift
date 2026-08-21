//
//  SchemaProviderRegistryTests.swift
//  TableProTests
//

import Foundation
import TableProPluginKit
import Testing
@testable import TablePro

@Suite("SchemaProviderRegistry")
@MainActor
struct SchemaProviderRegistryTests {
    private func scope(
        _ connectionId: UUID = UUID(),
        database: String = "shop",
        schema: String? = nil
    ) -> DatabaseScope {
        DatabaseScope(connectionId: connectionId, database: database, schema: schema)
    }

    @Test("getOrCreate returns new provider for unknown scope")
    func getOrCreateNewProvider() {
        let registry = SchemaProviderRegistry()
        let scoped = scope()
        let provider = registry.getOrCreate(for: scoped)
        #expect(registry.provider(for: scoped) === provider)
    }

    @Test("getOrCreate returns same provider for same scope")
    func getOrCreateReturnsSameProvider() {
        let registry = SchemaProviderRegistry()
        let scoped = scope()
        #expect(registry.getOrCreate(for: scoped) === registry.getOrCreate(for: scoped))
    }

    @Test("provider(for:) returns nil for unknown scope")
    func providerForUnknownReturnsNil() {
        let registry = SchemaProviderRegistry()
        #expect(registry.provider(for: scope()) == nil)
    }

    @Test("scopes on one connection get their own providers")
    func scopesOnOneConnectionAreIndependent() {
        let registry = SchemaProviderRegistry()
        let connectionId = UUID()
        let sales = scope(connectionId, database: "shop", schema: "sales")
        let audit = scope(connectionId, database: "shop", schema: "audit")
        let warehouse = scope(connectionId, database: "warehouse")
        let salesProvider = registry.getOrCreate(for: sales)
        let auditProvider = registry.getOrCreate(for: audit)
        let warehouseProvider = registry.getOrCreate(for: warehouse)
        #expect(salesProvider !== auditProvider)
        #expect(salesProvider !== warehouseProvider)
        #expect(auditProvider !== warehouseProvider)
    }

    @Test("retain increments refcount, prevents purge")
    func retainPreventsRemoval() {
        let registry = SchemaProviderRegistry()
        let scoped = scope()
        _ = registry.getOrCreate(for: scoped)
        registry.retain(for: scoped.connectionId)
        registry.purgeUnused()
        #expect(registry.provider(for: scoped) != nil)
    }

    @Test("release decrements refcount to zero, schedules deferred removal")
    func releaseSchedulesDeferredRemoval() {
        let registry = SchemaProviderRegistry()
        let scoped = scope()
        _ = registry.getOrCreate(for: scoped)
        registry.retain(for: scoped.connectionId)
        registry.release(for: scoped.connectionId)
        #expect(registry.provider(for: scoped) != nil)
    }

    @Test("clear removes every scope of the connection, its refcount and pending removal")
    func clearRemovesEverything() {
        let registry = SchemaProviderRegistry()
        let connectionId = UUID()
        let shop = scope(connectionId, database: "shop")
        let warehouse = scope(connectionId, database: "warehouse")
        _ = registry.getOrCreate(for: shop)
        _ = registry.getOrCreate(for: warehouse)
        registry.retain(for: connectionId)
        registry.clear(for: connectionId)
        #expect(registry.provider(for: shop) == nil)
        #expect(registry.provider(for: warehouse) == nil)
    }

    @Test("purgeUnused removes orphaned providers with zero refcount and no pending task")
    func purgeRemovesOrphans() {
        let registry = SchemaProviderRegistry()
        let scoped = scope()
        _ = registry.getOrCreate(for: scoped)
        registry.purgeUnused()
        #expect(registry.provider(for: scoped) == nil)
    }

    @Test("purgeUnused does not remove providers with pending removal task")
    func purgeKeepsProvidersWithPendingTask() {
        let registry = SchemaProviderRegistry()
        let scoped = scope()
        _ = registry.getOrCreate(for: scoped)
        registry.retain(for: scoped.connectionId)
        registry.release(for: scoped.connectionId)
        registry.purgeUnused()
        #expect(registry.provider(for: scoped) != nil)
    }

    @Test("multiple connections are independent")
    func multipleConnectionsIndependent() {
        let registry = SchemaProviderRegistry()
        let first = scope()
        let second = scope()
        let firstProvider = registry.getOrCreate(for: first)
        let secondProvider = registry.getOrCreate(for: second)
        #expect(firstProvider !== secondProvider)
        registry.clear(for: first.connectionId)
        #expect(registry.provider(for: first) == nil)
        #expect(registry.provider(for: second) != nil)
    }
}
