//
//  MainSplitViewController+ContentMode.swift
//  TablePro
//

import AppKit
import SwiftUI

internal extension MainSplitViewController {
    /// The mode of the connection on screen. The toolbar's segmented control reads this to decide
    /// which segment is lit, and every window answers for its own selection.
    var contentMode: ConnectionWorkspaceContentMode {
        workspaces.selected?.contentMode ?? .browse
    }

    /// The mode-change call site the detail pane's minimum needs. Tab changes are the only other
    /// trigger and they are a browse-mode event, so nothing else would re-seed the thickness when
    /// the surface itself changes.
    ///
    /// Nothing here writes `window.frame` or forces the inspector open. `recomputeWindowMinSize()`
    /// grows a window whose frame is under the new minimum and never shrinks it back, so forcing
    /// the artifact pane open would widen the user's window permanently after one round trip.
    /// The pane ships open and stays collapsible, which is what keeps the total inside a normal
    /// window without anyone rewriting a frame.
    func setContentMode(_ mode: ConnectionWorkspaceContentMode) {
        guard let workspace = workspaces.selected, workspace.contentMode != mode else { return }
        workspace.contentMode = mode
        /// Switching to Assistant is the user action that starts a session, so the surface has a
        /// conversation to show rather than an empty rail. Creating it here rather than from the
        /// pane builder is what keeps creation out of a view body.
        if mode == .assistant {
            startSessionIfNeeded(for: workspace)
        }
        applyContentMode(of: workspace)
    }

    /// Resolves the session the surface shows, creating one if this connection has none. Nil while
    /// the connection is still dialling: `AgentSession` requires a connection record, and phase 2
    /// made that a creation-time requirement so nothing can stream without one.
    @discardableResult
    func startSessionIfNeeded(for workspace: ConnectionWorkspace) -> AgentSession? {
        guard let connection = workspace.connection else { return nil }
        let session = AgentSessionRegistry.shared.session(for: connection)
        workspace.selectedSessionId = session.id
        return session
    }

    /// The session this workspace's surface renders. The selection is per workspace, so switching
    /// connection and back returns to the session the user was reading rather than to whichever one
    /// was touched last.
    func selectedSession(of workspace: ConnectionWorkspace) -> AgentSession? {
        let registry = AgentSessionRegistry.shared
        if let selected = workspace.selectedSessionId,
           let session = registry.existingSession(id: selected) {
            return session
        }
        return registry.existingDefaultSession(for: workspace.connectionId)
    }

    /// Puts a rail row on screen. A session is pinned to its connection and the window shows one
    /// connection at a time, so a row on another connection selects that workspace first, and a row
    /// on a connection no window hosts opens one, reconnecting on the way.
    func selectSession(id: UUID) {
        guard let session = AgentSessionRegistry.shared.existingSession(id: id) else { return }
        guard let workspace = workspaces.workspace(for: session.connectionId) else {
            WindowManager.shared.openTab(
                payload: EditorTabPayload(
                    connectionId: session.connectionId,
                    intent: .restoreOrDefault
                ),
                autoConnect: true
            )
            return
        }
        workspace.selectedSessionId = id
        if workspaces.selectedConnectionId == session.connectionId {
            refreshPanes(of: workspace)
        } else {
            selectHostedConnection(session.connectionId)
        }
    }

    func toggleContentMode() {
        setContentMode(contentMode == .assistant ? .browse : .assistant)
    }

    /// Repaints one connection after its mode changed: its three panes, the detail pane's minimum,
    /// the tab strip band, and the toolbar's segment.
    func applyContentMode(of workspace: ConnectionWorkspace) {
        refreshPanes(of: workspace)
        guard workspaces.selectedConnectionId == workspace.connectionId else { return }
        updateDetailMinimumThickness(
            for: workspace.sessionState?.tabManager.selectedTab?.tabType,
            connectionId: workspace.connectionId
        )
        /// The chrome pass is what reconciles the artifact pane, the tab strip band, the toolbar's
        /// segment and the window's minimum, and it is the same pass a workspace switch and a phase
        /// change already run. Doing those four things here as well would be a second copy to keep
        /// in step.
        applyPaneChrome()
    }

    // MARK: - Assistant Panes

    @ViewBuilder
    func buildAgentSessionRailView(for workspace: ConnectionWorkspace) -> some View {
        AgentSessionRailView(
            registry: .shared,
            currentConnectionId: workspace.connectionId,
            selectedSessionId: selectedSession(of: workspace)?.id,
            onSelect: { [weak self] id in self?.selectSession(id: id) },
            onNewSession: newSessionAction(for: workspace),
            onRemove: { [weak self] id in self?.closeSession(id: id) }
        )
    }

    /// Nil while the connection has no record to attach a session to, which disables the control
    /// rather than offering a button that would silently do nothing.
    private func newSessionAction(for workspace: ConnectionWorkspace) -> (() -> Void)? {
        guard let connection = workspace.connection else { return nil }
        return { [weak self] in
            guard let self else { return }
            let session = AgentSessionRegistry.shared.makeSession(connection: connection)
            workspace.selectedSessionId = session.id
            self.refreshPanes(of: workspace)
        }
    }

    /// Ends a session and leaves the surface pointing at whatever remains on this connection, so
    /// closing the one on screen does not leave the conversation pane empty with no way back.
    func closeSession(id: UUID) {
        guard let session = AgentSessionRegistry.shared.existingSession(id: id) else { return }
        let connectionId = session.connectionId
        AgentSessionRegistry.shared.remove(id: id)
        guard let workspace = workspaces.workspace(for: connectionId) else { return }
        if workspace.selectedSessionId == id {
            workspace.selectedSessionId = nil
        }
        refreshPanes(of: workspace)
    }

    @ViewBuilder
    func buildAgentConversationView(for workspace: ConnectionWorkspace) -> some View {
        if let connectionSession = workspace.session,
           let rightPanelState = workspace.rightPanelState,
           let agentSession = selectedSession(of: workspace) {
            let context = rightPanelState.inspectorContext
            AgentConversationView(
                connection: connectionSession.connection,
                currentQuery: context.currentQuery,
                queryResults: context.queryResults,
                session: agentSession
            )
            .environment(\.commandActions, workspace.sessionState?.coordinator.commandActions)
        } else {
            Color.clear
        }
    }
}
