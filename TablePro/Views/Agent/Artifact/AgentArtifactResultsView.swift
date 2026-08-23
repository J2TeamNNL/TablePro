//
//  AgentArtifactResultsView.swift
//  TablePro
//

import SwiftUI

/// What each query the session ran actually returned: the rows, the count, how long it took, and the
/// plan when the session asked for one.
///
/// This is the segment that separates the surface from a wider chat window. The model's sentence
/// about a result and the result are two different things, and only one of them came from the
/// database.
internal struct AgentArtifactResultsView: View {
    internal let runs: [QueryRun]
    internal let connectionId: UUID?

    internal var body: some View {
        List {
            ForEach(runs) { run in
                AgentArtifactRunRow(run: run, connectionId: connectionId)
            }
        }
        .listStyle(.inset)
    }
}

/// One run. The payload is decoded here rather than when the artifact was built, so a session with a
/// hundred results decodes only the handful of rows on screen.
private struct AgentArtifactRunRow: View {
    let run: QueryRun
    let connectionId: UUID?

    private var summary: QueryRunSummary? { QueryRunSummary.decode(run.resultJSON) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(run.sql)
                .font(.caption)
                .fontDesign(.monospaced)
                .textSelection(.enabled)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let summary {
                metrics(summary)
                if !summary.columns.isEmpty, !summary.rows.isEmpty {
                    rowTable(summary)
                }
                if summary.rowCount > summary.rows.count {
                    truncationNotice(summary)
                }
                if let statusMessage = summary.statusMessage {
                    Text(statusMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(String(localized: "This result could not be read back."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            planSection
        }
        .padding(.vertical, 4)
    }

    private func metrics(_ summary: QueryRunSummary) -> some View {
        HStack(spacing: 10) {
            Label(
                String(format: String(localized: "%d rows"), summary.rowCount),
                systemImage: "tablecells"
            )
            if summary.rowsAffected > 0 {
                Label(
                    String(format: String(localized: "%d affected"), summary.rowsAffected),
                    systemImage: "pencil"
                )
            }
            if let duration = summary.durationMs {
                Label(
                    String(format: String(localized: "%.0f ms"), duration),
                    systemImage: "clock"
                )
            }
            Spacer()
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
    }

    private func rowTable(_ summary: QueryRunSummary) -> some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 12) {
                    ForEach(Array(summary.columns.enumerated()), id: \.offset) { column in
                        Text(column.element)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .frame(minWidth: 60, alignment: .leading)
                    }
                }
                Divider()
                ForEach(Array(summary.rows.enumerated()), id: \.offset) { row in
                    HStack(spacing: 12) {
                        ForEach(Array(row.element.enumerated()), id: \.offset) { cell in
                            Text(cell.element)
                                .font(.caption2)
                                .fontDesign(.monospaced)
                                .lineLimit(1)
                                .frame(minWidth: 60, alignment: .leading)
                        }
                    }
                }
            }
            .padding(6)
        }
        .frame(maxHeight: 220)
        .background(
            RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    /// The pane shows a window onto a large result and says so, with the way to the whole thing
    /// alongside. Rendering every row here would put the result's layout cost in the same pass as the
    /// conversation's.
    private func truncationNotice(_ summary: QueryRunSummary) -> some View {
        HStack(spacing: 8) {
            Text(
                String(
                    format: String(localized: "Showing %1$d of %2$d rows."),
                    summary.rows.count,
                    summary.rowCount
                )
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            if let connectionId {
                Button(String(localized: "Open as Query")) {
                    WindowManager.shared.openTab(
                        payload: EditorTabPayload(
                            connectionId: connectionId,
                            tabType: .query,
                            initialQuery: run.sql,
                            forcesNewTab: true
                        )
                    )
                }
                .buttonStyle(.link)
                .font(.caption2)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var planSection: some View {
        if let planText = run.planText {
            DisclosureGroup(String(localized: "Query plan")) {
                Text(planText)
                    .font(.caption2)
                    .fontDesign(.monospaced)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.caption)
        }
    }
}
