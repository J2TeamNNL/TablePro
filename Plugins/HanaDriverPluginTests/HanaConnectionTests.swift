import Foundation
import XCTest

final class HanaConnectionTests: XCTestCase {
    private static let configuration = HanaConnectConfiguration(
        host: "hana.example",
        port: 443,
        username: "DBADMIN",
        password: "test-only",
        schema: "APP",
        tlsMode: .verifyIdentity,
        tlsServerName: "",
        caCertificatePath: "",
        clientCertificatePath: "",
        clientKeyPath: "",
        connectTimeoutSeconds: 30
    )

    func testStopWithNothingRunningSendsNothing() async throws {
        let bridge = HanaFakeBridge()
        let connection = HanaConnection(bridge: bridge)

        connection.cancelRunning()
        _ = try await connection.connect(Self.configuration)
        _ = try await connection.execute(sql: "SELECT 1 FROM DUMMY", parameters: nil, rowCap: 0)
        connection.cancelRunning()

        XCTAssertTrue(bridge.cancels.isEmpty)
    }

    func testAStopThatLandsAfterItsOperationFinishedNeverCancelsTheNextOne() async throws {
        let bridge = HanaFakeBridge()
        let connection = HanaConnection(bridge: bridge)
        _ = try await connection.connect(Self.configuration)
        let first = bridge.hold(sql: "UPDATE A SET X = 1")
        let second = bridge.hold(sql: "UPDATE B SET X = 1")
        let delivery = bridge.holdCancels()
        let firstRun = Task { try await connection.execute(sql: "UPDATE A SET X = 1", parameters: nil, rowCap: 0) }
        let firstTicket = await first.arrival()

        let stopReturned = HanaLatch()
        DispatchQueue.global().async {
            connection.cancelRunning()
            stopReturned.open()
        }
        let stoppedTicket = await delivery.arrival()
        first.release()
        _ = try await firstRun.value
        let secondRun = Task { try await connection.execute(sql: "UPDATE B SET X = 1", parameters: nil, rowCap: 0) }
        let secondTicket = await second.arrival()
        delivery.release()
        await stopReturned.wait()
        second.release()

        _ = try await secondRun.value
        XCTAssertEqual(stoppedTicket, firstTicket)
        XCTAssertNotEqual(secondTicket, firstTicket)
        XCTAssertEqual(bridge.cancels, [firstTicket])
    }

    func testAStopWhileAnOperationRunsNamesExactlyThatOperation() async throws {
        let bridge = HanaFakeBridge()
        let connection = HanaConnection(bridge: bridge)
        _ = try await connection.connect(Self.configuration)
        let hold = bridge.hold(sql: "SELECT * FROM BIG")
        let run = Task { try await connection.execute(sql: "SELECT * FROM BIG", parameters: nil, rowCap: 0) }
        let ticket = await hold.arrival()

        connection.cancelRunning()

        XCTAssertEqual(bridge.cancels, [ticket])
        XCTAssertNotEqual(ticket.operation, 0)
        hold.release()
        await assertFailure(of: run, kind: .cancelled)
    }

    func testCancellingTheTaskStopsItsOwnOperationBeforeCancelReturns() async throws {
        let bridge = HanaFakeBridge()
        let connection = HanaConnection(bridge: bridge)
        _ = try await connection.connect(Self.configuration)
        let hold = bridge.hold(sql: "SELECT * FROM BIG")
        let run = Task { try await connection.execute(sql: "SELECT * FROM BIG", parameters: nil, rowCap: 0) }
        let ticket = await hold.arrival()

        run.cancel()

        XCTAssertEqual(bridge.cancels, [ticket])
        hold.release()
        await assertFailure(of: run, kind: .cancelled)
        XCTAssertEqual(bridge.cancels, [ticket])
    }

    func testATaskCancelledWhileQueuedNeverReachesTheBridge() async throws {
        let bridge = HanaFakeBridge()
        let queue = HanaRecordingQueue()
        let connection = HanaConnection(bridge: bridge, queue: queue)
        _ = try await connection.connect(Self.configuration)
        let hold = bridge.hold(sql: "SELECT * FROM BIG")
        let running = Task { try await connection.execute(sql: "SELECT * FROM BIG", parameters: nil, rowCap: 0) }
        _ = await hold.arrival()
        let queued = Task { try await connection.execute(sql: "DELETE FROM T", parameters: nil, rowCap: 0) }
        await queue.submissions(reaching: 3)

        queued.cancel()
        hold.release()

        _ = try await running.value
        do {
            _ = try await queued.value
            XCTFail("the queued statement should not run")
        } catch {
            XCTAssertTrue(error is CancellationError, "got \(error)")
        }
        XCTAssertEqual(bridge.statements.map(\.sql), ["SELECT * FROM BIG"])
    }

