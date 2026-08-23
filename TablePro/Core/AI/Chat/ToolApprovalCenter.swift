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

    /// Told which session's queue changed, so the session rail can say "waiting on you" on the row
    /// it belongs to. A pull would not do: this type is a plain class and its dictionary is outside
    /// the observation graph, so a view that asked it a question would render once and never
    /// invalidate.
    var onPendingChange: (@MainActor (UUID) -> Void)?

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
            onPendingChange?(request.sessionId)
        }
    }

    func resolve(_ request: ApprovalRequestID, decision: ToolApprovalDecision) {
        guard let continuation = pending.removeValue(forKey: request) else { return }
        continuation.resume(returning: decision)
        onPendingChange?(request.sessionId)
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
        guard !owned.isEmpty else { return }
        onPendingChange?(sessionId)
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

    /// One session's outstanding requests. The unscoped `hasPending` above is the only question the
    /// center could answer before, and answering it for a rail would mark every session "waiting on
    /// you" whenever any one of them was.
    func pendingRequests(for sessionId: UUID) -> [ApprovalRequestID] {
        pending.keys.filter { $0.sessionId == sessionId }
    }
}
