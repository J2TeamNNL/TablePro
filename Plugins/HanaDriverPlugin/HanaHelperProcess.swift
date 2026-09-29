import Darwin
import Foundation
import os

final class HanaHelperProcess: @unchecked Sendable {
    static let shutdownGrace: TimeInterval = 2
    static let exitReportDeadline: TimeInterval = 2

    private enum StreamEnd {
        case endOfStream
        case violation(HanaHelperFrameError)
        case readFailed(Int32)
    }

    private static let logger = Logger(subsystem: "com.TablePro", category: "HanaHelperProcess")

    let processIdentifier: pid_t

    private let process: Process
    private let input: FileHandle
    private let output: FileHandle
    private let errorStream = HanaHelperErrorStream()
    private let exited: DispatchSemaphore
    private let handshake = HanaHelperPendingCall(ticket: nil)
    private let writer = DispatchQueue(label: "com.TablePro.hana.helper.writer", qos: .userInitiated)
    private let stateLock = NSLock()
    private var lastFrameID: UInt64 = 0
    private var pendingCalls: [UInt64: HanaHelperPendingCall] = [:]
    private var deathFailure: HanaBridgeFailure?
    private var stopCause: String?
    private var isShuttingDown = false
    private var isInputClosed = false
    private var isHandshaken = false

    static func launch(executable: URL, handshakeDeadline: TimeInterval) throws -> HanaHelperProcess {
        let helper = try HanaHelperProcess(executable: executable)
        try helper.awaitHandshake(within: handshakeDeadline)
        return helper
    }

