//
//  WelcomeAgentPanel.swift
//  TablePro
//

import SwiftUI

/// The welcome window's second way in: describe the job and land in Assistant mode, without opening
/// the object browser first.
///
/// A per-connection action, not an app mode. **Browse database** is still what `Return` and a double
/// click do in the list, so nothing about the existing way in changes; this is a second action on the
/// connection already selected.
///
/// Sessions already running or stopped are listed underneath, which is where a session that outlived
/// its window becomes reachable. Read straight from the registry rather than folded into the
/// connection tree: `treeItems` is rebuilt from `connections` on every mutation, and a session list
/// inside it would be rebuilt with it and would have to be kept in step by hand.
internal struct WelcomeAgentPanel: View {
    internal let registry: AgentSessionRegistry
    internal let selectedConnection: DatabaseConnection?
    internal let onBrowse: (DatabaseConnection) -> Void
    internal let onAsk: (DatabaseConnection, String) -> Void
    internal let onOpenSession: (AgentSession) -> Void

    @State private var prompt: String = ""
    @FocusState private var promptFocused: Bool

    private var sessions: [AgentSession] {
        registry.sessions.sorted { $0.updatedAt > $1.updatedAt }
    }

    internal var body: some View {
        VStack(spacing: 0) {
            if !sessions.isEmpty {
                Divider()
                sessionList
            }
            if let selectedConnection {
                Divider()
                composer(selectedConnection)
            }
        }
        .background(.bar)
    }

    private func composer(_ connection: DatabaseConnection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ConnectionTypeIcon(type: connection.type)
                    .frame(width: 14, height: 14)
                Text(connection.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Spacer()
                Button(String(localized: "Browse database")) {
                    onBrowse(connection)
                }
                .buttonStyle(.link)
                .font(.caption)
            }

            HStack(spacing: 8) {
                TextField(
                    String(localized: "Ask the assistant"),
                    text: $prompt,
                    axis: .vertical
                )
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .focused($promptFocused)
                .onSubmit { ask(connection) }

                Button {
                    ask(connection)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(trimmedPrompt.isEmpty)
                .help(String(localized: "Ask the assistant"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "Sessions"))
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(sessions) { session in
                        Button {
                            onOpenSession(session)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: session.status.icon)
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 14)
                                Text(session.displayTitle)
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text(session.status.localizedTitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 3)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            String(
                                format: String(localized: "%1$@, %2$@"),
                                session.displayTitle,
                                session.status.localizedTitle
                            )
                        )
                    }
                }
                .padding(.bottom, 6)
            }
            .frame(maxHeight: 120)
        }
    }

    private var trimmedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The field is cleared before the launch is dispatched. The window closes as the connection
    /// opens, and text left behind would come back the next time the welcome window appeared.
    private func ask(_ connection: DatabaseConnection) {
        let text = trimmedPrompt
        guard !text.isEmpty else { return }
        prompt = ""
        promptFocused = false
        onAsk(connection, text)
    }
}
