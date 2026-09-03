import XCTest

/// Switching a connection window between Browse and Assistant, driven through **View > Mode**.
///
/// Not through the toolbar's segmented control, for two reasons that both came out of measurement.
/// XCUITest cannot work it: the group publishes as a radio group of radio buttons, and `click()` on
/// a segment leaves `isSelected` false and the window unchanged, because AppKit does not route a
/// synthetic click to a segment inside a toolbar item group. And the runner's screen is 1024x768,
/// so a window there is narrow enough that the control collapses into the toolbar's overflow menu
/// and the segments do not exist at all: an earlier version of this suite asserted on them and
/// failed on CI for that reason while passing on any real display.
///
/// The menu command has neither problem. It is what a keyboard user reaches for, it exists at every
/// window width, and a menu item is something XCUITest can actually click, which is what makes the
/// switch itself testable rather than only its chrome.
@MainActor
final class AssistantModeSwitchUITests: UITestCase {
    private func mainWindow(of app: XCUIApplication) throws -> XCUIElement {
        let window = app.windows.matching(NSPredicate(format: "identifier != %@", "welcome")).firstMatch
        XCTAssertTrue(window.waitToExist(timeout: 60), "The sample database produced no window")
        return window
    }

    /// Walks View > Mode rather than typing a shortcut, because the command deliberately has none.
    private func chooseMode(_ title: String, in app: XCUIApplication) {
        let viewMenu = app.menuBars.menuBarItems["View"]
        XCTAssertTrue(viewMenu.waitToExist(timeout: 10), "The View menu must exist")
        viewMenu.click()

        let modeItem = app.menuBars.menuItems["Mode"]
        XCTAssertTrue(modeItem.waitToExist(timeout: 10), "View > Mode must exist")
        XCTAssertTrue(modeItem.waitToBeHittable(timeout: 10), "View > Mode must be reachable")
        modeItem.click()

        let item = app.menuBars.menuItems[title]
        XCTAssertTrue(item.waitToExist(timeout: 10), "View > Mode > \(title) must exist")
        XCTAssertTrue(item.waitToBeHittable(timeout: 10), "View > Mode > \(title) must be clickable")
        item.click()
    }

    func testTheModeCommandsAreInTheViewMenu() throws {
        let app = try launchWithSampleDatabase()
        _ = try mainWindow(of: app)

        app.menuBars.menuBarItems["View"].click()
        let modeItem = app.menuBars.menuItems["Mode"]
        XCTAssertTrue(modeItem.waitToExist(timeout: 10), "View > Mode must exist")
        modeItem.click()

        XCTAssertTrue(
            app.menuBars.menuItems["Browse"].waitToExist(timeout: 10),
            "View > Mode must offer Browse"
        )
        XCTAssertTrue(
            app.menuBars.menuItems["Assistant"].exists,
            "View > Mode must offer Assistant"
        )
    }

    /// The object browser is what Browse mode puts in the sidebar and Assistant mode replaces with
    /// the session rail, so the outline going is the switch actually having happened rather than a
    /// menu item merely being clickable.
    func testChoosingAssistantReplacesTheObjectBrowser() throws {
        let app = try launchWithSampleDatabase()
        let window = try mainWindow(of: app)

        XCTAssertTrue(window.outlines.firstMatch.waitToExist(timeout: 20), "Browse mode shows the object browser")

        chooseMode("Assistant", in: app)

        XCTAssertTrue(
            UITestPoll.until(timeout: 20) { !window.outlines.firstMatch.exists },
            "Assistant mode must take the object browser out of the sidebar"
        )
    }

    /// The round trip. A window that cannot get back to its tables has stranded the user.
    func testBrowseComesBackWithItsTables() throws {
        let app = try launchWithSampleDatabase()
        let window = try mainWindow(of: app)

        XCTAssertTrue(window.outlines.firstMatch.waitToExist(timeout: 20))

        chooseMode("Assistant", in: app)
        XCTAssertTrue(UITestPoll.until(timeout: 20) { !window.outlines.firstMatch.exists })

        chooseMode("Browse", in: app)

        XCTAssertTrue(
            window.outlines.firstMatch.waitToExist(timeout: 20),
            "Returning to Browse must bring the object browser back"
        )
    }
}
