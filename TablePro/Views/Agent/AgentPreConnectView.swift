//
//  AgentPreConnectView.swift
//  TablePro
//

import SwiftUI

/// The assistant surface before the connection answers.
///
/// A prompt typed at the welcome window has to survive a connect that takes seconds and a connect
/// that fails, so it is visible here rather than held somewhere the user cannot see. The failure is
/// inline with **Try Again**, never an alert: the HIG rules alerts out at startup, and N restored
/// connections would mean N modals.
///
/// Deliberately smaller than `AIChatPanelView`, which takes a non-optional connection. Transcript
/// and composer only: no tool cards, no history menu, no model picker. It swaps to the real panel
/// the moment the connection is up.
internal struct AgentPreConnectView: View {
    internal let connection: DatabaseConnection
    internal let session: AgentSession
    internal let failure: ConnectionUnavailableReason?
    internal let onRetry: () -> Void
    internal let onCancel: () -> Void

    internal var body: some View {
        VStack(spacing: 0) {
            transcript
            Divider()
            status
            composer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var transcript: some View {
        if session.viewModel.messages.isEmpty {
            EmptyStateView(
                icon: "sparkles",
                title: String(
                    format: String(localized: "Opening %@"),
                    connection.name
                ),
                description: String(localized: "Your request is sent as soon as the connection is up.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(session.viewModel.messages) { turn in
                        Text(turn.plainText)
                            .font(.callout)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var status: some View {
        if let failure {
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    ConnectionUnavailablePresentation.headline(
                        reason: failure,
                        connectionName: connection.name
                    ),
                    systemImage: "exclamationmark.triangle"
                )
                .font(.callout)
                .fontWeight(.semibold)
                ForEach(
                    Array(ConnectionUnavailablePresentation.detailLines(reason: failure).enumerated()),
                    id: \.offset
                ) { line in
                    Text(line.element)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                HStack(spacing: 8) {
                    Button(
                        ConnectionUnavailablePresentation.primaryActionTitle(reason: failure),
                        action: onRetry
                    )
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        } else {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(
                    String(
                        format: String(localized: "Connecting to %@…"),
                        connection.name
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                Button(String(localized: "Cancel"), action: onCancel)
                    .buttonStyle(.link)
                    .font(.caption)
            }
            .padding(12)
        }
    }

    /// The pending prompt is shown in a disabled field rather than an editable one. Editing it would
    /// need the send path this surface does not have, and a field that takes text nothing will send
    /// is worse than one that plainly waits.
    private var composer: some View {
        VStack(spacing: 6) {
            Divider()
            HStack(alignment: .bottom, spacing: 8) {
                Text(session.pendingPrompt ?? "")
                    .font(.callout)
                    .foregroundStyle(session.pendingPrompt == nil ? .secondary : .primary)
                    .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
                    .textSelection(.enabled)
                Button {
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(true)
                .help(String(localized: "Sends once the connection is up"))
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }
}
