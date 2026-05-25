//
//  SyncRecordMapperFavoriteTableTests.swift
//  TableProTests
//

import CloudKit
import Foundation
@testable import TablePro
import Testing

@Suite("SyncRecordMapper favorite tables")
struct SyncRecordMapperFavoriteTableTests {
    @Test("Table favorite record round trips table name")
    func tableFavoriteRoundTrip() throws {
        let zoneID = CKRecordZone.ID(zoneName: "TestZone", ownerName: CKCurrentUserDefaultName)
        let record = SyncRecordMapper.toCKRecord(favoriteTableName: "users", in: zoneID)

        let id = FavoriteTablesStorage.syncId(for: "users")
        #expect(record.recordType == SyncRecordType.tableFavorite.rawValue)
        #expect(record.recordID.recordName == "FavoriteTable_\(id)")
        #expect(record["favoriteTableId"] as? String == id)
        #expect(try SyncRecordMapper.favoriteTableName(from: record) == "users")
    }
}
