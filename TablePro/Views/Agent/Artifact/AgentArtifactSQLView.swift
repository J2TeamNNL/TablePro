//
//  AgentArtifactSQLView.swift
//  TablePro
//

import SwiftUI

/// Every statement the session proposed, in order, with its state and, while it waits, **Run** and
/// **Reject**.
///
/// No "Always for this connection". A grant made here would name one statement and mean every write
/// on the connection, and the whole point of this list is that each statement is read on its own.
/// The button in the conversation card is unchanged and stays the only place a grant is offered.
internal struct AgentArtifactSQLView: View {
    internal let statements: [ProposedStatement]
    internal let sessionId: UUID

    internal var body: some View {
        List {
            ForEach(statements) { statement in
                row(statement)
            }
        }
        .listStyle(.inset)
    }

    private func row(_ statement: ProposedStatement) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: statement.state.icon)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(statement.isDestructive ? .red : .secondary)
                Text(statement.state.localizedTitle)
                    .font(.caption)
                    .fontWeight(.semibold)
                if statement.isDestructive {
                    Text(String(localized: "Destructive"))
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.red.opacity(0.15), in: Capsule())
                        .foregroundStyle(.red)
                }
                Spacer()
            }

            Text(statement.sql)
                .font(.caption)
                .fontDesign(.monospaced)
                .textSelection(.enabled)
                .lineLimit(8)
                .frame(maxWidth: .infinity, alignment: .leading)

            if statement.awaitsDecision {
                Text(
                    String(
                        format: String(localized: "Targets %@"),
                        statement.connectionName
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                decisionButtons(statement)
            } else if let detail = statement.state.detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
        }
        .padding(.vertical, 4)
    }

    private func decisionButtons(_ statement: ProposedStatement) -> some View {
        HStack(spacing: 8) {
            Button(String(localized: "Run")) {
                resolve(statement, decision: .run)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button(String(localized: "Reject")) {
                resolve(statement, decision: .cancel)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()
        }
    }

    private func resolve(_ statement: ProposedStatement, decision: ToolApprovalDecision) {
        ToolApprovalCenter.shared.resolve(
            ApprovalRequestID(sessionId: sessionId, toolUseId: statement.id),
            decision: decision
        )
    }
}
