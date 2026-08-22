//
//  AgentSessionRailView.swift
//  TablePro
//

import SwiftUI

/// The sidebar's content in assistant mode: the sessions this window can show, in place of the
/// object browser.
///
/// One row for now, the session the window already has. The shape is here so the phase that adds
/// several sessions changes only where the rows come from, not what a row looks like.
internal struct AgentSessionRailView: View {
    internal let connectionName: String
    internal let statusTitle: String
    internal let hasSession: Bool

    internal var body: some View {
        if hasSession {
            List {
                Section(String(localized: "Sessions")) {
                    row
                }
            }
            .listStyle(.sidebar)
        } else {
            EmptyStateView(
                icon: "sparkles",
                title: String(localized: "No session yet"),
                description: String(localized: "Ask a question below to start one.")
            )
        }
    }

    private var row: some View {
        HStack(spacing: 8) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(connectionName)
                    .lineLimit(1)
                Text(statusTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
