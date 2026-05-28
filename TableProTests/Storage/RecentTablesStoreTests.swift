//
//  RecentTablesStoreTests.swift
//  TableProTests
//

import Foundation
import Testing

@testable import TablePro

@Suite("RecentTablesStore")
@MainActor
struct RecentTablesStoreTests {
    private func makeStore() -> RecentTablesStore {
        RecentTablesStore()
    }

    private func makeTable(_ name: String, schema: String? = nil) -> TableInfo {
        TableInfo(name: name, type: .table, rowCount: nil, schema: schema)
    }

    @Test("Push inserts entry at the front")
    func pushInsertsAtFront() {
        let store = makeStore()
        let conn = UUID()
        store.push(connectionID: conn, database: "db", table: makeTable("a"))
        store.push(connectionID: conn, database: "db", table: makeTable("b"))
        let entries = store.entries(connectionID: conn, database: "db")
        #expect(entries.map(\.name) == ["b", "a"])
    }

    @Test("Push dedupes by table id and bumps to front")
    func pushDedupes() {
        let store = makeStore()
        let conn = UUID()
        store.push(connectionID: conn, database: "db", table: makeTable("a"))
        store.push(connectionID: conn, database: "db", table: makeTable("b"))
        store.push(connectionID: conn, database: "db", table: makeTable("a"))
        let entries = store.entries(connectionID: conn, database: "db")
        #expect(entries.map(\.name) == ["a", "b"])
    }

    @Test("Push caps list at 10 entries")
    func pushCaps() {
        let store = makeStore()
        let conn = UUID()
        for index in 0..<15 {
            store.push(connectionID: conn, database: "db", table: makeTable("t\(index)"))
        }
        let entries = store.entries(connectionID: conn, database: "db")
        #expect(entries.count == store.cappedSize)
        #expect(entries.first?.name == "t14")
        #expect(entries.last?.name == "t5")
    }

    @Test("Entries isolated per (connection, database) key")
    func entriesIsolated() {
        let store = makeStore()
        let connA = UUID()
        let connB = UUID()
        store.push(connectionID: connA, database: "db", table: makeTable("alpha"))
        store.push(connectionID: connB, database: "db", table: makeTable("beta"))
        store.push(connectionID: connA, database: "other", table: makeTable("gamma"))

        #expect(store.entries(connectionID: connA, database: "db").map(\.name) == ["alpha"])
        #expect(store.entries(connectionID: connB, database: "db").map(\.name) == ["beta"])
        #expect(store.entries(connectionID: connA, database: "other").map(\.name) == ["gamma"])
    }

    @Test("Schema-qualified table is distinct from same-name unqualified")
    func schemaDistinct() {
        let store = makeStore()
        let conn = UUID()
        store.push(connectionID: conn, database: "db", table: makeTable("users", schema: "public"))
        store.push(connectionID: conn, database: "db", table: makeTable("users", schema: nil))
        let entries = store.entries(connectionID: conn, database: "db")
        #expect(entries.count == 2)
    }

    @Test("Clear removes all entries for a key")
    func clearKey() {
        let store = makeStore()
        let conn = UUID()
        store.push(connectionID: conn, database: "db", table: makeTable("a"))
        store.push(connectionID: conn, database: "other", table: makeTable("b"))
        store.clear(connectionID: conn, database: "db")
        #expect(store.entries(connectionID: conn, database: "db").isEmpty)
        #expect(store.entries(connectionID: conn, database: "other").map(\.name) == ["b"])
    }

    @Test("Nil database key is distinct from empty-string database")
    func nilDatabaseDistinctFromEmpty() {
        let store = makeStore()
        let conn = UUID()
        store.push(connectionID: conn, database: nil, table: makeTable("sqlite_table"))
        store.push(connectionID: conn, database: "postgres", table: makeTable("pg_table"))
        #expect(store.entries(connectionID: conn, database: nil).map(\.name) == ["sqlite_table"])
        #expect(store.entries(connectionID: conn, database: "postgres").map(\.name) == ["pg_table"])
    }
}
