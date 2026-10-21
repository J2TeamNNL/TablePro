//
//  AppleIntelligenceTests.swift
//  TableProTests
//

import Foundation
@testable import TablePro
import Testing

struct OnDeviceFitTests {
    private let small = OnDeviceRequest(instructions: "i", prompt: "small")
    private let large = OnDeviceRequest(instructions: "i", prompt: "large")

    private func model(context: Int = 4_096) -> FakeOnDeviceModel {
        FakeOnDeviceModel(contextSize: context) { $0.prompt == "large" ? 3_500 : 900 }
    }

    @Test("The first candidate that leaves room for the reply wins, and the reply gets the rest")
    func firstFittingCandidate() async {
        let fit = await model().fit([large, small], reservingForReply: 1_024)
        #expect(fit == .fits(index: 1, maximumResponseTokens: 4_096 - OnDeviceTokenBudget.transcriptMargin - 900))
    }

    @Test("A candidate that fits stops the measuring")
    func stopsAtFirstFit() async {
        let fake = model()
        _ = await fake.fit([small, large], reservingForReply: 1_024)
        #expect(fake.countedRequests == [small])
    }

    @Test("Nothing that leaves room for the reply is too large, so nothing is generated")
    func tooLarge() async {
        let fake = model(context: 1_500)
        let fit = await fake.fit([large, small], reservingForReply: 1_024)
        #expect(fit == .tooLarge)
        #expect(fake.streamedRequests.isEmpty)
    }

    @Test("A reply that would only fit by eating the transcript margin does not fit")
    func marginCounts() async {
        let fake = FakeOnDeviceModel(contextSize: 2_000) { _ in 2_000 - 1_024 - OnDeviceTokenBudget.transcriptMargin + 1 }
        #expect(await fake.fit([small], reservingForReply: 1_024) == .tooLarge)
    }

    @Test("The estimate rounds up and adds the session's overhead")
    func estimate() {
        let request = OnDeviceRequest(instructions: "abc", prompt: "de")
        #expect(OnDeviceTokenBudget.estimatedTokens(in: request) == 3 + OnDeviceTokenBudget.estimateOverhead)
    }
}

struct AppleIntelligenceAvailabilityTests {
    @Test("Every reason the model is unavailable explains itself", arguments: [
        AppleIntelligenceAvailability.Reason.requiresNewerMacOS,
        .deviceNotEligible,
        .appleIntelligenceNotEnabled,
        .modelNotReady,
        .unknown
    ])
    func unavailableExplains(reason: AppleIntelligenceAvailability.Reason) {
        let availability = AppleIntelligenceAvailability.unavailable(reason)
        #expect(!availability.isAvailable)
        #expect(availability.unavailableExplanation?.isEmpty == false)
    }

    @Test("An available model has nothing to explain")
    func availableExplainsNothing() {
        #expect(AppleIntelligenceAvailability.available.isAvailable)
        #expect(AppleIntelligenceAvailability.available.unavailableExplanation == nil)
    }
}

struct QueryContextUsedColumnsTests {
    private func snapshot() -> QueryContextSnapshot {
        let orders = QueryContextTableStructure(
            columns: [
                QueryContextColumn(name: "id", dataType: "bigint", isNullable: false, isPrimaryKey: true),
                QueryContextColumn(name: "customer_id", dataType: "bigint", isNullable: false, isPrimaryKey: false),
                QueryContextColumn(name: "Total", dataType: "numeric", isNullable: false, isPrimaryKey: false),
                QueryContextColumn(name: "notes", dataType: "text", isNullable: true, isPrimaryKey: false)
            ],
            indexes: [
                QueryContextIndex(name: "orders_pkey", columns: ["id"], isUnique: true, isPrimary: true),
                QueryContextIndex(name: "orders_customer_idx", columns: ["customer_id"], isUnique: false, isPrimary: false)
            ],
            foreignKeys: [
                QueryContextForeignKey(name: "fk_customer", columns: ["customer_id"], referencedTable: "customers", referencedColumns: ["id"])
            ],
            approximateRowCount: 1_000
        )
        return QueryContextSnapshot(
            engineName: "PostgreSQL",
            tables: [
                QueryContextTable(name: "orders", schema: "public", kind: .table, content: .described(orders)),
                QueryContextTable(name: "audit", schema: "public", kind: .table, content: .unavailable(reason: "denied"))
            ]
        )
    }

    @Test("Only the columns the statement names stay, matched without case, and the keys and indexes stay whole")
    func keepsUsedColumns() throws {
        let trimmed = snapshot().keepingColumns(usedBy: "SELECT customer_id, total FROM orders WHERE customer_id = 7")
        guard case .described(let orders) = try #require(trimmed.tables.first).content else {
            Issue.record("orders lost its structure")
            return
        }
        #expect(orders.columns.map(\.name) == ["customer_id", "Total"])
        #expect(orders.omittedColumnCount == 2)
        #expect(orders.indexes.map(\.name) == ["orders_pkey", "orders_customer_idx"])
        #expect(orders.foreignKeys.map(\.name) == ["fk_customer"])
        #expect(orders.approximateRowCount == 1_000)
        #expect(trimmed.tables.last?.content == .unavailable(reason: "denied"))
    }

    @Test("The trimmed table says columns were left out rather than that it has none")
    func rendersOmittedColumns() {
        let some = QueryContextRenderer.render(snapshot().keepingColumns(usedBy: "SELECT total FROM orders"))
        #expect(some.contains("| Total |"))
        #expect(!some.contains("| notes |"))
        #expect(some.contains("… and 3 more columns not listed."))

        let none = QueryContextRenderer.render(snapshot().keepingColumns(usedBy: "SELECT count(*) FROM orders"))
        #expect(none.contains("None of its 4 columns are named in the statement"))
        #expect(!none.contains("No columns reported."))
    }

    @Test("A statement that names every column keeps the snapshot as it was")
    func everyColumnUsed() {
        let full = snapshot()
        let trimmed = full.keepingColumns(usedBy: "SELECT id, customer_id, total, notes FROM orders")
        #expect(trimmed == full)
    }
}
