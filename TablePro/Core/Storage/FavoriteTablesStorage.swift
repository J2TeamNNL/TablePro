//
//  FavoriteTablesStorage.swift
//  TablePro
//

import Foundation
import os

extension Notification.Name {
    static let favoriteTablesDidChange = Notification.Name("FavoriteTablesDidChange")
}

final class FavoriteTablesStorage {
    static let shared = FavoriteTablesStorage()
    private static let logger = Logger(subsystem: "com.TablePro", category: "FavoriteTablesStorage")

    private let defaults: UserDefaults
    private let syncTracker: SyncChangeTracker
    private let key = "com.TablePro.favoriteTables"
    private var cache: Set<String>?

    init(userDefaults: UserDefaults = .standard, syncTracker: SyncChangeTracker = .shared) {
        self.defaults = userDefaults
        self.syncTracker = syncTracker
    }

    func loadFavorites() -> Set<String> {
        if let cache { return cache }
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) else {
            cache = []
            return []
        }
        cache = decoded
        return decoded
    }

    func isFavorite(_ name: String) -> Bool {
        loadFavorites().contains(name)
    }

    func toggle(_ name: String) {
        if isFavorite(name) {
            removeFavorite(name)
        } else {
            addFavorite(name)
        }
    }

    func addFavorite(_ name: String) {
        var favorites = loadFavorites()
        guard favorites.insert(name).inserted else { return }
        persist(favorites)
        syncTracker.markDirty(.tableFavorite, id: Self.syncId(for: name))
    }

    func addFavoriteWithoutSync(_ name: String) {
        var favorites = loadFavorites()
        guard favorites.insert(name).inserted else { return }
        persist(favorites)
    }

    func removeFavorite(_ name: String) {
        var favorites = loadFavorites()
        guard favorites.remove(name) != nil else { return }
        persist(favorites)
        syncTracker.markDeleted(.tableFavorite, id: Self.syncId(for: name))
    }

    func removeFavoriteWithoutSync(_ name: String) {
        var favorites = loadFavorites()
        guard favorites.remove(name) != nil else { return }
        persist(favorites)
    }

    func removeFavoriteWithoutSync(id: String) {
        var favorites = loadFavorites()
        guard let name = favorites.first(where: { Self.syncId(for: $0) == id }) else { return }
        favorites.remove(name)
        persist(favorites)
    }

    static func syncId(for name: String) -> String {
        name.sha256
    }

    private func persist(_ favorites: Set<String>) {
        cache = favorites
        guard let data = try? JSONEncoder().encode(favorites) else {
            Self.logger.error("Failed to encode favorite tables")
            return
        }
        defaults.set(data, forKey: key)
        NotificationCenter.default.post(name: .favoriteTablesDidChange, object: nil)
    }
}