    func testDisconnectClosesTheSessionBeforeReturningAndDropsQueuedWork() async throws {
        let bridge = HanaFakeBridge()
        let queue = HanaRecordingQueue()
        let connection = HanaConnection(bridge: bridge, queue: queue)
        _ = try await connection.connect(Self.configuration)
        let hold = bridge.hold(sql: "UPDATE A SET X = 1")
        let running = Task { try await connection.execute(sql: "UPDATE A SET X = 1", parameters: nil, rowCap: 0) }
        let runningTicket = await hold.arrival()
        let queued = Task { try await connection.execute(sql: "DELETE FROM T", parameters: nil, rowCap: 0) }
        await queue.submissions(reaching: 3)

        connection.disconnect()

        XCTAssertEqual(bridge.closes, [runningTicket.session])
        hold.release()
        await assertFailure(of: running, kind: .closed)
        await assertFailure(of: queued, kind: .closed)
        XCTAssertEqual(bridge.statements.map(\.sql), ["UPDATE A SET X = 1"])
        XCTAssertFalse(connection.hasLostConnection)
    }

    func testReconnectClosesTheOldSessionAndDropsWorkQueuedForIt() async throws {
        let bridge = HanaFakeBridge()
        let queue = HanaRecordingQueue()
        let connection = HanaConnection(bridge: bridge, queue: queue)
        _ = try await connection.connect(Self.configuration)
        let hold = bridge.hold(sql: "UPDATE A SET X = 1")
        let running = Task { try await connection.execute(sql: "UPDATE A SET X = 1", parameters: nil, rowCap: 0) }
        let oldSession = await hold.arrival().session
        let queued = Task { try await connection.execute(sql: "DELETE FROM T", parameters: nil, rowCap: 0) }
        await queue.submissions(reaching: 3)

        let reconnect = Task { try await connection.connect(Self.configuration) }
        await queue.submissions(reaching: 4)

        XCTAssertEqual(bridge.closes, [oldSession])
        hold.release()
        await assertFailure(of: queued, kind: .closed)
        _ = try await reconnect.value
        _ = try? await running.value
        XCTAssertEqual(bridge.statements.map(\.sql), ["UPDATE A SET X = 1"])
        XCTAssertEqual(bridge.connects.map(\.session), [oldSession, oldSession + 1])
        _ = try await connection.execute(sql: "SELECT 1 FROM DUMMY", parameters: nil, rowCap: 0)
        XCTAssertEqual(bridge.statements.last?.ticket.session, oldSession + 1)
    }

    func testASessionLostEnvelopeKeepsItsRowsAndMarksTheConnectionLost() async throws {
        let bridge = HanaFakeBridge()
        bridge.respond(to: "COMMIT", with: HanaBridgeJSON.envelope(columns: ["A"], rows: [["1"]], sessionLost: true))
        let connection = HanaConnection(bridge: bridge)
        _ = try await connection.connect(Self.configuration)

        _ = try await connection.execute(sql: "SELECT 1 FROM DUMMY", parameters: nil, rowCap: 0)
        XCTAssertFalse(connection.hasLostConnection)
        let envelope = try await connection.execute(sql: "COMMIT", parameters: nil, rowCap: 0)

        XCTAssertEqual(envelope.rows, [[.text("1")]])
        XCTAssertTrue(envelope.sessionLost)
        XCTAssertTrue(connection.hasLostConnection)
    }

    func testAPlanFromASessionLostWhileDiscardingItStillArrives() async throws {
        let bridge = HanaFakeBridge()
        let plan = HanaBridgeJSON.envelope(columns: ["QUERY PLAN"], rows: [["COLUMN SEARCH"]], sessionLost: true)
        bridge.respond(to: "SELECT * FROM T", with: plan)
        let connection = HanaConnection(bridge: bridge)
        _ = try await connection.connect(Self.configuration)

        let envelope = try await connection.explain(sql: "SELECT * FROM T")

        XCTAssertEqual(envelope.rows, [[.text("COLUMN SEARCH")]])
        XCTAssertTrue(connection.hasLostConnection)
    }

    func testReconnectingClearsALostSession() async throws {
        let bridge = HanaFakeBridge()
        bridge.respond(to: "COMMIT", with: HanaBridgeJSON.envelope(sessionLost: true))
        let connection = HanaConnection(bridge: bridge)
        _ = try await connection.connect(Self.configuration)
        _ = try await connection.execute(sql: "COMMIT", parameters: nil, rowCap: 0)
        XCTAssertTrue(connection.hasLostConnection)

        _ = try await connection.connect(Self.configuration)

        XCTAssertFalse(connection.hasLostConnection)
    }

    private func assertFailure<T: Sendable>(
        of task: Task<T, any Error>,
        kind: HanaBridgeFailure.Kind,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await task.value
            XCTFail("the operation should fail with \(kind)", file: file, line: line)
        } catch {
            XCTAssertEqual((error as? HanaBridgeFailure)?.kind, kind, "got \(error)", file: file, line: line)
        }
    }
}
