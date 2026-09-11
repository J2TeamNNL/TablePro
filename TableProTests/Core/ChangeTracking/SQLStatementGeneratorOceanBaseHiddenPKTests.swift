import TableProPluginKit
@testable import TablePro
import Testing

@Suite("SQL Statement Generator OceanBase hidden PK")
struct SQLStatementGeneratorOceanBaseHiddenPKTests {
    private func makeGenerator(
        columns: [String],
        primaryKeyColumns: [String],
        generatedColumns: Set<String> = []
    ) throws -> SQLStatementGenerator {
        try SQLStatementGenerator(
            tableName: "orders",
            columns: columns,
            primaryKeyColumns: primaryKeyColumns,
            databaseType: .oceanbase,
            generatedColumns: generatedColumns,
            dialect: nil
        )
    }

    @Test("An UPDATE is skipped when the hidden PK is named but not in the result columns")
    func missingHiddenKeySkipsUpdate() throws {
        let generator = try makeGenerator(
            columns: ["name", "amount"],
            primaryKeyColumns: ["__pk_increment"]
        )
        let change = RowChange(
            rowIndex: 0,
            type: .update,
            cellChanges: [
                CellChange(columnIndex: 0, columnName: "name", oldValue: "old", newValue: "new")
            ],
            originalRow: ["old", "1"].map(PluginCellValue.fromOptional)
        )
        #expect(generator.generateUpdateSQL(for: change) == nil)
    }

    @Test("An UPDATE matches on the hidden PK once it is a result column")
    func hiddenKeyAnchorsUpdate() throws {
        let generator = try makeGenerator(
            columns: ["name", "amount", "__pk_increment"],
            primaryKeyColumns: ["__pk_increment"],
            generatedColumns: ["__pk_increment"]
        )
        let change = RowChange(
            rowIndex: 0,
            type: .update,
            cellChanges: [
                CellChange(columnIndex: 0, columnName: "name", oldValue: "old", newValue: "new")
            ],
            originalRow: ["old", "1", "42"].map(PluginCellValue.fromOptional)
        )
        let statement = try #require(generator.generateUpdateSQL(for: change))
        #expect(statement.sql == "UPDATE `orders` SET `name` = ? WHERE `__pk_increment` = ?")
        #expect(statement.parameters.count == 2)
        #expect(statement.parameters[0] as? String == "new")
        #expect(statement.parameters[1] as? String == "42")
        #expect(!statement.sql.contains("SET `__pk_increment`"))
    }
}
