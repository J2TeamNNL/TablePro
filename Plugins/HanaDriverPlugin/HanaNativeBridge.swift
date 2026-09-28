import CHana
import Foundation

protocol HanaNativeBridge: Sendable {
    func open(configuration: Data) throws -> UInt64
    func connect(_ ticket: HanaOperationTicket) throws -> Data
    func execute(_ ticket: HanaOperationTicket, request: Data) throws -> Data
    func explain(_ ticket: HanaOperationTicket, request: Data) throws -> Data
    func ping(_ ticket: HanaOperationTicket) throws
    func cancel(_ ticket: HanaOperationTicket)
    func close(session: UInt64)
}

struct HanaCBridge: HanaNativeBridge {
    func open(configuration: Data) throws -> UInt64 {
        var rawError: UnsafeMutablePointer<CChar>?
        let session = configuration.withUnsafeBytes { bytes in
            tp_hana_open(bytes.baseAddress?.assumingMemoryBound(to: UInt8.self), bytes.count, &rawError)
        }
        guard session != 0 else { throw Self.failure(consuming: rawError) }
        Self.release(rawError)
        return session
    }

    func connect(_ ticket: HanaOperationTicket) throws -> Data {
        var rawResult: UnsafeMutablePointer<CChar>?
        var rawError: UnsafeMutablePointer<CChar>?
        guard tp_hana_connect(ticket.session, ticket.operation, &rawResult, &rawError) else {
            Self.release(rawResult)
            throw Self.failure(consuming: rawError)
        }
        Self.release(rawError)
        guard let data = Self.consume(rawResult) else { throw HanaError.unreadableResult }
        return data
    }

    func execute(_ ticket: HanaOperationTicket, request: Data) throws -> Data {
        var rawError: UnsafeMutablePointer<CChar>?
        let rawResult = request.withUnsafeBytes { bytes in
            tp_hana_execute(
                ticket.session,
                ticket.operation,
                bytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                bytes.count,
                &rawError
            )
        }
        return try Self.payload(consuming: rawResult, error: rawError)
    }

    func explain(_ ticket: HanaOperationTicket, request: Data) throws -> Data {
        var rawError: UnsafeMutablePointer<CChar>?
        let rawResult = request.withUnsafeBytes { bytes in
            tp_hana_explain(
                ticket.session,
                ticket.operation,
                bytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                bytes.count,
                &rawError
            )
        }
        return try Self.payload(consuming: rawResult, error: rawError)
    }

    func ping(_ ticket: HanaOperationTicket) throws {
        var rawError: UnsafeMutablePointer<CChar>?
        guard tp_hana_ping(ticket.session, ticket.operation, &rawError) else {
            throw Self.failure(consuming: rawError)
        }
        Self.release(rawError)
    }

    func cancel(_ ticket: HanaOperationTicket) {
        tp_hana_cancel(ticket.session, ticket.operation)
    }

    func close(session: UInt64) {
        tp_hana_close(session)
    }

    private static func payload(
        consuming rawResult: UnsafeMutablePointer<CChar>?,
        error rawError: UnsafeMutablePointer<CChar>?
    ) throws -> Data {
        guard rawResult != nil else { throw failure(consuming: rawError) }
        release(rawError)
        guard let data = consume(rawResult) else { throw HanaError.unreadableResult }
        return data
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
