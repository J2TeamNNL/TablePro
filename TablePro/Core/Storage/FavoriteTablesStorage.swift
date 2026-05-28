
import Foundation
import os

extension Notification.Name {
    static let favoriteTablesDidChange = Notification.Name("FavoriteTablesDidChange")
}

final class FavoriteTablesStorage {
    static let shared = FavoriteTablesStorage()
    private static let logger = Logger(subsystem: "com.TablePro", category: "FavoriteTablesStorage")

    struct FavoriteEntry: Codable, Hashable {
        let connectionId: UUID
        let schema: String?
        let name: String
    }

    private let defaults: UserDefaults
    private let syncTracker: SyncChangeTracker
    private let key = "com.TablePro.favoriteTables"
    private var cache: Set<FavoriteEntry>?
    private let lock = NSLock()

    init(userDefaults: UserDefaults = .standard, syncTracker: SyncChangeTracker = .shared) {
        self.defaults = userDefaults
        self.syncTracker = syncTracker
    }

    func loadFavorites() -> Set<FavoriteEntry> {
        lock.lock()
        defer { lock.unlock() }
        return _loadFavorites()
    }

    func favorites(for connectionId: UUID) -> Set<FavoriteEntry> {
        lock.lock()
        defer { lock.unlock() }
        return _loadFavorites().filter { $0.connectionId == connectionId }
    }

    func isFavorite(name: String, schema: String?, connectionId: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return _loadFavorites().contains(FavoriteEntry(connectionId: connectionId, schema: schema, name: name))
    }

    func toggle(name: String, schema: String?, connectionId: UUID) {
        let entry = FavoriteEntry(connectionId: connectionId, schema: schema, name: name)
        lock.lock()
        var favorites = _loadFavorites()
        let isPresent = favorites.contains(entry)
        lock.unlock()

        if isPresent {
            removeFavorite(name: name, schema: schema, connectionId: connectionId)
        } else {
            addFavorite(name: name, schema: schema, connectionId: connectionId)
        }
    }

    func addFavorite(name: String, schema: String?, connectionId: UUID) {
        let entry = FavoriteEntry(connectionId: connectionId, schema: schema, name: name)
        lock.lock()
        var favorites = _loadFavorites()
        guard favorites.insert(entry).inserted else { lock.unlock(); return }
        _persist(favorites)
        lock.unlock()
        syncTracker.markDirty(.tableFavorite, id: Self.syncId(for: entry))
    }

    func addFavoriteWithoutSync(_ entry: FavoriteEntry) {
        lock.lock()
        var favorites = _loadFavorites()
        guard favorites.insert(entry).inserted else { lock.unlock(); return }
        _persist(favorites)
        lock.unlock()
    }

    func removeFavorite(name: String, schema: String?, connectionId: UUID) {
        let entry = FavoriteEntry(connectionId: connectionId, schema: schema, name: name)
        lock.lock()
        var favorites = _loadFavorites()
        guard favorites.remove(entry) != nil else { lock.unlock(); return }
        _persist(favorites)
        lock.unlock()
        syncTracker.markDeleted(.tableFavorite, id: Self.syncId(for: entry))
    }

    func removeFavoriteWithoutSync(_ entry: FavoriteEntry) {
        lock.lock()
        var favorites = _loadFavorites()
        guard favorites.remove(entry) != nil else { lock.unlock(); return }
        _persist(favorites)
        lock.unlock()
    }

    func removeFavoriteWithoutSync(id: String) {
        lock.lock()
        var favorites = _loadFavorites()
        guard let entry = favorites.first(where: { Self.syncId(for: $0) == id }) else { lock.unlock(); return }
        favorites.remove(entry)
        _persist(favorites)
        lock.unlock()
    }

    static func syncId(for entry: FavoriteEntry) -> String {
        let raw = entry.connectionId.uuidString + "|" + (entry.schema ?? "") + "|" + entry.name
        return raw.sha256
    }

    private func _loadFavorites() -> Set<FavoriteEntry> {
        if let cache { return cache }
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(Set<FavoriteEntry>.self, from: data) else {
            cache = []
            return []
        }
        cache = decoded
        return decoded
    }

    private func _persist(_ favorites: Set<FavoriteEntry>) {
        cache = favorites
        guard let data = try? JSONEncoder().encode(favorites) else {
            Self.logger.error("Failed to encode favorite tables")
            return
        }
        defaults.set(data, forKey: key)
        NotificationCenter.default.post(name: .favoriteTablesDidChange, object: nil)
    }
}
