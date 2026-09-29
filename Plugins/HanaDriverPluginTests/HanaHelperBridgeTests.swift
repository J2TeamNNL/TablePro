import Darwin
import Foundation
import XCTest

final class HanaHelperBridgeTests: XCTestCase {
    private static let missingHelper = """
        tablepro-hana-helper is missing from the test bundle's Contents/MacOS. \
        Run scripts/build-hana.sh, then build HanaDriverTests again.
        """
    private static let callDeadline: TimeInterval = 30

    private var bridges: [HanaHelperBridge] = []
    private var servers: [HanaSilentServer] = []

    override func setUpWithError() throws {
        let helper = Bundle(for: HanaPluginDriver.self).url(forAuxiliaryExecutable: HanaHelperTrust.executableName)
        _ = try XCTUnwrap(helper, Self.missingHelper)
    }

    override func tearDown() {
        bridges.forEach { $0.shutdown() }
        bridges.removeAll()
        servers.forEach { $0.stop() }
        servers.removeAll()
        super.tearDown()
    }

    func testOpeningTheFirstSessionStartsAHelperThatPassesTheHandshake() throws {
        let bridge = makeBridge()

        let session = try bridge.open(configuration: configuration(port: HanaLoopbackSocket.closedPort()))

        XCTAssertGreaterThan(session, 0)
        let processIdentifier = try XCTUnwrap(bridge.helperProcessIdentifier)
        XCTAssertTrue(HanaProcessProbe.isRunning(processIdentifier))
    }

    func testSessionsOpenedOnOneHelperGetDistinctIdentifiers() throws {
        let bridge = makeBridge()
        let port = try HanaLoopbackSocket.closedPort()

        let first = try bridge.open(configuration: configuration(port: port))
        let processIdentifier = bridge.helperProcessIdentifier
        let second = try bridge.open(configuration: configuration(port: port))

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(bridge.helperProcessIdentifier, processIdentifier)
    }

    func testOpeningWithAnInvalidConfigurationIsAConfigurationFailure() throws {
        let bridge = makeBridge()

        XCTAssertThrowsError(try bridge.open(configuration: configuration(host: "", port: 30_015))) { error in
            let failure = error as? HanaBridgeFailure
            XCTAssertEqual(failure?.kind, .configuration, "got \(error)")
            XCTAssertEqual(failure?.message, "host")
        }
    }

    func testConnectingToAClosedPortIsAConnectFailure() throws {
        let bridge = makeBridge()
        let session = try bridge.open(configuration: configuration(port: HanaLoopbackSocket.closedPort()))

        XCTAssertThrowsError(try bridge.connect(HanaOperationTicket(session: session, operation: 1))) { error in
            XCTAssertEqual((error as? HanaBridgeFailure)?.kind, .connect, "got \(error)")
        }
    }

    func testCancellingAConnectTheServerNeverAnswersReportsCancelled() throws {
        let bridge = makeBridge()
        let (ticket, call) = try blockedConnect(on: bridge)

        bridge.cancel(ticket)

        XCTAssertEqual(try failure(of: call).kind, .cancelled)
        let processIdentifier = try XCTUnwrap(bridge.helperProcessIdentifier)
        XCTAssertTrue(HanaProcessProbe.isRunning(processIdentifier))
    }

    func testKillingTheHelperFailsThePendingCallAsConnectionLostAndLaterCallsFailCleanly() throws {
        let bridge = makeBridge()
        let (ticket, call) = try blockedConnect(on: bridge)
        let processIdentifier = try XCTUnwrap(bridge.helperProcessIdentifier)

        kill(processIdentifier, SIGKILL)
        for _ in 0..<200 {
            bridge.cancel(ticket)
        }

        let lost = try failure(of: call)
        XCTAssertEqual(lost.kind, .connectionLost)
        XCTAssertTrue(lost.message.contains("signal \(SIGKILL)"), lost.message)
        XCTAssertThrowsError(try bridge.ping(HanaOperationTicket(session: ticket.session, operation: 2))) { error in
            XCTAssertEqual((error as? HanaBridgeFailure)?.kind, .connectionLost, "got \(error)")
        }
        XCTAssertThrowsError(try bridge.connect(HanaOperationTicket(session: ticket.session, operation: 3))) { error in
            XCTAssertEqual((error as? HanaBridgeFailure)?.kind, .connectionLost, "got \(error)")
        }
        bridge.close(session: ticket.session)
        XCTAssertTrue(HanaProcessProbe.waitForExit(of: processIdentifier, within: Self.callDeadline))
    }

