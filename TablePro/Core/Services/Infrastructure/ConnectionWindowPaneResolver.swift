//
//  ConnectionWindowPaneResolver.swift
//  TablePro
//

import Foundation

internal enum ConnectionWindowPane: Equatable {
    case connecting
    case unavailable(ConnectionUnavailableReason)
    case content
    case empty
}

internal enum ConnectionWindowPaneResolver {
    internal static func pane(
        phase: ConnectionWindowPhase,
        hasConnection: Bool,
        hasRenderableSession: Bool
    ) -> ConnectionWindowPane {
        switch phase {
        case .closing:
            return .empty
        case .connected:
            return hasRenderableSession ? .content : .empty
        case .idle:
            if hasRenderableSession { return .content }
            return hasConnection ? .unavailable(.notConnected) : .empty
        case .connecting:
            return hasConnection ? .connecting : .empty
        case .unavailable(let reason):
            return hasConnection ? .unavailable(reason) : .empty
        }
    }

    /// A sidebar and an inspector with nothing to put in them are not chrome, they are two empty
    /// columns that promise a session the window does not have yet.
    ///
    /// Assistant mode is the exception while a connection is being established or has failed. A
    /// prompt typed at Welcome lives on the session, not on the window, so there is content to show
    /// before any database answers: the transcript and the composer. The sidebar and the inspector
    /// still go, because a session rail and a result pane have nothing to say yet.
    internal static func hidesChrome(
        for pane: ConnectionWindowPane,
        mode: ConnectionWorkspaceContentMode = .browse
    ) -> Bool {
        switch pane {
        case .content:
            return false
        case .connecting, .unavailable:
            return mode != .assistant
        case .empty:
            return true
        }
    }

    /// Whether the detail pane carries the pre-connect assistant surface rather than the connecting
    /// or failure view. Read by the pane builder, so the two decisions cannot drift: a mode that
    /// keeps its chrome hidden and mounts no content would leave the window blank.
    internal static func showsPreConnectAssistant(
        for pane: ConnectionWindowPane,
        mode: ConnectionWorkspaceContentMode
    ) -> Bool {
        guard mode == .assistant else { return false }
        switch pane {
        case .connecting, .unavailable:
            return true
        case .content, .empty:
            return false
        }
    }

    /// The tab strip's band is a list of tabs, so it appears only when there is a list worth
    /// showing: content behind it, and more than one tab in it. A window with a single tab keeps
    /// the chrome it always had, which is what the system does too.
    ///
    /// Assistant mode shows no editor tabs at all, so the band stays down however many the
    /// connection has open. They are not closed, and returning to browse mode brings them back
    /// along with the strip.
    internal static func showsTabStrip(
        for pane: ConnectionWindowPane,
        tabCount: Int,
        mode: ConnectionWorkspaceContentMode = .browse
    ) -> Bool {
        guard mode == .browse else { return false }
        return pane == .content && tabCount > 1
    }
}
