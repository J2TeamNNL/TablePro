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
        applyContentMode(of: workspace)
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

    /// One row for the session this window already has. The phase that adds several sessions
    /// changes where the rows come from and leaves the row itself alone.
    @ViewBuilder
    func buildAgentSessionRailView(for workspace: ConnectionWorkspace) -> some View {
        AgentSessionRailView(
            connectionName: workspace.connection?.name ?? String(localized: "Connection"),
            statusTitle: Self.sessionStatusTitle(phase: workspace.phase),
            hasSession: workspace.session != nil
        )
    }

    @ViewBuilder
    func buildAgentConversationView(for workspace: ConnectionWorkspace) -> some View {
        if let session = workspace.session, let rightPanelState = workspace.rightPanelState {
            let context = rightPanelState.inspectorContext
            AgentConversationView(
                connection: session.connection,
                currentQuery: context.currentQuery,
                queryResults: context.queryResults,
                viewModel: rightPanelState.aiViewModel
            )
            .environment(\.commandActions, workspace.sessionState?.coordinator.commandActions)
        } else {
            Color.clear
        }
    }

    /// Derived from the window phase for now. The phase that gives a session its own status
    /// replaces this with the session's, which can say things a connection's health cannot:
    /// running, waiting on you, queued behind another session's provider.
    static func sessionStatusTitle(phase: ConnectionWindowPhase) -> String {
        switch phase {
        case .connected:
            return String(localized: "Ready")
        case .connecting:
            return String(localized: "Connecting")
        case .idle:
            return String(localized: "Not connected")
        case .unavailable:
            return String(localized: "Unavailable")
        case .closing:
            return String(localized: "Closing")
        }
    }
}
