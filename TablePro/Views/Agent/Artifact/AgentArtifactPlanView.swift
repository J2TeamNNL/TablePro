//
//  AgentArtifactPlanView.swift
//  TablePro
//

import SwiftUI

/// The steps the session has taken, derived from its own tool calls.
///
/// Not a plan the model declared. A declared plan can drift from what happened and needs a prompt
/// contract to hold it together; a timeline read from the calls cannot say anything the session did
/// not do.
internal struct AgentArtifactPlanView: View {
    internal let steps: [AgentStep]

    internal var body: some View {
        List {
            ForEach(steps) { step in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: Self.icon(for: step.state))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Self.tint(for: step.state))
                        .frame(width: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                            .font(.caption)
                        if let detail = step.detail {
                            Text(detail)
                                .font(.caption2)
                                .fontDesign(.monospaced)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .listStyle(.inset)
    }

    private static func icon(for state: AgentStep.State) -> String {
        switch state {
        case .done: return "checkmark.circle"
        case .inFlight: return "circle.dotted"
        case .waitingOnYou: return "hand.raised"
        case .failed: return "exclamationmark.triangle"
        }
    }

    private static func tint(for state: AgentStep.State) -> Color {
        switch state {
        case .done: return .secondary
        case .inFlight: return .accentColor
        case .waitingOnYou: return .orange
        case .failed: return .red
        }
    }
}
