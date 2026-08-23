//
//  MainWindowToolbar+ContentMode.swift
//  TablePro
//

import AppKit

/// The control that switches what the window shows: the object browser and editor, or the
/// assistant. It says **Assistant**, never "Agent". `AIChatMode` already has an `.agent` case in
/// the composer meaning "which tools may run", and two controls both labelled Agent, meaning
/// different things, is a support ticket generator.
extension MainWindowToolbar {
    private static let contentModeSegments: [ConnectionWorkspaceContentMode] = [.browse, .assistant]

    /// `.selectOne` is what makes this a one-of-N segmented control, the same shape the sidebar
    /// toggle uses. Not navigational: `isNavigational` lets AppKit lift an item out of its declared
    /// slot and pin it to the leading edge of the content title area, which is where back, forward
    /// and the connection chip already are.
    internal static func makeContentModeGroup(target: AnyObject?, action: Selector) -> NSToolbarItemGroup {
        let labels = [String(localized: "Browse"), String(localized: "Assistant")]
        /// The label goes on the image too, not only in `labels`. An expanded group builds its own
        /// segmented control and takes each segment's accessibility name from the image's
        /// `accessibilityDescription`, so a nil one leaves VoiceOver reading the SF Symbol name:
        /// the window's sidebar toggle announces itself as "List" and "favorite" for exactly this
        /// reason.
        let images = zip(["tablecells", "sparkles"], labels).compactMap {
            NSImage(systemSymbolName: $0.0, accessibilityDescription: $0.1)
        }
        let group = NSToolbarItemGroup(
            itemIdentifier: contentMode,
            images: images,
            selectionMode: .selectOne,
            labels: labels,
            target: target,
            action: action
        )
        group.label = String(localized: "Mode")
        group.paletteLabel = group.label
        group.controlRepresentation = .expanded
        return group
    }

    /// Only the item actually going into the toolbar may claim `contentModeGroup`. A Customize
    /// Toolbar palette copy that took the slot would leave every later sync writing into a
    /// discarded group, which is the bug the sidebar toggle's own `claimsSlot` exists to prevent.
    internal func makeContentModeItem(claimsSlot: Bool) -> NSToolbarItem {
        let group = Self.makeContentModeGroup(target: self, action: #selector(contentModeSegmentChanged(_:)))
        bindMenuForm(action: #selector(contentModeSegmentChanged(_:)), to: Self.contentMode)
        guard claimsSlot else { return group }
        contentModeGroup = group
        syncContentModeSelection()
        return group
    }

    /// `@objc` does not type-check the sender, and this action is reachable from the overflow menu
    /// as well as from the control, where AppKit sends an `NSMenuItem` that has no `selectedIndex`.
    @objc fileprivate func contentModeSegmentChanged(_ sender: Any?) {
        guard let group = sender as? NSToolbarItemGroup else { return }
        let index = group.selectedIndex
        guard Self.contentModeSegments.indices.contains(index) else { return }
        coordinator?.splitViewController?.setContentMode(Self.contentModeSegments[index])
    }

    /// Pushed from the split view controller when the mode or the connection on screen changes,
    /// rather than observed. A view-backed group's subitems are never sent `validate()`, so there
    /// is no validation pass to piggyback on.
    internal func syncContentModeSelection() {
        guard let group = contentModeGroup, let coordinator else { return }
        let mode = coordinator.splitViewController?.contentMode ?? .browse
        group.selectedIndex = Self.contentModeSegments.firstIndex(of: mode) ?? 0
    }
}
