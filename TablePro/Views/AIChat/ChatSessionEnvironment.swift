//
//  ChatSessionEnvironment.swift
//  TablePro
//

import SwiftUI

private struct ChatSessionIdKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}

private struct ChatWriteFloorActiveKey: EnvironmentKey {
    static let defaultValue = false
}

internal extension EnvironmentValues {
    /// Which chat session the view is inside. Read by the approval buttons, which have to name the
    /// session their decision belongs to: a decision keyed by the provider's tool-use string alone
    /// could resolve another session's approval, because several providers emit `call_0`, `call_1`.
    ///
    /// Optional with no default session on purpose. A row rendered somewhere that has not published
    /// a session cannot say whose approval it is resolving, and the row disables itself rather than
    /// guessing.
    var chatSessionId: UUID? {
        get { self[ChatSessionIdKey.self] }
        set { self[ChatSessionIdKey.self] = newValue }
    }

    /// True when a floor rather than the connection's own level is what is asking for the
    /// confirmation. The approval card's "Always for this connection" is disabled then, because the
    /// approval path ignores a grant under a floor and nothing would be recorded: a button that
    /// looks like it turns the prompts off, and does not, is worse than no button.
    var chatWriteFloorActive: Bool {
        get { self[ChatWriteFloorActiveKey.self] }
        set { self[ChatWriteFloorActiveKey.self] = newValue }
    }
}
