import CHana
import Foundation
import os

final class HanaConnection: HanaSession, @unchecked Sendable {
    private enum Target {
        case connecting(UInt64)
        case connected
    }

    private struct State {
        var session: UInt64 = 0
        var isAdopted = false
        var epoch: UInt64 = 0
        var lastOperation: UInt64 = 0
        var queryTimeoutSeconds = 0
        var hasLostConnection = false
    }

    private static let logger = Logger(subsystem: "com.TablePro", category: "HanaConnection")

    private let queue = DispatchQueue(label: "com.TablePro.hana.connection", qos: .userInitiated)
    private let stateLock = NSLock()
    private var state = State()

    deinit {
        Self.close(state.session)
    }

    var hasLostConnection: Bool {
        stateLock.withLock { state.hasLostConnection }
    }

    func connect(_ configuration: HanaConnectConfiguration) async throws -> HanaConnectResult {
        let configurationJSON = try JSONEncoder().encode(configuration)
        let attempt = beginAttempt()
        let session = try Self.open(configurationJSON)
        guard claim(session, attempt: attempt) else {
            Self.close(session)
            throw HanaBridgeFailure.closed
        }
        let result: HanaConnectResult
        do {
            result = try await perform(.connecting(session)) { session, operation in
                var rawResult: UnsafeMutablePointer<CChar>?
                var rawError: UnsafeMutablePointer<CChar>?
                guard tp_hana_connect(session, operation, &rawResult, &rawError) else {
                    Self.release(rawResult)
                    throw Self.failure(consuming: rawError)
                }
                Self.release(rawError)
                return try Self.decode(HanaConnectResult.self, consuming: rawResult)
            }
        } catch {
            abandon(session)
            throw error
        }
        guard adopt(session, attempt: attempt) else {
            abandon(session)
            throw HanaBridgeFailure.closed
        }
        Self.logger.debug("SAP HANA session connected as connection \(result.connectionId)")
        return result
    }

    func disconnect() {
        let session = stateLock.withLock { () -> UInt64 in
            let current = state.session
            state.session = 0
            state.isAdopted = false
            state.hasLostConnection = false
            state.epoch &+= 1
            return current
        }
        Self.close(session)
    }

    func ping() async throws {
        try await perform(.connected) { session, operation in
            var rawError: UnsafeMutablePointer<CChar>?
            guard tp_hana_ping(session, operation, &rawError) else {
                throw Self.failure(consuming: rawError)
            }
            Self.release(rawError)
        }
    }

    func execute(sql: String, parameters: [HanaBridgeCell]?, rowCap: Int) async throws -> HanaResultEnvelope {
        let request = HanaExecuteRequest(
            sql: sql,
            parameters: parameters,
            rowCap: rowCap,
            timeoutSeconds: queryTimeoutSeconds
        )
        let requestJSON = try JSONEncoder().encode(request)
        return try await perform(.connected) { session, operation in
            var rawError: UnsafeMutablePointer<CChar>?
            let rawResult = requestJSON.withUnsafeBytes { bytes in
                tp_hana_execute(
                    session,
                    operation,
                    bytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    bytes.count,
                    &rawError
                )
            }
            return try Self.envelope(consuming: rawResult, error: rawError)
        }
    }

    func explain(sql: String) async throws -> HanaResultEnvelope {
        let requestJSON = try JSONEncoder().encode(HanaExplainRequest(sql: sql, timeoutSeconds: queryTimeoutSeconds))
        return try await perform(.connected) { session, operation in
            var rawError: UnsafeMutablePointer<CChar>?
            let rawResult = requestJSON.withUnsafeBytes { bytes in
                tp_hana_explain(
                    session,
                    operation,
                    bytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    bytes.count,
                    &rawError
                )
            }
            return try Self.envelope(consuming: rawResult, error: rawError)
        }
    }

    func cancelRunning() {
        let session = stateLock.withLock { state.session }
        guard session != 0 else { return }
        Self.cancel(HanaOperationTicket(session: session, operation: 0))
    }

    func applyQueryTimeout(seconds: Int) {
        stateLock.withLock { state.queryTimeoutSeconds = max(0, seconds) }
    }

    private var queryTimeoutSeconds: Int {
        stateLock.withLock { state.queryTimeoutSeconds }
    }

    private func beginAttempt() -> UInt64 {
        let (previous, attempt) = stateLock.withLock { () -> (UInt64, UInt64) in
            let current = state.session
            state.session = 0
            state.isAdopted = false
            state.hasLostConnection = false
            state.epoch &+= 1
            return (current, state.epoch)
        }
        Self.close(previous)
        return attempt
    }

