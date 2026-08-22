//
//  ToolApprovalCenter.swift
//  TablePro
//

import Foundation
import os

enum ToolApprovalDecision: Sendable {
    case run
    case alwaysAllow
    case cancel
}

/// Where a tool call waits for a human.
///
/// Keyed by `ApprovalRequestID`, not by the provider's tool-use string. That string is the
/// provider's to choose and several of them emit `call_0`, `call_1`, so two sessions streaming at
/// once produced the same key: `awaitDecision` resumed the earlier session's continuation with
/// `.cancel`, and `resolve` popped whichever continuation happened to be in the dictionary with no
/// check that the decision belonged to it.
@MainActor
final class ToolApprovalCenter {
    static let shared = ToolApprovalCenter()

    nonisolated private static let logger = Logger(subsystem: "com.TablePro", category: "ToolApprovalCenter")

    private var pending: [ApprovalRequestID: CheckedContinuation<ToolApprovalDecision, Never>] = [:]

    func awaitDecision(for request: ApprovalRequestID) async -> ToolApprovalDecision {
        await withCheckedContinuation { continuation in
            if let existing = pending[request] {
                Self.logger.warning(
                    """
                    Duplicate awaitDecision for tool use id \(request.toolUseId, privacy: .public) \
                    in session \(request.sessionId, privacy: .public); cancelling prior continuation
                    """
                )
                existing.resume(returning: .cancel)
            }
            pending[request] = continuation
        }
    }

    func resolve(_ request: ApprovalRequestID, decision: ToolApprovalDecision) {
        guard let continuation = pending.removeValue(forKey: request) else { return }
        continuation.resume(returning: decision)
    }

    /// Cancels one session's pending approvals and leaves every other session's alone. This is what
    /// Stop Generating and a session teardown reach for: the unscoped sibling below would have one
    /// session's Stop cancel the approval another session is holding a card open for.
    func cancelAll(sessionId: UUID) {
        let owned = pending.filter { $0.key.sessionId == sessionId }
        for (request, _) in owned {
            pending.removeValue(forKey: request)
        }
        for (_, continuation) in owned {
            continuation.resume(returning: .cancel)
        }
    }

    /// App teardown only. Every other caller wants the session-scoped one above.
    func cancelAll() {
        let snapshot = pending
        pending.removeAll()
        for (_, continuation) in snapshot {
            continuation.resume(returning: .cancel)
        }
    }

    var hasPending: Bool { !pending.isEmpty }

    func hasPending(sessionId: UUID) -> Bool {
        pending.keys.contains { $0.sessionId == sessionId }
    }
}
