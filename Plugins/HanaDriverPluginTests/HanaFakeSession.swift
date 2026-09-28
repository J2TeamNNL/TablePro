import Foundation
import TableProPluginKit

final class HanaFakeSession: HanaSession, @unchecked Sendable {
    struct ExecutedStatement: Equatable {
        let sql: String
        let parameters: [HanaBridgeCell]?
        let rowCap: Int
    }

    private let lock = NSLock()
    private var responses: [Result<HanaResultEnvelope, any Error>] = []
    private var connectOutcome: Result<HanaConnectResult, any Error> = .success(
        HanaConnectResult(serverVersion: "4.00.000.00.1234567890", currentSchema: "DBADMIN", connectionId: 200_123)
    )
    private var statementHook: (@Sendable () -> Void)?
    private var executedStatements: [ExecutedStatement] = []
    private var explainedStatements: [String] = []
    private var connectConfigurations: [HanaConnectConfiguration] = []
    private var cancelRunningCalls = 0
    private var disconnectCalls = 0
    private var appliedTimeout: Int?
    private var lostConnection = false

    var hasLostConnection: Bool { lock.withLock { lostConnection } }
    var executed: [ExecutedStatement] { lock.withLock { executedStatements } }
    var explained: [String] { lock.withLock { explainedStatements } }
    var connects: [HanaConnectConfiguration] { lock.withLock { connectConfigurations } }
    var cancelRunningCount: Int { lock.withLock { cancelRunningCalls } }
    var disconnectCount: Int { lock.withLock { disconnectCalls } }
    var timeout: Int? { lock.withLock { appliedTimeout } }

    func respond(_ envelope: HanaResultEnvelope) {
        lock.withLock { responses.append(.success(envelope)) }
    }

    func fail(_ error: any Error) {
        lock.withLock { responses.append(.failure(error)) }
    }

    func connectWith(_ outcome: Result<HanaConnectResult, any Error>) {
        lock.withLock { connectOutcome = outcome }
    }

    func runDuringStatement(_ hook: @escaping @Sendable () -> Void) {
        lock.withLock { statementHook = hook }
    }

    func markConnectionLost() {
        lock.withLock { lostConnection = true }
    }

    func connect(_ configuration: HanaConnectConfiguration) async throws -> HanaConnectResult {
        let outcome = lock.withLock { () -> Result<HanaConnectResult, any Error> in
            connectConfigurations.append(configuration)
            return connectOutcome
        }
        return try outcome.get()
    }

    func disconnect() {
        lock.withLock { disconnectCalls += 1 }
    }

    func ping() async throws {}

    func execute(sql: String, parameters: [HanaBridgeCell]?, rowCap: Int) async throws -> HanaResultEnvelope {
        lock.withLock {
            executedStatements.append(ExecutedStatement(sql: sql, parameters: parameters, rowCap: rowCap))
        }
        return try nextResponse()
    }

    func explain(sql: String) async throws -> HanaResultEnvelope {
        lock.withLock { explainedStatements.append(sql) }
        return try nextResponse()
    }

    func cancelRunning() {
        lock.withLock { cancelRunningCalls += 1 }
    }

    func applyQueryTimeout(seconds: Int) {
        lock.withLock { appliedTimeout = seconds }
    }

    private func nextResponse() throws -> HanaResultEnvelope {
        let (hook, response) = lock.withLock { () -> ((@Sendable () -> Void)?, Result<HanaResultEnvelope, any Error>) in
            let response = responses.isEmpty ? .success(HanaEnvelopes.empty) : responses.removeFirst()
            return (statementHook, response)
        }
        hook?()
        return try response.get()
    }
}

enum HanaEnvelopes {
    static let empty = HanaResultEnvelope(
        columns: [],
        columnTypeNames: [],
        columnClassifications: [],
        rows: [],
        rowsAffected: 0,
        hasResultSet: false,
        executionTime: 0,
        isTruncated: false,
        truncatedLobCount: 0
    )

    static func rows(_ columns: [String], _ rows: [[HanaBridgeCell]]) -> HanaResultEnvelope {
        HanaResultEnvelope(
            columns: columns,
            columnTypeNames: Array(repeating: "NVARCHAR", count: columns.count),
            columnClassifications: Array(repeating: nil, count: columns.count),
            rows: rows,
            rowsAffected: 0,
            hasResultSet: true,
            executionTime: 0.01,
            isTruncated: false,
            truncatedLobCount: 0
        )
    }
}
