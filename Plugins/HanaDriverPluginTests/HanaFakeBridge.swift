import Foundation

final class HanaFakeBridge: HanaNativeBridge, @unchecked Sendable {
    struct Statement: Equatable {
        let ticket: HanaOperationTicket
        let sql: String
    }

    static let connectResult = Data(#"{"serverVersion":"4.00.000.00.1","currentSchema":"APP","connectionId":200123}"#.utf8)

    private let lock = NSLock()
    private var lastSession: UInt64 = 40
    private var openSessions: Set<UInt64> = []
    private var running: HanaOperationTicket?
    private var stopped: Set<HanaOperationTicket> = []
    private var connectLog: [HanaOperationTicket] = []
    private var statementLog: [Statement] = []
    private var pingLog: [HanaOperationTicket] = []
    private var cancelLog: [HanaOperationTicket] = []
    private var closeLog: [UInt64] = []
    private var statementHolds: [String: HanaBridgeHold] = [:]
    private var pingHold: HanaBridgeHold?
    private var cancelHold: HanaBridgeHold?
    private var responses: [String: Data] = [:]

    var connects: [HanaOperationTicket] { lock.withLock { connectLog } }
    var statements: [Statement] { lock.withLock { statementLog } }
    var pings: [HanaOperationTicket] { lock.withLock { pingLog } }
    var cancels: [HanaOperationTicket] { lock.withLock { cancelLog } }
    var closes: [UInt64] { lock.withLock { closeLog } }

    func hold(sql: String) -> HanaBridgeHold {
        let hold = HanaBridgeHold()
        lock.withLock { statementHolds[sql] = hold }
        return hold
    }

    func holdPing() -> HanaBridgeHold {
        let hold = HanaBridgeHold()
        lock.withLock { pingHold = hold }
        return hold
    }

    func holdCancels() -> HanaBridgeHold {
        let hold = HanaBridgeHold()
        lock.withLock { cancelHold = hold }
        return hold
    }

    func respond(to sql: String, with envelope: Data) {
        lock.withLock { responses[sql] = envelope }
    }

    func open(configuration: Data) throws -> UInt64 {
        lock.withLock {
            lastSession += 1
            openSessions.insert(lastSession)
            return lastSession
        }
    }

    func connect(_ ticket: HanaOperationTicket) throws -> Data {
        lock.withLock { connectLog.append(ticket) }
        return try run(ticket, hold: nil) { Self.connectResult }
    }

    func execute(_ ticket: HanaOperationTicket, request: Data) throws -> Data {
        try statement(ticket, request: request)
    }

    func explain(_ ticket: HanaOperationTicket, request: Data) throws -> Data {
        try statement(ticket, request: request)
    }

    func ping(_ ticket: HanaOperationTicket) throws {
        let hold = lock.withLock { () -> HanaBridgeHold? in
            pingLog.append(ticket)
            return pingHold
        }
        _ = try run(ticket, hold: hold) { Data() }
    }

    func cancel(_ ticket: HanaOperationTicket) {
        let hold = lock.withLock { () -> HanaBridgeHold? in
            cancelLog.append(ticket)
            return cancelHold
        }
        hold?.arrive(ticket)
        lock.withLock {
            guard let running, running == ticket || (ticket.operation == 0 && ticket.session == running.session) else {
                return
            }
            stopped.insert(running)
        }
    }

    func close(session: UInt64) {
        lock.withLock {
            closeLog.append(session)
            openSessions.remove(session)
        }
    }

    private func statement(_ ticket: HanaOperationTicket, request: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: request) as? [String: Any]
        let sql = object?["sql"] as? String ?? ""
        let (hold, response) = lock.withLock { () -> (HanaBridgeHold?, Data?) in
            statementLog.append(Statement(ticket: ticket, sql: sql))
            return (statementHolds[sql], responses[sql])
        }
        return try run(ticket, hold: hold) { response ?? HanaBridgeJSON.envelope() }
    }

    private func run(_ ticket: HanaOperationTicket, hold: HanaBridgeHold?, result: () -> Data) throws -> Data {
        try lock.withLock {
            guard openSessions.contains(ticket.session) else { throw HanaBridgeFailure.closed }
            running = ticket
        }
        hold?.arrive(ticket)
        let outcome = lock.withLock { () -> HanaBridgeFailure.Kind? in
            if running == ticket {
                running = nil
            }
            guard openSessions.contains(ticket.session) else { return .closed }
            return stopped.contains(ticket) ? .cancelled : nil
        }
        if let outcome {
            throw HanaBridgeFailure(kind: outcome)
        }
        return result()
    }
}

final class HanaBridgeHold: @unchecked Sendable {
    private let lock = NSLock()
    private let gate = DispatchSemaphore(value: 0)
    private var arrivals: [HanaOperationTicket] = []
    private var waiters: [CheckedContinuation<HanaOperationTicket, Never>] = []

    func arrive(_ ticket: HanaOperationTicket) {
        let waiting = lock.withLock { () -> [CheckedContinuation<HanaOperationTicket, Never>] in
            arrivals.append(ticket)
            let waiting = waiters
            waiters.removeAll()
            return waiting
        }
        waiting.forEach { $0.resume(returning: ticket) }
        _ = gate.wait(timeout: .now() + 10)
    }

    func arrival() async -> HanaOperationTicket {
        await withCheckedContinuation { continuation in
            let first = lock.withLock { () -> HanaOperationTicket? in
                guard let first = arrivals.first else {
                    waiters.append(continuation)
                    return nil
                }
                return first
            }
            guard let first else { return }
            continuation.resume(returning: first)
        }
    }

    func release() {
        gate.signal()
    }
}

final class HanaRecordingQueue: HanaOperationQueue, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.TablePro.tests.hana.connection")
    private let lock = NSLock()
    private var submitted = 0
    private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func submit(_ work: @escaping @Sendable () -> Void) {
        queue.async(execute: work)
        let ready = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            submitted += 1
            let ready = waiters.filter { $0.count <= submitted }.map(\.continuation)
            waiters.removeAll { $0.count <= submitted }
            return ready
        }
        ready.forEach { $0.resume() }
    }

    func submissions(reaching count: Int) async {
        await withCheckedContinuation { continuation in
            let reached = lock.withLock { () -> Bool in
                guard submitted >= count else {
                    waiters.append((count, continuation))
                    return false
                }
                return true
            }
            guard reached else { return }
            continuation.resume()
        }
    }
}

final class HanaLatch: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func open() {
        let waiting = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            isOpen = true
            let waiting = waiters
            waiters.removeAll()
            return waiting
        }
        waiting.forEach { $0.resume() }
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            let opened = lock.withLock { () -> Bool in
                guard isOpen else {
                    waiters.append(continuation)
                    return false
                }
                return true
            }
            guard opened else { return }
            continuation.resume()
        }
    }
}

enum HanaBridgeJSON {
    static func envelope(columns: [String] = [], rows: [[String]] = [], sessionLost: Bool = false) -> Data {
        let object: [String: Any] = [
            "columns": columns,
            "columnTypeNames": Array(repeating: "NVARCHAR", count: columns.count),
            "columnClassifications": Array(repeating: NSNull(), count: columns.count),
            "rows": rows,
            "rowsAffected": 0,
            "hasResultSet": !columns.isEmpty,
            "executionTime": 0.01,
            "isTruncated": false,
            "truncatedLobCount": 0,
            "sessionLost": sessionLost
        ]
        return (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }
}
