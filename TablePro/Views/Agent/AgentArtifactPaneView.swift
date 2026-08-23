//
//  AgentArtifactPaneView.swift
//  TablePro
//

import SwiftUI

/// What the session produced, in the inspector's column: the SQL it proposes, the steps it took,
/// the rows it got back, and the schema change a DDL statement would make.
///
/// This is what separates the surface from a wider chat window: the user checks the database's own
/// answer instead of the model's sentence about it.
internal enum AgentArtifactSegment: String, CaseIterable, Identifiable {
    case sql
    case plan
    case results
    case schema

    internal var id: String { rawValue }

    internal var localizedTitle: String {
        switch self {
        case .sql: return String(localized: "SQL")
        case .plan: return String(localized: "Plan")
        case .results: return String(localized: "Results")
        case .schema: return String(localized: "Schema")
        }
    }

    internal var icon: String {
        switch self {
        case .sql: return "curlybraces"
        case .plan: return "list.bullet.indent"
        case .results: return "tablecells"
        case .schema: return "square.stack.3d.up"
        }
    }

    internal var emptyTitle: String {
        switch self {
        case .sql: return String(localized: "No statements yet")
        case .plan: return String(localized: "No steps yet")
        case .results: return String(localized: "No results yet")
        case .schema: return String(localized: "No schema changes")
        }
    }

    internal var emptyDescription: String {
        switch self {
        case .sql:
            return String(localized: "SQL the assistant proposes appears here, with Run and Reject on each statement.")
        case .plan:
            return String(localized: "The steps the assistant has taken appear here as it works.")
        case .results:
            return String(localized: "Rows, count, duration and the query plan appear here after a query runs.")
        case .schema:
            return String(localized: "Columns, indexes and constraints a statement would add or remove appear here.")
        }
    }
}

internal struct AgentArtifactPaneView: View {
    /// Nil before the connection is up. The pane still renders its empty states then; only the
    /// Safe Mode notice needs a connection to speak about.
    internal let connectionId: UUID?

    /// Nil before there is a session. Every segment reads its content from the session's transcript,
    /// so a pane with no session is the same as a pane with an empty one.
    internal let session: AgentSession?

    @State private var segment: AgentArtifactSegment = .sql

    internal init(connectionId: UUID? = nil, session: AgentSession? = nil) {
        self.connectionId = connectionId
        self.session = session
    }

    /// Recomputed from the transcript on every pass rather than cached beside it.
    ///
    /// The projection reads `messages` and each block's approval state, both observed, so this
    /// invalidates exactly when the session changes and can never disagree with the conversation.
    /// A stored copy would need its own invalidation and would be wrong after a restore, when the
    /// transcript arrives without any of the stream events that built it.
    private var artifact: AgentArtifact {
        guard let session else { return AgentArtifact() }
        return AgentArtifactProjection.build(
            from: session.viewModel.messages,
            connectionName: session.connectionName,
            databaseType: session.viewModel.connection?.type ?? .mysql
        )
    }

    internal var body: some View {
        VStack(spacing: 0) {
            picker
            if let connectionId {
                AssistantFloorNoticeView(connectionId: connectionId)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var content: some View {
        let artifact = artifact
        switch segment {
        case .sql:
            if artifact.statements.isEmpty {
                emptyState
            } else if let session {
                AgentArtifactSQLView(statements: artifact.statements, sessionId: session.id)
            }
        case .plan:
            if artifact.steps.isEmpty {
                emptyState
            } else {
                AgentArtifactPlanView(steps: artifact.steps)
            }
        case .results:
            if artifact.runs.isEmpty {
                emptyState
            } else {
                AgentArtifactResultsView(runs: artifact.runs, connectionId: connectionId)
            }
        case .schema:
            if artifact.schemaChanges.isEmpty {
                emptyState
            } else {
                AgentArtifactSchemaView(changes: artifact.schemaChanges)
            }
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: segment.icon,
            title: segment.emptyTitle,
            description: segment.emptyDescription
        )
    }

    private var picker: some View {
        Picker("", selection: $segment) {
            ForEach(AgentArtifactSegment.allCases) { candidate in
                Text(candidate.localizedTitle).tag(candidate)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .accessibilityLabel(String(localized: "Artifact"))
    }
}
