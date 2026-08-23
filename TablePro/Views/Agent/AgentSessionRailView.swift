//
//  AgentSessionRailView.swift
//  TablePro
//

import SwiftUI

/// The sidebar's content in assistant mode: every session the app is holding, in place of the
/// object browser.
///
/// Sessions on the connection this window is showing come first, because that is the set the user
/// is working in; the rest are listed under their own connection's name so a session that outlived
/// its window is reachable rather than merely remembered.
internal struct AgentSessionRailView: View {
    internal let registry: AgentSessionRegistry
    internal let currentConnectionId: UUID?
    internal let selectedSessionId: UUID?
    internal let onSelect: (UUID) -> Void
    internal let onNewSession: (() -> Void)?
    internal let onRemove: (UUID) -> Void

    private var currentSessions: [AgentSession] {
        guard let currentConnectionId else { return [] }
        return registry.sessions(for: currentConnectionId).sorted { $0.createdAt < $1.createdAt }
    }

    private var otherSessions: [AgentSession] {
        registry.sessions
            .filter { $0.connectionId != currentConnectionId }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    internal var body: some View {
        if registry.sessions.isEmpty {
            EmptyStateView(
                icon: "sparkles",
                title: String(localized: "No session yet"),
                description: String(localized: "Ask a question below to start one.")
            )
        } else {
            List(selection: selectionBinding) {
                if !currentSessions.isEmpty {
                    Section(String(localized: "This Connection")) {
                        ForEach(currentSessions) { session in
                            row(session)
                        }
                    }
                }
                if !otherSessions.isEmpty {
                    Section(String(localized: "Other Connections")) {
                        ForEach(otherSessions) { session in
                            row(session)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom) { newSessionBar }
        }
    }

    /// A `List` selection writes through this rather than owning the value, so the rail always shows
    /// what the window is actually rendering. A rail with its own `@State` would keep a stale row
    /// lit after the window switched connection.
    private var selectionBinding: Binding<UUID?> {
        Binding(
            get: { selectedSessionId },
            set: { next in
                guard let next else { return }
                onSelect(next)
            }
        )
    }

    private func row(_ session: AgentSession) -> some View {
        HStack(spacing: 8) {
            Image(systemName: session.status.icon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.displayTitle)
                    .lineLimit(1)
                Text(statusLine(session))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .tag(session.id)
        .contextMenu {
            Button(String(localized: "Close Session"), role: .destructive) {
                onRemove(session.id)
            }
        }
        .accessibilityLabel(
            String(
                format: String(localized: "%1$@, %2$@"),
                session.displayTitle,
                statusLine(session)
            )
        )
    }

    /// Every row names its connection, including the ones on the connection on screen: two sessions
    /// on one connection are told apart by their titles, and a title taken from a first message says
    /// nothing about which database it ran against.
    private func statusLine(_ session: AgentSession) -> String {
        let status = session.statusDetail ?? session.status.localizedTitle
        return String(format: String(localized: "%1$@ · %2$@"), session.connectionName, status)
    }

    @ViewBuilder
    private var newSessionBar: some View {
        if let onNewSession {
            VStack(spacing: 0) {
                Divider()
                Button(action: onNewSession) {
                    Label(String(localized: "New Session"), systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(.bar)
        }
    }
}
