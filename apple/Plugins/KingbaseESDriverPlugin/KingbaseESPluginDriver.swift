import Foundation
import os
import TableProPluginKit

final class KingbaseESPluginDriver: PostgreSQLPluginDriver, @unchecked Sendable {
    private let oracleMode = OSAllocatedUnfairLock(initialState: false)
    private static let modeFeatures: SQLLexicalFeatures = [
        .alternativeQuoting, .plsqlBlocks, .slashLineTerminators, .dollarAndHashInIdentifiers
    ]

    override var sessionLexicalState: PluginSessionLexicalState? {
        let inherited = super.sessionLexicalState
        let enabled = oracleMode.withLock { $0 } ? Self.modeFeatures : []
        return PluginSessionLexicalState(
            determined: (inherited?.determined ?? []).union(Self.modeFeatures),
            enabled: (inherited?.enabled ?? []).union(enabled)
        )
    }

    override func connect() async throws {
        try await super.connect()
        do {
            let result = try await execute(query: "SELECT current_setting('database_mode')")
            let mode = result.rows.first?.first?.asText?.lowercased()
            guard mode == "pg" || mode == "oracle" else {
                throw LibPQPluginError(
                    message: String(localized: "This KingbaseES compatibility mode is not supported. Use PostgreSQL or Oracle mode."),
                    sqlState: nil, detail: nil
                )
            }
            oracleMode.withLock { $0 = mode == "oracle" }
        } catch {
            await disconnect()
            throw error
        }
    }
}
