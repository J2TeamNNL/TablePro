//
//  TableRowView.swift
//  TablePro
//

import SwiftUI

enum TableRowLogic {
    static func iconName(for type: TableInfo.TableType) -> String {
        switch type {
        case .table:            return "tablecells"
        case .view:             return "eye"
        case .materializedView: return "square.stack.3d.up"
        case .foreignTable:     return "link"
        case .systemTable:      return "tablecells.badge.ellipsis"
        }
    }

    static func accessibilityKindLabel(for type: TableInfo.TableType) -> String {
        switch type {
        case .table:            return String(localized: "Table")
        case .view:             return String(localized: "View")
        case .materializedView: return String(localized: "Materialized View")
        case .foreignTable:     return String(localized: "Foreign Table")
        case .systemTable:      return String(localized: "System Table")
        }
    }

    static func accessibilityLabel(table: TableInfo, isPendingDelete: Bool, isPendingTruncate: Bool, isFavorite: Bool = false) -> String {
        let kind = accessibilityKindLabel(for: table.type)
        var label = String(format: String(localized: "%@: %@"), kind, table.name)
        if isPendingDelete {
            label += ", " + String(localized: "pending delete")
        } else if isPendingTruncate {
            label += ", " + String(localized: "pending truncate")
        } else if isFavorite {
            label += ", " + String(localized: "favorite")
        }
        return label
    }

    static func iconColor(table: TableInfo, isPendingDelete: Bool, isPendingTruncate: Bool) -> Color {
        if isPendingDelete { return Color(nsColor: .systemRed) }
        if isPendingTruncate { return Color(nsColor: .systemOrange) }
        switch table.type {
        case .table:            return Color(nsColor: .systemBlue)
        case .view:             return Color(nsColor: .systemPurple)
        case .materializedView: return Color(nsColor: .systemTeal)
        case .foreignTable:     return Color(nsColor: .systemIndigo)
        case .systemTable:      return Color(nsColor: .systemGray)
        }
    }

    static func textColor(isPendingDelete: Bool, isPendingTruncate: Bool) -> Color {
        if isPendingDelete { return Color(nsColor: .systemRed) }
        if isPendingTruncate { return Color(nsColor: .systemOrange) }
        return .primary
    }
}

struct TableRow: View {
    let table: TableInfo
    let isPendingTruncate: Bool
    let isPendingDelete: Bool
    var isFavorite: Bool = false
    var onToggleFavorite: (() -> Void)?

    @State private var isHovered = false

    private var iconColor: Color {
        TableRowLogic.iconColor(table: table, isPendingDelete: isPendingDelete, isPendingTruncate: isPendingTruncate)
    }

    private var textColor: Color {
        TableRowLogic.textColor(isPendingDelete: isPendingDelete, isPendingTruncate: isPendingTruncate)
    }

    var body: some View {
        HStack(spacing: 6) {
            Label {
                Text(table.name)
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(1)
                    .sidebarTint(textColor)
            } icon: {
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: TableRowLogic.iconName(for: table.type))
                        .sidebarTint(iconColor)
                        .frame(width: 14)

                    if isPendingDelete {
                        Image(systemName: "minus.circle.fill")
                            .font(.caption)
                            .sidebarTint(.red)
                            .offset(x: 4, y: 4)
                    } else if isPendingTruncate {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.caption)
                            .sidebarTint(.orange)
                            .offset(x: 4, y: 4)
                    }
                }
            }

            Spacer(minLength: 4)

            if let onToggleFavorite {
                let starVisible = isFavorite || isHovered
                Button(action: onToggleFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(isFavorite ? Color.yellow : Color.secondary)
                        .contentShape(Rectangle())
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .opacity(starVisible ? 1 : 0)
                .allowsHitTesting(starVisible)
                .accessibilityHidden(true)
                .help(isFavorite
                      ? String(localized: "Remove from Favorites")
                      : String(localized: "Add to Favorites"))
            }
        }
        .padding(.vertical, 4)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            TableRowLogic.accessibilityLabel(
                table: table,
                isPendingDelete: isPendingDelete,
                isPendingTruncate: isPendingTruncate,
                isFavorite: isFavorite
            )
        )
        .modifier(FavoriteAccessibilityAction(isFavorite: isFavorite, toggle: onToggleFavorite))
    }
}

private struct FavoriteAccessibilityAction: ViewModifier {
    let isFavorite: Bool
    let toggle: (() -> Void)?

    func body(content: Content) -> some View {
        if let toggle {
            content.accessibilityAction(
                named: isFavorite
                    ? Text("Remove from Favorites")
                    : Text("Add to Favorites"),
                toggle
            )
        } else {
            content
        }
    }
}
