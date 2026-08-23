//
//  AgentArtifactSchemaView.swift
//  TablePro
//

import SwiftUI

/// What a `CREATE`, `ALTER`, `DROP` or `TRUNCATE` the session proposed would change.
///
/// The preview is never the gate. A statement still runs only through its approval card and, when it
/// is destructive, only through `confirm_destructive_operation`. A statement the reader could not be
/// sure about shows its own SQL instead of a list, because a preview that missed a dropped column
/// would be worse than no preview.
internal struct AgentArtifactSchemaView: View {
    internal let changes: [SchemaChangePreview]

    internal var body: some View {
        List {
            ForEach(changes) { change in
                VStack(alignment: .leading, spacing: 6) {
                    header(change)
                    if change.lines.isEmpty {
                        Text(String(localized: "TablePro could not read this statement's effect. Its SQL is above."))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(change.lines) { line in
                            lineRow(line)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.inset)
    }

    private func header(_ change: SchemaChangePreview) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if let target = change.target {
                    Text(target)
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                if change.isDestructive {
                    Text(String(localized: "Destructive"))
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.red.opacity(0.15), in: Capsule())
                        .foregroundStyle(.red)
                }
                Spacer()
            }
            Text(change.sql)
                .font(.caption)
                .fontDesign(.monospaced)
                .textSelection(.enabled)
                .lineLimit(6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func lineRow(_ line: SchemaChangeLine) -> some View {
        HStack(spacing: 6) {
            Image(systemName: Self.icon(for: line.kind))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(line.isDestructive ? .red : .secondary)
                .frame(width: 12)
            Text(line.text)
                .font(.caption2)
                .fontDesign(.monospaced)
                .foregroundStyle(line.isDestructive ? .red : .primary)
            Spacer()
        }
    }

    private static func icon(for kind: SchemaChangeLine.Kind) -> String {
        switch kind {
        case .adds: return "plus.circle"
        case .removes: return "minus.circle"
        case .changes: return "arrow.triangle.2.circlepath"
        }
    }
}
