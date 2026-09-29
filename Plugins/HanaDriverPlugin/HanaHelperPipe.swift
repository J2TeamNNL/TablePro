import Darwin
import Foundation

enum HanaHelperPipeRead: Equatable, Sendable {
    case complete(Data)
    case endOfStream(receivedByteCount: Int)
}

enum HanaHelperPipe {
    static func suppressBrokenPipeSignal(on descriptor: Int32) throws {
        guard fcntl(descriptor, F_SETNOSIGPIPE, 1) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    static func write(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { buffer in
            guard let start = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(descriptor, start + offset, buffer.count - offset)
                if written >= 0 {
                    offset += written
                    continue
                }
                try throwUnlessInterrupted(errno)
            }
        }
    }

    static func read(exactly count: Int, from descriptor: Int32) throws -> HanaHelperPipeRead {
        guard count > 0 else { return .complete(Data()) }
        var bytes = Data(count: count)
        let received = try bytes.withUnsafeMutableBytes { buffer -> Int in
            guard let start = buffer.baseAddress else { return 0 }
            var offset = 0
            while offset < count {
                let chunk = Darwin.read(descriptor, start + offset, count - offset)
                if chunk > 0 {
                    offset += chunk
                    continue
                }
                if chunk == 0 {
                    return offset
                }
                try throwUnlessInterrupted(errno)
            }
            return offset
        }
        guard received == count else { return .endOfStream(receivedByteCount: received) }
        return .complete(bytes)
    }

    private static func throwUnlessInterrupted(_ failure: Int32) throws {
        guard failure == EINTR else {
            throw POSIXError(POSIXErrorCode(rawValue: failure) ?? .EIO)
        }
    }
}