    private init(executable: URL) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = []
        process.environment = [:]
        process.qualityOfService = .userInitiated
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try HanaHelperPipe.suppressBrokenPipeSignal(on: inputPipe.fileHandleForWriting.fileDescriptor)
            try process.run()
        } catch {
            throw HanaBridgeFailure(
                kind: .internalFailure,
                message: "TablePro could not start the SAP HANA helper: \(error.localizedDescription)"
            )
        }
        self.process = process
        self.exited = exited
        processIdentifier = process.processIdentifier
        input = inputPipe.fileHandleForWriting
        output = outputPipe.fileHandleForReading
        startThreads(errorHandle: errorPipe.fileHandleForReading)
        Self.logger.debug("Started the SAP HANA helper as process \(self.processIdentifier)")
    }

    var isAlive: Bool {
        stateLock.withLock { deathFailure == nil }
    }

    func call(_ opcode: HanaHelperOpcode, body: Data, ticket: HanaOperationTicket?) throws -> Data {
        let pending = HanaHelperPendingCall(ticket: ticket)
        let request = try register(pending, opcode: opcode, body: body)
        writer.sync { send(request) }
        return try pending.wait().get()
    }

    @discardableResult
    func post(_ opcode: HanaHelperOpcode, body: Data) -> UInt64? {
        let request = stateLock.withLock { () -> HanaHelperRequest? in
            guard deathFailure == nil else { return nil }
            lastFrameID &+= 1
            return try? HanaHelperRequest(id: lastFrameID, opcode: opcode, body: body)
        }
        guard let request else { return nil }
        writer.async { self.send(request) }
        return request.header.id
    }

    func stop(ifStillPending watch: HanaHelperCancelWatch, cause: String) {
        let isStillPending = stateLock.withLock {
            deathFailure == nil && pendingCalls.contains { watch.covers(callID: $0.key, ticket: $0.value.ticket) }
        }
        guard isStillPending else { return }
        Self.logger.error("SAP HANA helper \(self.processIdentifier) did not stop a cancelled operation in time")
        stop(cause: cause)
    }

    func shutdown() {
        stateLock.withLock {
            isShuttingDown = true
            if stopCause == nil {
                stopCause = "TablePro shut the SAP HANA helper down."
            }
        }
        writer.async { self.closeInput() }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.shutdownGrace) { [weak self] in
            self?.stop(cause: nil)
        }
    }

    func stop(cause: String?) {
        let isRunning = stateLock.withLock { () -> Bool in
            if stopCause == nil {
                stopCause = cause
            }
            return process.isRunning
        }
        guard isRunning else { return }
        kill(processIdentifier, SIGKILL)
    }

    private func register(
        _ pending: HanaHelperPendingCall,
        opcode: HanaHelperOpcode,
        body: Data
    ) throws -> HanaHelperRequest {
        try stateLock.withLock {
            if let deathFailure {
                throw deathFailure
            }
            let id = lastFrameID &+ 1
            let request: HanaHelperRequest
            do {
                request = try HanaHelperRequest(id: id, opcode: opcode, body: body)
            } catch let error as HanaHelperFrameError {
                throw error.failure
            }
            lastFrameID = id
            pendingCalls[id] = pending
            return request
        }
    }

    private func send(_ request: HanaHelperRequest) {
        guard !isInputClosed else { return }
        do {
            try HanaHelperPipe.write(request.header.encoded, to: input.fileDescriptor)
            try HanaHelperPipe.write(request.body, to: input.fileDescriptor)
        } catch {
            let code = (error as? POSIXError)?.code.rawValue ?? 0
            Self.logger.error("Writing to SAP HANA helper \(self.processIdentifier) failed with errno \(code)")
            stop(cause: nil)
        }
    }

    private func closeInput() {
        guard !isInputClosed else { return }
        isInputClosed = true
        try? input.close()
    }

    private func awaitHandshake(within deadline: TimeInterval) throws {
        let outcome: Result<Data, HanaBridgeFailure>
        if let answered = handshake.wait(until: .now() + deadline) {
            outcome = answered
        } else {
            stop(cause: "The SAP HANA helper did not answer within \(Int(deadline)) seconds of starting.")
            outcome = handshake.wait()
        }
        if case .failure(let failure) = outcome {
            throw failure
        }
    }

    private func startThreads(errorHandle: FileHandle) {
        let errorStream = errorStream
        let processIdentifier = processIdentifier
        let errorDrain = Thread {
            errorStream.drain(errorHandle, helper: processIdentifier)
        }
        errorDrain.name = "com.TablePro.hana.helper.stderr"
        errorDrain.qualityOfService = .utility
        errorDrain.start()
        let reader = Thread {
            self.finish(after: self.readReplies())
        }
        reader.name = "com.TablePro.hana.helper.reader"
        reader.qualityOfService = .userInitiated
        reader.start()
    }

    private func readReplies() -> StreamEnd {
        let descriptor = output.fileDescriptor
        do {
            while true {
                let headerRead = try HanaHelperPipe.read(exactly: HanaHelperFrameHeader.byteCount, from: descriptor)
                guard case .complete(let headerBytes) = headerRead else {
                    guard case .endOfStream(let received) = headerRead, received > 0 else { return .endOfStream }
                    return .violation(.truncatedHeader(receivedByteCount: received))
                }
                let header = try HanaHelperFrameHeader(decoding: headerBytes)
                let expected = Int(header.bodyLength)
                switch try HanaHelperPipe.read(exactly: expected, from: descriptor) {
                case .complete(let body):
                    try deliver(header, body: body)
                case .endOfStream(let received):
                    return .violation(.truncatedBody(expectedByteCount: expected, receivedByteCount: received))
                }
            }
        } catch let violation as HanaHelperFrameError {
            return .violation(violation)
        } catch {
            return .readFailed((error as? POSIXError)?.code.rawValue ?? EIO)
        }
    }

    private func deliver(_ header: HanaHelperFrameHeader, body: Data) throws {
        guard isHandshaken else {
            try HanaHelperHandshake.validate(header, body: body)
            isHandshaken = true
            handshake.complete(with: .success(body))
            return
        }
        let reply = try HanaHelperReply(status: header.code, body: body)
        let pending = try stateLock.withLock { () -> HanaHelperPendingCall? in
            if let pending = pendingCalls.removeValue(forKey: header.id) {
                return pending
            }
            guard header.id != HanaHelperHandshake.frameID, header.id <= lastFrameID else {
                throw HanaHelperFrameError.unexpectedReply(id: header.id)
            }
            return nil
        }
        guard let pending else {
            Self.logger.error("SAP HANA helper \(self.processIdentifier) answered frame \(header.id), which expects no reply")
            return
        }
        pending.complete(with: reply.result)
    }

    private func finish(after end: StreamEnd) {
        switch end {
        case .endOfStream:
            break
        case .violation(let violation):
            stop(cause: "TablePro stopped the SAP HANA helper after a protocol error: \(violation.message).")
        case .readFailed(let code):
            stop(cause: "TablePro stopped the SAP HANA helper after reading its output failed with errno \(code).")
        }
        let report = exitReport()
        let lostFailure = HanaBridgeFailure(kind: .connectionLost, message: report.message)
        let violationFailure: HanaBridgeFailure?
        if case .violation(let violation) = end {
            violationFailure = violation.failure
        } else {
            violationFailure = nil
        }
        let (stranded, wasShuttingDown) = stateLock.withLock { () -> ([HanaHelperPendingCall], Bool) in
            deathFailure = lostFailure
            let stranded = Array(pendingCalls.values)
            pendingCalls.removeAll()
            return (stranded, isShuttingDown)
        }
        handshake.complete(with: .failure(violationFailure ?? HanaBridgeFailure(kind: .internalFailure, message: report.message)))
        stranded.forEach { $0.complete(with: .failure(violationFailure ?? lostFailure)) }
        writer.async { self.closeInput() }
        log(report, strandedCalls: stranded.count, wasShuttingDown: wasShuttingDown)
    }

    private func exitReport() -> HanaHelperExitReport {
        let deadline = DispatchTime.now() + Self.exitReportDeadline
        if exited.wait(timeout: deadline) == .timedOut {
            stop(cause: nil)
            _ = exited.wait(timeout: .now() + Self.exitReportDeadline)
        }
        let tail = errorStream.tailText(waitingUntil: deadline)
        let cause = stateLock.withLock { stopCause }
        return HanaHelperExitReport(termination: termination(), stopCause: cause, errorTail: tail)
    }

    private func termination() -> HanaHelperExitReport.Termination {
        guard !process.isRunning else { return .unknown }
        switch process.terminationReason {
        case .exit:
            return .exited(status: process.terminationStatus)
        case .uncaughtSignal:
            return .signalled(process.terminationStatus)
        @unknown default:
            return .unknown
        }
    }

    private func log(_ report: HanaHelperExitReport, strandedCalls: Int, wasShuttingDown: Bool) {
        guard !wasShuttingDown else {
            Self.logger.debug("SAP HANA helper \(self.processIdentifier) ended: \(report.summary, privacy: .public)")
            return
        }
        Self.logger.error(
            "SAP HANA helper \(self.processIdentifier) ended with \(strandedCalls) calls waiting: \(report.summary, privacy: .public)"
        )
        guard !report.errorTail.isEmpty else { return }
        Self.logger.error("SAP HANA helper \(self.processIdentifier) error output: \(report.errorTail, privacy: .private)")
    }
}
