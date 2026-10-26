import Testing

@testable import TableProMySQLCore

struct MySQLRoutineSignaturesTests {
    @Test("Signatures distinguish routine kind and schema, even when names match")
    func identityIncludesSchemaAndKind() {
        let signatures = MySQLRoutineSignatures(rows: [
            ["app", "same", "PROCEDURE", "IN x int(11), OUT y varchar(255)"],
            ["app", "same", "FUNCTION", "IN value varchar(12)"],
            ["other", "same", "PROCEDURE", "IN other bigint(20)"]
        ])

        #expect(signatures.parameterList(schema: "app", name: "same", kind: "PROCEDURE")
            == "IN x int(11), OUT y varchar(255)")
        #expect(signatures.parameterList(schema: "app", name: "same", kind: "function") == "IN value varchar(12)")
        #expect(signatures.parameterList(schema: "other", name: "same", kind: "PROCEDURE") == "IN other bigint(20)")
    }

    @Test("A routine with no parameter rows keeps an empty argument list")
    func missingParametersAreEmpty() {
        let signatures = MySQLRoutineSignatures(rows: [["app", "with_args", "PROCEDURE", "IN x int(11)"]])
        #expect(signatures.parameterList(schema: "app", name: "no_args", kind: "PROCEDURE").isEmpty)
        #expect(signatures.parameterList(schema: "app", name: "with_args", kind: "FUNCTION").isEmpty)
    }

    @Test("Incomplete catalog rows cannot attach a signature to another routine")
    func incompleteRowsAreIgnored() {
        let signatures = MySQLRoutineSignatures(rows: [
            [], ["app"], [nil, "same", "PROCEDURE", "wrong"],
            ["app", nil, "PROCEDURE", "wrong"], ["app", "same", nil, "wrong"],
            ["app", "same", "PROCEDURE", nil], ["app", "valid", "procedure", "IN x int(11)"]
        ])
        #expect(signatures.parameterList(schema: "app", name: "same", kind: "PROCEDURE").isEmpty)
        #expect(signatures.parameterList(schema: "app", name: "valid", kind: "PROCEDURE") == "IN x int(11)")
    }
}
