import Foundation
import TableProPluginKit

internal enum OceanBaseHiddenPrimaryKey {
    static func synthesizedColumn(named name: String) -> PluginColumnInfo {
        PluginColumnInfo(
            name: name,
            dataType: "BIGINT",
            isNullable: false,
            isPrimaryKey: true,
            defaultValue: nil,
            extra: "auto_increment",
            identityKind: .always,
            isGenerated: false,
            allowedValues: nil,
            generationExpression: nil,
            generationKind: nil
        )
    }

    static func attaching(
        to columns: [PluginColumnInfo],
        primaryIndexColumns: [String]
    ) -> [PluginColumnInfo] {
        let visible = Set(columns.map(\.name))
        let hidden = OceanBaseSQL.hiddenPrimaryKeyColumns(
            primaryIndexColumns: primaryIndexColumns,
            visibleColumnNames: visible
        )
        guard !hidden.isEmpty else { return columns }
        return columns + hidden.map(synthesizedColumn(named:))
    }
}
