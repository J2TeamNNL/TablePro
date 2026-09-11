import Foundation
import TableProPluginKit
import Testing

@Suite("OceanBase hidden primary key")
struct OceanBaseHiddenPrimaryKeyTests {
    @Test("A SHOW INDEX PRIMARY column missing from SHOW COLUMNS is attached as BIGINT PK")
    func attachesHiddenPrimary() {
        let visible = [
            PluginColumnInfo(name: "name", dataType: "VARCHAR(32)", isNullable: true, isPrimaryKey: false)
        ]
        let attached = OceanBaseHiddenPrimaryKey.attaching(
            to: visible,
            primaryIndexColumns: ["__pk_increment"]
        )
        #expect(attached.map(\.name) == ["name", "__pk_increment"])
        let hidden = attached[1]
        #expect(hidden.isPrimaryKey)
        #expect(hidden.dataType == "BIGINT")
        #expect(hidden.identityKind == .always)
        #expect(!hidden.isNullable)
    }

    @Test("A visible primary key is left alone")
    func visiblePrimaryIsUnchanged() {
        let visible = [
            PluginColumnInfo(name: "id", dataType: "INT", isNullable: false, isPrimaryKey: true),
            PluginColumnInfo(name: "name", dataType: "VARCHAR(32)", isNullable: true, isPrimaryKey: false)
        ]
        let attached = OceanBaseHiddenPrimaryKey.attaching(
            to: visible,
            primaryIndexColumns: ["id"]
        )
        #expect(attached.map(\.name) == ["id", "name"])
    }

    @Test("An already-visible hidden name is not duplicated")
    func doesNotDuplicate() {
        let visible = [
            PluginColumnInfo(
                name: "__pk_increment",
                dataType: "BIGINT",
                isNullable: false,
                isPrimaryKey: true
            )
        ]
        let attached = OceanBaseHiddenPrimaryKey.attaching(
            to: visible,
            primaryIndexColumns: ["__pk_increment"]
        )
        #expect(attached.count == 1)
    }
}
