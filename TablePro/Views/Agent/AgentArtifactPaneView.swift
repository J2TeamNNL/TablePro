//
//  AgentArtifactPaneView.swift
//  TablePro
//

import SwiftUI

/// What the session produced, in the inspector's column: the SQL it proposes, the steps it took,
/// the rows it got back, and the schema change a DDL statement would make.
///
/// This is what separates the surface from a wider chat window: the user checks the database's own
/// answer instead of the model's sentence about it. The segments are empty until the phase that
/// fills them; each one says what will appear there rather than showing a blank column.
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
    @State private var segment: AgentArtifactSegment = .sql

    internal var body: some View {
        VStack(spacing: 0) {
            picker
            Divider()
            EmptyStateView(
                icon: segment.icon,
                title: segment.emptyTitle,
                description: segment.emptyDescription
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