    func testOpeningAfterTheHelperDiedStartsANewHelper() throws {
        let bridge = makeBridge()
        let (_, call) = try blockedConnect(on: bridge)
        let firstHelper = try XCTUnwrap(bridge.helperProcessIdentifier)
        kill(firstHelper, SIGKILL)
        XCTAssertEqual(try failure(of: call).kind, .connectionLost)

        let session = try bridge.open(configuration: configuration(port: HanaLoopbackSocket.closedPort()))

        let secondHelper = try XCTUnwrap(bridge.helperProcessIdentifier)
        XCTAssertNotEqual(secondHelper, firstHelper)
        XCTAssertThrowsError(try bridge.connect(HanaOperationTicket(session: session, operation: 1))) { error in
            XCTAssertEqual((error as? HanaBridgeFailure)?.kind, .connect, "got \(error)")
        }
    }

    func testACancelledCallTheHelperNeverAnswersEndsTheHelperAtTheDeadline() throws {
        let bridge = makeBridge(cancelDeadline: 1)
        let (ticket, call) = try blockedConnect(on: bridge)
        let processIdentifier = try XCTUnwrap(bridge.helperProcessIdentifier)
        kill(processIdentifier, SIGSTOP)

        bridge.cancel(ticket)

        let lost = try failure(of: call)
        XCTAssertEqual(lost.kind, .connectionLost)
        XCTAssertTrue(lost.message.contains("cancelled operation"), lost.message)
        XCTAssertTrue(HanaProcessProbe.waitForExit(of: processIdentifier, within: Self.callDeadline))
    }

    func testClosingASessionLeavesTheHelperRunningForTheNextOne() throws {
        let bridge = makeBridge()
        let port = try HanaLoopbackSocket.closedPort()
        let session = try bridge.open(configuration: configuration(port: port))
        let processIdentifier = try XCTUnwrap(bridge.helperProcessIdentifier)

        bridge.close(session: session)

        XCTAssertThrowsError(try bridge.connect(HanaOperationTicket(session: session, operation: 1))) { error in
            XCTAssertEqual(error as? HanaBridgeFailure, .closed)
        }
        _ = try bridge.open(configuration: configuration(port: port))
        XCTAssertEqual(bridge.helperProcessIdentifier, processIdentifier)
        XCTAssertTrue(HanaProcessProbe.isRunning(processIdentifier))
    }

    func testShutdownMakesTheHelperExit() throws {
        let bridge = makeBridge()
        let session = try bridge.open(configuration: configuration(port: HanaLoopbackSocket.closedPort()))
        let processIdentifier = try XCTUnwrap(bridge.helperProcessIdentifier)

        bridge.shutdown()

        XCTAssertNil(bridge.helperProcessIdentifier)
        XCTAssertTrue(HanaProcessProbe.waitForExit(of: processIdentifier, within: Self.callDeadline))
        XCTAssertThrowsError(try bridge.connect(HanaOperationTicket(session: session, operation: 1))) { error in
            XCTAssertEqual(error as? HanaBridgeFailure, .closed)
        }
    }

    private func makeBridge(cancelDeadline: TimeInterval = HanaHelperBridge.defaultCancelDeadline) -> HanaHelperBridge {
        let bridge = HanaHelperBridge(cancelDeadline: cancelDeadline)
        bridges.append(bridge)
        return bridge
    }

    private func blockedConnect(on bridge: HanaHelperBridge) throws -> (HanaOperationTicket, HanaBlockingCall) {
        let server = try HanaSilentServer()
        servers.append(server)
        let session = try bridge.open(configuration: configuration(port: server.port))
        let ticket = HanaOperationTicket(session: session, operation: 1)
        let call = HanaBlockingCall { try bridge.connect(ticket) }
        XCTAssertTrue(server.awaitConnection(within: Self.callDeadline), "the helper never dialled the test server")
        XCTAssertFalse(call.hasFinished, "the connect should still be waiting for the server")
        return (ticket, call)
    }

    private func failure(of call: HanaBlockingCall) throws -> HanaBridgeFailure {
        let outcome = try XCTUnwrap(call.outcome(within: Self.callDeadline), "the call never finished")
        guard case .failure(let error) = outcome else {
            XCTFail("the call should fail")
            return HanaBridgeFailure(kind: .internalFailure)
        }
        return try XCTUnwrap(error as? HanaBridgeFailure, "got \(error)")
    }

    private func configuration(host: String = "127.0.0.1", port: Int) throws -> Data {
        try JSONEncoder().encode(
            HanaConnectConfiguration(
                host: host,
                port: port,
                username: "SYSTEM",
                password: "test-only",
                schema: "",
                tlsMode: .disabled,
                tlsServerName: "",
                caCertificatePath: "",
                clientCertificatePath: "",
                clientKeyPath: "",
                connectTimeoutSeconds: 120
            )
        )
    }
}
