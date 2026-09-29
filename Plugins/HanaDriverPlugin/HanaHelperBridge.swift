import Foundation
import os

final class HanaHelperBridge: HanaNativeBridge, @unchecked Sendable {
    static let defaultCancelDeadline: TimeInterval = 15
    static let handshakeDeadline: TimeInterval = 15

    private struct Route {
        let helper: HanaHelperProcess
        let session: UInt64
    }

    private static let logger = Logger(subsystem: "com.TablePro", category: "HanaHelperBridge")

    private let locateExecutable: @Sendable () throws -> URL
    private let cancelDeadline: TimeInterval
    private let launchLock = NSLock()
    private let lock = NSLock()
    private var helper: HanaHelperProcess?
    private var routes: [UInt64: Route] = [:]
    private var lastSession: UInt64 = 0

    init(
        cancelDeadline: TimeInterval = HanaHelperBridge.defaultCancelDeadline,
        locateExecutable: @escaping @Sendable () throws -> URL = { try HanaHelperBridge.bundledExecutable() }
    ) {
        self.cancelDeadline = cancelDeadline
        self.locateExecutable = locateExecutable
    }

    deinit {
        shutdown()
    }

    var helperProcessIdentifier: pid_t? {
        lock.withLock { helper?.processIdentifier }
    }

    func open(configuration: Data) throws -> UInt64 {
        let helper = try runningHelper()
        let reply = try helper.call(.open, body: configuration, ticket: nil)
        let remoteSession = try HanaHelperMessage.openedSession(from: reply)
        return lock.withLock {
            lastSession &+= 1
            routes[lastSession] = Route(helper: helper, session: remoteSession)
            return lastSession
        }
    }

    func connect(_ ticket: HanaOperationTicket) throws -> Data {
        try call(.connect, ticket: ticket) { HanaHelperMessage.operation($0) }
    }

    func execute(_ ticket: HanaOperationTicket, request: Data) throws -> Data {
        try call(.execute, ticket: ticket) { HanaHelperMessage.statement($0, request: request) }
    }

    func explain(_ ticket: HanaOperationTicket, request: Data) throws -> Data {
        try call(.explain, ticket: ticket) { HanaHelperMessage.statement($0, request: request) }
    }

    func ping(_ ticket: HanaOperationTicket) throws {
        _ = try call(.ping, ticket: ticket) { HanaHelperMessage.operation($0) }
    }

    func cancel(_ ticket: HanaOperationTicket) {
        guard let route = lock.withLock({ routes[ticket.session] }) else { return }
        let remoteTicket = HanaOperationTicket(session: route.session, operation: ticket.operation)
        guard let cancelFrame = route.helper.post(.cancel, body: HanaHelperMessage.operation(remoteTicket)) else { return }
        let watch = HanaHelperCancelWatch(ticket: remoteTicket, issuedThrough: cancelFrame)
        let cause = "TablePro stopped the SAP HANA helper because a cancelled operation was still running "
            + "\(Self.secondsText(cancelDeadline)) seconds later."
        let helper = route.helper
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + cancelDeadline) { [weak helper] in
            helper?.stop(ifStillPending: watch, cause: cause)
        }
    }

    func close(session: UInt64) {
        guard let route = lock.withLock({ routes.removeValue(forKey: session) }) else { return }
        route.helper.post(.close, body: HanaHelperMessage.session(route.session))
    }

    func shutdown() {
        let retired = lock.withLock { () -> HanaHelperProcess? in
            let retired = helper
            helper = nil
            routes.removeAll()
            return retired
        }
        retired?.shutdown()
    }

    static func bundledExecutable() throws -> URL {
        try HanaHelperTrust.verifiedExecutable(in: Bundle(for: HanaPluginDriver.self))
    }

    private func call(
        _ opcode: HanaHelperOpcode,
        ticket: HanaOperationTicket,
        body: (HanaOperationTicket) -> Data
    ) throws -> Data {
        guard let route = lock.withLock({ routes[ticket.session] }) else { throw HanaBridgeFailure.closed }
        let remoteTicket = HanaOperationTicket(session: route.session, operation: ticket.operation)
        return try route.helper.call(opcode, body: body(remoteTicket), ticket: remoteTicket)
    }

    private func runningHelper() throws -> HanaHelperProcess {
        try launchLock.withLock {
            if let current = lock.withLock({ helper }), current.isAlive {
                return current
            }
            let launched = try HanaHelperProcess.launch(
                executable: locateExecutable(),
                handshakeDeadline: Self.handshakeDeadline
            )
            let retired = lock.withLock { () -> HanaHelperProcess? in
                let retired = helper
                helper = launched
                routes = routes.filter { $0.value.helper.isAlive }
                return retired
            }
            retired?.shutdown()
            Self.logger.debug("SAP HANA helper \(launched.processIdentifier) is serving this connection")
            return launched
        }
    }

    private static func secondsText(_ seconds: TimeInterval) -> String {
        seconds.rounded() == seconds ? String(Int(seconds)) : String(seconds)
    }
}
