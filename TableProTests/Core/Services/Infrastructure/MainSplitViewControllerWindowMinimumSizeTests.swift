import AppKit
import Testing

@testable import TablePro

@Suite("MainSplitViewController window minimum size")
@MainActor
struct MainSplitViewControllerWindowMinimumSizeTests {
    @Test("Uses all visible pane minimums when the inspector is shown")
    func includesVisibleInspectorPane() {
        let size = MainSplitViewController.resolvedContentMinSize(
            base: NSSize(width: 720, height: 448),
            panes: [
                .init(minimumThickness: 280, isCollapsed: false),
                .init(minimumThickness: 400, isCollapsed: false),
                .init(minimumThickness: 270, isCollapsed: false)
            ],
            dividerThickness: 2
        )

        #expect(size.width == 954)
        #expect(size.height == 448)
    }

    @Test("Keeps the base width floor when the inspector is hidden")
    func keepsBaseWidthWhenInspectorHidden() {
        let size = MainSplitViewController.resolvedContentMinSize(
            base: NSSize(width: 720, height: 448),
            panes: [
                .init(minimumThickness: 280, isCollapsed: false),
                .init(minimumThickness: 400, isCollapsed: false),
                .init(minimumThickness: 270, isCollapsed: true)
            ],
            dividerThickness: 2
        )

        #expect(size.width == 720)
        #expect(size.height == 448)
    }

    @Test("Relaxes to the base width when only detail and inspector remain")
    func keepsBaseWidthWithSidebarCollapsed() {
        let size = MainSplitViewController.resolvedContentMinSize(
            base: NSSize(width: 720, height: 448),
            panes: [
                .init(minimumThickness: 280, isCollapsed: true),
                .init(minimumThickness: 400, isCollapsed: false),
                .init(minimumThickness: 270, isCollapsed: false)
            ],
            dividerThickness: 2
        )

        #expect(size.width == 720)
        #expect(size.height == 448)
    }
}
