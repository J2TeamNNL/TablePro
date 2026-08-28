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

/// What the window's one sidebar item holds. `railOnly` is the state that exists because the
/// workspace rail and the object browser share that item and answer to different owners.
internal enum SidebarChromeMode: Equatable {
    case revealed
    case railOnly
    case hidden

    internal var showsObjectBrowser: Bool { self == .revealed }
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

    /// An object browser and an inspector with nothing to put in them are not chrome, they are two
    /// empty columns that promise a session the window does not have yet.
    ///
    /// Assistant mode is the exception while a connection is being established or has failed. A
    /// prompt typed at Welcome lives on the session, not on the window, so there is content to show
    /// before any database answers: the transcript, the session rail and the result pane.
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

    /// How much of the window's sidebar survives the pane it is standing next to.
    ///
    /// The rule above is right about the object browser and wrong about the workspace rail, which
    /// lists every connection the window hosts and belongs to the window rather than to any one of
    /// them. They share a split item because AppKit grants full-height sidebar layout to exactly one
    /// leading sidebar, so collapsing for an empty object browser took the switcher with it and left
    /// the window's other connections with no way in.
    ///
    /// Assistant mode during connect or failure is not that case: the session rail is the sidebar,
    /// so clamping to the workspace rail would hide the conversation's own list of sessions.
    internal static func sidebarChromeMode(
        for pane: ConnectionWindowPane,
        hasRail: Bool,
        mode: ConnectionWorkspaceContentMode = .browse
    ) -> SidebarChromeMode {
        guard hidesChrome(for: pane, mode: mode) else { return .revealed }
        return hasRail ? .railOnly : .hidden
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

    /// Whether the connections strip stands, given the preference that normally governs it.
    ///
    /// The preference hides a switcher the user reaches other ways: the object browser sits beside
    /// it, the tab strip runs under the toolbar, and Switch Connection is in the Database menu. A
    /// pane with no content takes every one of those with it, and the strip is then the only thing
    /// on screen pointing at the connections the window still has, so the preference stops applying
    /// for as long as that lasts. `railOnly` preserves a strip that is already up; without this
    /// nothing brings one back, and a user who had hidden it was left with a window whose every
    /// route out was a menu command or a keystroke.
    ///
    /// Closing is passed in rather than read off the pane. A window that is tearing down resolves
    /// to `empty`, but so does a workspace whose connection never resolved, and a `connected` one
    /// with no renderable session behind it, so `empty` cannot be asked which of those it is.
    /// Laying a switcher over a window that is going away and stranding a window that is not are
    /// the same mistake read from the same value.
    ///
    /// The browse-mode chrome decision is the one that answers this. Assistant mode keeps its own
    /// sidebar during connect, but a window with several connections still needs the strip when
    /// browse chrome would have gone, because that strip is how the user reaches the others.
    internal static func showsWorkspaceRail(
        preferenceEnabled: Bool,
        workspaceCount: Int,
        pane: ConnectionWindowPane,
        isClosing: Bool
    ) -> Bool {
        guard workspaceCount > 1, !isClosing else { return false }
        return preferenceEnabled || hidesChrome(for: pane)
    }
}
