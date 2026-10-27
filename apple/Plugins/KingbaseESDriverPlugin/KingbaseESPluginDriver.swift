import Foundation
import os
import TableProPluginKit

final class KingbaseESPluginDriver: PostgreSQLPluginDriver, @unchecked Sendable {
    private let mode = OSAllocatedUnfairLock(initialState: KingbaseESCompatibilityMode.postgreSQL)

    override var sessionLexicalState: PluginSessionLexicalState? {
        guard let inherited = super.sessionLexicalState else { return nil }
        let modeFeatures = mode.withLock { $0 }.lexicalFeatures
        return PluginSessionLexicalState(
            determined: inherited.determined.union(KingbaseESCompatibilityMode.lexicalFeaturesItDecides),
            enabled: inherited.enabled.union(modeFeatures)
        )
    }

    override func connect() async throws {
        try await super.connect()
        do {
            let result = try await execute(query: KingbaseESCompatibilityMode.probeQuery)
            let detected = try KingbaseESCompatibilityMode(setting: result.rows.first?.first?.asText)
            mode.withLock { $0 = detected }
        } catch {
            disconnect()
            throw error
        }
    }
}
