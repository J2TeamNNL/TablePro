import Foundation
import XCTest

final class HanaHelperProcessTests: XCTestCase {
    private static let greetingHeader = #"\000\000\000\016\000\000\000\000\000\000\000\000\000"#

    private var root: URL?

    override func setUpWithError() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("HanaHelperProcessTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        self.root = root
    }

    override func tearDownWithError() throws {
        guard let root else { return }
        try FileManager.default.removeItem(at: root)
    }

    func testAHelperSpeakingAnotherProtocolIsRefusedByNumber() throws {
        let helper = try script("""
            /usr/bin/printf '\(Self.greetingHeader){"protocol":2}'
            exec /bin/sleep 30
            """)

        XCTAssertThrowsError(try HanaHelperProcess.launch(executable: helper, handshakeDeadline: 30)) { error in
            XCTAssertEqual(error as? HanaBridgeFailure, HanaBridgeFailure(
                kind: .internalFailure,
                message: "incompatible helper protocol 2"
            ))
        }
    }

    func testAHelperThatNeverGreetsIsStoppedAtTheHandshakeDeadline() throws {
        let helper = try script("exec /bin/sleep 30")

        XCTAssertThrowsError(try HanaHelperProcess.launch(executable: helper, handshakeDeadline: 1)) { error in
            let failure = error as? HanaBridgeFailure
            XCTAssertEqual(failure?.kind, .internalFailure, "got \(error)")
            XCTAssertEqual(failure?.message.contains("did not answer within 1 seconds"), true, "\(error)")
        }
    }

    func testAHelperThatExitsBeforeGreetingReportsItsStatusAndErrorOutput() throws {
        let helper = try script("""
            echo 'panic: invalid type code' >&2
            exit 2
            """)

        XCTAssertThrowsError(try HanaHelperProcess.launch(executable: helper, handshakeDeadline: 30)) { error in
            let failure = error as? HanaBridgeFailure
            XCTAssertEqual(failure?.kind, .internalFailure, "got \(error)")
            XCTAssertEqual(failure?.message.contains("exited with status 2"), true, "\(error)")
            XCTAssertEqual(failure?.message.contains("panic: invalid type code"), true, "\(error)")
        }
    }

    func testAReplyToAFrameNobodyIssuedFailsTheWaitingCallAndEndsTheHelper() throws {
        let helper = try script("""
            /usr/bin/printf '\(Self.greetingHeader){"protocol":1}'
            /usr/bin/head -c 13 > /dev/null
            /usr/bin/printf '\\000\\000\\000\\002\\000\\000\\000\\000\\000\\000\\003\\347\\000{}'
            exec /bin/sleep 30
            """)
        let process = try HanaHelperProcess.launch(executable: helper, handshakeDeadline: 30)
        defer { process.shutdown() }

        XCTAssertThrowsError(try process.call(.ping, body: Data("{}".utf8), ticket: nil)) { error in
            XCTAssertEqual(error as? HanaBridgeFailure, HanaBridgeFailure(
                kind: .internalFailure,
                message: "the helper answered frame 999, which no call is waiting for"
            ))
        }
        XCTAssertFalse(process.isAlive)
        XCTAssertThrowsError(try process.call(.ping, body: Data("{}".utf8), ticket: nil)) { error in
            let failure = error as? HanaBridgeFailure
            XCTAssertEqual(failure?.kind, .connectionLost, "got \(error)")
            XCTAssertEqual(failure?.message.contains("frame 999"), true, "\(error)")
        }
    }

    func testCallsAfterTheHelperEndedFailWithoutWriting() throws {
        let helper = try script("""
            /usr/bin/printf '\(Self.greetingHeader){"protocol":1}'
            exit 0
            """)
        let process = try HanaHelperProcess.launch(executable: helper, handshakeDeadline: 30)
        defer { process.shutdown() }

        XCTAssertThrowsError(try process.call(.ping, body: Data("{}".utf8), ticket: nil)) { error in
            XCTAssertEqual((error as? HanaBridgeFailure)?.kind, .connectionLost, "got \(error)")
        }
        XCTAssertNil(process.post(.close, body: Data(#"{"session":1}"#.utf8)))
        XCTAssertThrowsError(try process.call(.ping, body: Data("{}".utf8), ticket: nil)) { error in
            XCTAssertEqual((error as? HanaBridgeFailure)?.message.contains("exited with status 0"), true, "\(error)")
        }
    }

    private func script(_ body: String) throws -> URL {
        let url = try XCTUnwrap(root).appendingPathComponent("helper-\(UUID().uuidString)")
        try Data("#!/bin/sh\n\(body)\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
}
