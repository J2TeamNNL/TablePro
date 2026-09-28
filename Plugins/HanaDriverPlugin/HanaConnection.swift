import CHana
import Foundation
import TableProPluginKit

struct HanaConnectOptions: Codable, Sendable {
    let host: String
    let port: Int
    let username: String
    let password: String
    let schema: String
    let tlsMode: Int
    let tlsServerName: String
    let caPath: String
}

struct HanaBridgeResult: Codable, Sendable {
    struct Cell: Codable, Sendable {
        let kind: String
        let value: String?
    }

    let columns: [String]
    let columnTypeNames: [String]
    let rows: [[Cell]]
    let rowsAffected: Int64
    let executionTime: TimeInterval
    let isTruncated: Bool

    var pluginResult: PluginQueryResult {
        PluginQueryResult(
            columns: columns,
            columnTypeNames: columnTypeNames,
            rows: rows.map { row in
                row.map { cell in
                    switch cell.kind {
                    case "null": return .null
                    case "bytes": return .bytes(Data(base64Encoded: cell.value ?? "") ?? Data())
                    default: return .text(cell.value ?? "")
                    }
                }
            },
            rowsAffected: Int(clamping: rowsAffected),
            timing: PluginQueryTiming(total: executionTime),
            isTruncated: isTruncated
        )
    }
}

enum HanaError: LocalizedError, Sendable {
    case bridge(String)
    case invalidPort
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .bridge(let message): return message
        case .invalidPort: return String(localized: "The SAP HANA port must be between 1 and 65535.")
        case .unsupported(let message): return message
        }
    }
}

final class HanaConnection: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.TablePro.hana.connection", qos: .userInitiated)
    private let stateLock = NSLock()
    private var handle: UInt64 = 0
    private var epoch: UInt64 = 0

    deinit {
        disconnect()
    }

    func connect(options: HanaConnectOptions) async throws {
        let data = try JSONEncoder().encode(options)
        let attempt = stateLock.withLock { () -> UInt64 in
            epoch &+= 1
            return epoch
        }
        let handle = try await run { [data] in
            var rawError: UnsafeMutablePointer<CChar>?
            let rawHandle = data.withUnsafeBytes { bytes in
                tp_hana_connect(
                    bytes.bindMemory(to: UInt8.self).baseAddress,
                    data.count,
                    &rawError
                )
            }
            guard rawHandle != 0 else { throw Self.error(from: rawError) }
            return rawHandle
        }
        let adopted = stateLock.withLock { () -> Bool in
            guard self.epoch == attempt, self.handle == 0 else { return false }
            self.handle = handle
            return true
        }
        guard adopted else {
            queue.async { tp_hana_disconnect(handle) }
            throw HanaError.bridge(String(localized: "The SAP HANA connection was closed."))
        }
    }

    func disconnect() {
        let handle = stateLock.withLock { () -> UInt64 in
            let current = self.handle
            self.handle = 0
            self.epoch &+= 1
            return current
        }
        guard handle != 0 else { return }
        queue.async { tp_hana_disconnect(handle) }
    }

    func cancel() {
        let handle = stateLock.withLock { self.handle }
        guard handle != 0 else { return }
        tp_hana_cancel(handle)
    }

    func ping() async throws {
        try await run {
            let handle = try self.connectedHandle()
            var rawError: UnsafeMutablePointer<CChar>?
            guard tp_hana_ping(handle, &rawError) else { throw Self.error(from: rawError) }
        }
    }

    func execute(_ sql: String, rowCap: Int?) async throws -> HanaBridgeResult {
        try await run {
            let handle = try self.connectedHandle()
            let bytes = Array(sql.utf8)
            var rawError: UnsafeMutablePointer<CChar>?
            let rawResult = bytes.withUnsafeBufferPointer { buffer in
                tp_hana_execute(
                    handle,
                    buffer.baseAddress,
                    buffer.count,
                    UInt64(max(0, rowCap ?? PluginRowLimits.emergencyMax)),
                    &rawError
                )
            }
            guard let rawResult else { throw Self.error(from: rawError) }
            defer { tp_hana_free_string(rawResult) }
            let json = String(cString: rawResult)
            guard let data = json.data(using: .utf8) else {
                throw HanaError.bridge(String(localized: "SAP HANA returned invalid result data."))
            }
            do {
                return try JSONDecoder().decode(HanaBridgeResult.self, from: data)
            } catch {
                throw HanaError.bridge(String(localized: "SAP HANA returned an unreadable result."))
            }
        }
    }

    private func connectedHandle() throws -> UInt64 {
        let handle = stateLock.withLock { self.handle }
        guard handle != 0 else {
            throw HanaError.bridge(String(localized: "The SAP HANA connection is closed."))
        }
        return handle
    }

    private func run<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result(catching: operation))
            }
        }
    }

    private static func error(from pointer: UnsafeMutablePointer<CChar>?) -> HanaError {
        guard let pointer else {
            return .bridge(String(localized: "SAP HANA returned an unknown error."))
        }
        defer { tp_hana_free_string(pointer) }
        return .bridge(String(cString: pointer))
    }
}
