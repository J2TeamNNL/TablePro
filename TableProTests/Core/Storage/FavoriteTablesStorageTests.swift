//
//  FavoriteTablesStorageTests.swift
//  TableProTests
//

import Foundation
@testable import TablePro
import Testing

@Suite("FavoriteTablesStorage")
struct FavoriteTablesStorageTests {
    private func makeStorage() throws -> (FavoriteTablesStorage, SyncMetadataStorage) {
        let favoritesSuite = "FavoriteTablesStorageTests.favorites.\(UUID().uuidString)"
        let syncSuite = "FavoriteTablesStorageTests.sync.\(UUID().uuidString)"
        let favoritesDefaults = try #require(UserDefaults(suiteName: favoritesSuite))
        let syncDefaults = try #require(UserDefaults(suiteName: syncSuite))
        favoritesDefaults.removePersistentDomain(forName: favoritesSuite)
        syncDefaults.removePersistentDomain(forName: syncSuite)

        let metadata = SyncMetadataStorage(userDefaults: syncDefaults)
        let tracker = SyncChangeTracker(metadataStorage: metadata)
        let storage = FavoriteTablesStorage(userDefaults: favoritesDefaults, syncTracker: tracker)
        return (storage, metadata)
    }

    @Test("Add favorite marks stable sync ID dirty")
    func addMarksDirty() throws {
        let (storage, metadata) = try makeStorage()
        storage.addFavorite("users")

        let id = FavoriteTablesStorage.syncId(for: "users")
        #expect(storage.loadFavorites() == ["users"])
        #expect(metadata.dirtyIds(for: .tableFavorite) == [id])
    }

    @Test("Remove favorite creates sync tombstone")
    func removeCreatesTombstone() throws {
        let (storage, metadata) = try makeStorage()
        storage.addFavorite("users")
        storage.removeFavorite("users")

        let id = FavoriteTablesStorage.syncId(for: "users")
        #expect(storage.loadFavorites().isEmpty)
        #expect(metadata.dirtyIds(for: .tableFavorite).isEmpty)
        #expect(metadata.tombstones(for: .tableFavorite).contains { $0.id == id })
    }

    @Test("Remote apply helpers do not track local sync changes")
    func withoutSyncDoesNotTrackChanges() throws {
        let (storage, metadata) = try makeStorage()
        storage.addFavoriteWithoutSync("orders")
        storage.removeFavoriteWithoutSync("orders")

        #expect(storage.loadFavorites().isEmpty)
        #expect(metadata.dirtyIds(for: .tableFavorite).isEmpty)
        #expect(metadata.tombstones(for: .tableFavorite).isEmpty)
    }
}
