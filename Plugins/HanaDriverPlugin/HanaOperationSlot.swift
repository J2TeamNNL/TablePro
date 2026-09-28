import Foundation

struct HanaOperationTicket: Equatable, Sendable {
    let session: UInt64
    let operation: UInt64
}

final class HanaOperationSlot: @unchecked Sendable {
    private let lock = NSLock()
    private var ticket: HanaOperationTicket?
    private var isCancelled = false

    func assign(_ ticket: HanaOperationTicket) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isCancelled else { return false }
        self.ticket = ticket
        return true
    }

    func cancel() -> HanaOperationTicket? {
        lock.lock()
        defer { lock.unlock() }
        isCancelled = true
        return ticket
    }
}