    private func claim(_ session: UInt64, attempt: UInt64) -> Bool {
        stateLock.withLock {
            guard state.epoch == attempt, state.session == 0 else { return false }
            state.session = session
            state.isAdopted = false
            return true
        }
    }

    private func adopt(_ session: UInt64, attempt: UInt64) -> Bool {
        stateLock.withLock {
            guard state.epoch == attempt, state.session == session else { return false }
            state.isAdopted = true
            return true
        }
    }

    private func abandon(_ session: UInt64) {
        stateLock.withLock {
            guard state.session == session else { return }
            state.session = 0
            state.isAdopted = false
        }
        Self.close(session)
    }

    private func perform<T: Sendable>(
        _ target: Target,
        _ call: @escaping @Sendable (_ session: UInt64, _ operation: UInt64) throws -> T
    ) async throws -> T {
        let slot = HanaOperationSlot()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, any Error>) in
                enqueue(target, slot: slot, continuation: continuation, call: call)
            }
        } onCancel: {
            guard let ticket = slot.cancel() else { return }
            Self.cancel(ticket)
        }
    }

    private func enqueue<T: Sendable>(
        _ target: Target,
        slot: HanaOperationSlot,
        continuation: CheckedContinuation<T, any Error>,
        call: @escaping @Sendable (_ session: UInt64, _ operation: UInt64) throws -> T
    ) {
        stateLock.lock()
        guard let session = resolve(target) else {
            stateLock.unlock()
            continuation.resume(throwing: HanaBridgeFailure.closed)
            return
        }
        state.lastOperation &+= 1
        let ticket = HanaOperationTicket(session: session, operation: state.lastOperation)
        guard slot.assign(ticket) else {
            stateLock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }
        queue.async {
            let outcome = Result { try call(ticket.session, ticket.operation) }
            if case .failure(let error) = outcome {
                self.noteFailure(error, session: ticket.session)
            }
            continuation.resume(with: outcome)
        }
        stateLock.unlock()
    }

    private func resolve(_ target: Target) -> UInt64? {
        switch target {
        case .connecting(let session):
            guard state.session == session, !state.isAdopted else { return nil }
            return session
        case .connected:
            guard state.session != 0, state.isAdopted else { return nil }
            return state.session
        }
    }

    private func noteFailure(_ error: any Error, session: UInt64) {
        guard (error as? HanaBridgeFailure)?.kind == .connectionLost else { return }
        stateLock.withLock {
            guard state.session == session else { return }
            state.hasLostConnection = true
        }
    }

    private static func open(_ configurationJSON: Data) throws -> UInt64 {
        var rawError: UnsafeMutablePointer<CChar>?
        let session = configurationJSON.withUnsafeBytes { bytes in
            tp_hana_open(bytes.baseAddress?.assumingMemoryBound(to: UInt8.self), bytes.count, &rawError)
        }
        guard session != 0 else { throw failure(consuming: rawError) }
        release(rawError)
        return session
    }

    private static func close(_ session: UInt64) {
        guard session != 0 else { return }
        DispatchQueue.global(qos: .userInitiated).async { tp_hana_close(session) }
    }

    private static func cancel(_ ticket: HanaOperationTicket) {
        DispatchQueue.global(qos: .userInitiated).async { tp_hana_cancel(ticket.session, ticket.operation) }
    }

    private static func envelope(
        consuming rawResult: UnsafeMutablePointer<CChar>?,
        error rawError: UnsafeMutablePointer<CChar>?
    ) throws -> HanaResultEnvelope {
        guard rawResult != nil else { throw failure(consuming: rawError) }
        release(rawError)
        return try decode(HanaResultEnvelope.self, consuming: rawResult)
    }

    private static func decode<T: Decodable>(_ type: T.Type, consuming pointer: UnsafeMutablePointer<CChar>?) throws -> T {
        guard let data = consume(pointer) else { throw HanaError.unreadableResult }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            logger.error("SAP HANA bridge returned unreadable JSON: \(error.localizedDescription, privacy: .private)")
            throw HanaError.unreadableResult
        }
    }

    private static func failure(consuming pointer: UnsafeMutablePointer<CChar>?) -> HanaBridgeFailure {
        guard let data = consume(pointer) else { return HanaBridgeFailure(kind: .internalFailure) }
        return HanaBridgeFailure.decoded(from: data)
    }

    private static func consume(_ pointer: UnsafeMutablePointer<CChar>?) -> Data? {
        guard let pointer else { return nil }
        defer { tp_hana_free_string(pointer) }
        return Data(bytes: pointer, count: strlen(pointer))
    }

    private static func release(_ pointer: UnsafeMutablePointer<CChar>?) {
        guard let pointer else { return }
        tp_hana_free_string(pointer)
    }
}
