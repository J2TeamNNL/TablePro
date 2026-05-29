
import CloudKit
import Foundation
@testable import TablePro
import Testing

@Suite("SyncRecordMapper favorite tables")
struct SyncRecordMapperFavoriteTableTests {
    private let zoneID = CKRecordZone.ID(zoneName: "TestZone", ownerName: CKCurrentUserDefaultName)

    @Test("Table favorite record round trips all fields")
    func tableFavoriteRoundTrip() throws {
        let connId = UUID()
        let entry = FavoriteTablesStorage.FavoriteEntry(connectionId: connId, schema: "public", name: "users")
        let record = SyncRecordMapper.toCKRecord(favoriteEntry: entry, in: zoneID)

        let id = FavoriteTablesStorage.syncId(for: entry)
        #expect(record.recordType == SyncRecordType.tableFavorite.rawValue)
        #expect(record.recordID.recordName == "FavoriteTable_\(id)")
        #expect(record["name"] as? String == "users")
        #expect(record["connectionId"] as? String == connId.uuidString)
        #expect(record["schema"] as? String == "public")

        let decoded = try SyncRecordMapper.favoriteEntry(from: record)
        #expect(decoded == entry)
    }

    @Test("Table favorite without schema round trips correctly")
    func tableFavoriteNoSchemaRoundTrip() throws {
        let connId = UUID()
        let entry = FavoriteTablesStorage.FavoriteEntry(connectionId: connId, schema: nil, name: "orders")
        let record = SyncRecordMapper.toCKRecord(favoriteEntry: entry, in: zoneID)

        #expect(record["schema"] == nil)
        let decoded = try SyncRecordMapper.favoriteEntry(from: record)
        #expect(decoded == entry)
    }

    @Test("Two entries with same name but different connections have distinct sync IDs")
    func distinctSyncIds() {
        let connA = UUID()
        let connB = UUID()
        let entryA = FavoriteTablesStorage.FavoriteEntry(connectionId: connA, schema: nil, name: "users")
        let entryB = FavoriteTablesStorage.FavoriteEntry(connectionId: connB, schema: nil, name: "users")
        #expect(FavoriteTablesStorage.syncId(for: entryA) != FavoriteTablesStorage.syncId(for: entryB))
    }
}
