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

    @Test("Uses the pane sum when detail and inspector exceed the base floor")
    func usesPaneSumWhenItExceedsBaseWithSidebarCollapsed() {
        let size = MainSplitViewController.resolvedContentMinSize(
            base: NSSize(width: 720, height: 448),
            panes: [
                .init(minimumThickness: 280, isCollapsed: true),
                .init(minimumThickness: 400, isCollapsed: false),
                .init(minimumThickness: 400, isCollapsed: false)
            ],
            dividerThickness: 2
        )

        #expect(size.width == 802)
        #expect(size.height == 448)
    }

    @Test("Returns to the original base width after showing then hiding the inspector")
    func relaxesBackToOriginalBaseAfterInspectorCycle() {
        let originalBase = NSSize(width: 720, height: 448)

        let shownSize = MainSplitViewController.resolvedContentMinSize(
            base: originalBase,
            panes: [
                .init(minimumThickness: 280, isCollapsed: false),
                .init(minimumThickness: 400, isCollapsed: false),
                .init(minimumThickness: 270, isCollapsed: false)
            ],
            dividerThickness: 2
        )

        #expect(shownSize.width == 954)

        let hiddenSize = MainSplitViewController.resolvedContentMinSize(
            base: originalBase,
            panes: [
                .init(minimumThickness: 280, isCollapsed: false),
                .init(minimumThickness: 400, isCollapsed: false),
                .init(minimumThickness: 270, isCollapsed: true)
            ],
            dividerThickness: 2
        )

        #expect(hiddenSize.width == 720)
        #expect(hiddenSize.height == 448)
    }

    @Test("Applies the controller base constants as the runtime content floor")
    func usesControllerBaseConstantsAsFloor() {
        #expect(MainSplitViewController.baseContentMinWidth == 720)
        #expect(MainSplitViewController.baseContentMinHeight == 480)

        let base = NSSize(
            width: MainSplitViewController.baseContentMinWidth,
            height: MainSplitViewController.baseContentMinHeight
        )

        let sidebarAndDetail = MainSplitViewController.resolvedContentMinSize(
            base: base,
            panes: [
                .init(minimumThickness: 280, isCollapsed: false),
                .init(minimumThickness: 400, isCollapsed: false),
                .init(minimumThickness: 270, isCollapsed: true)
            ],
            dividerThickness: 2
        )

        #expect(sidebarAndDetail.width == MainSplitViewController.baseContentMinWidth)
        #expect(sidebarAndDetail.height == MainSplitViewController.baseContentMinHeight)

        let allPanesVisible = MainSplitViewController.resolvedContentMinSize(
            base: base,
            panes: [
                .init(minimumThickness: 280, isCollapsed: false),
                .init(minimumThickness: 400, isCollapsed: false),
                .init(minimumThickness: 270, isCollapsed: false)
            ],
            dividerThickness: 2
        )

        #expect(allPanesVisible.width == 954)
        #expect(allPanesVisible.height == MainSplitViewController.baseContentMinHeight)
    }
}
