//
//  AssistantFloorNoticeView.swift
//  TablePro
//

import SwiftUI

/// Says that Assistant mode is holding this connection at Confirm Writes, and that it is temporary.
///
/// A user who chose Silent on purpose is about to start getting prompts, so the surface has to say
/// what changed and that leaving the mode ends it. Without the line the mode reads as the app
/// ignoring a setting they made.
internal struct AssistantFloorNoticeView: View {
    internal let connectionId: UUID

    /// Read rather than observed. The mode is UserDefaults-backed and not `@Observable`, but every
    /// mode change rewrites the three panes' `rootView`, which remounts this view, so there is
    /// nothing for an observation to add here.
    private var isActive: Bool {
        AssistantSafeModeFloor.isActive(for: connectionId)
    }

    internal var body: some View {
        if isActive {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle")
                    .symbolRenderingMode(.hierarchical)
                Text(String(localized: "Confirm Writes while in Assistant mode"))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .help(String(
                localized: "Assistant mode holds this connection at Confirm Writes, whatever its own Safe Mode level says. Switch to Browse to restore your level."
            ))
        }
    }
}
