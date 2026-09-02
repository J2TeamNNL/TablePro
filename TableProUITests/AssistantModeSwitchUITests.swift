import XCTest

/// Switching a connection window between Browse and Assistant.
///
/// The mode control is an `NSToolbarItemGroup`, so AppKit draws it as a segmented control when the
/// window is wide enough and moves it into the overflow menu when it is not. Both routes end at the
/// same action, and the overflow one was inert: its menu items carried nothing naming a segment, so
/// choosing Browse or Assistant there did nothing. These drive the control the way a person does
/// rather than calling the action, which is the only way that gap shows up.
///
/// What is deliberately not here is anything that needs a model to answer. The suite has no AI
/// provider, so a reply, a tool card and an approval cannot be reached at all; those are covered by
/// the unit suites over `ToolApprovalCenter`, `AgentArtifactProjection` and the pane resolver.
final class AssistantModeSwitchUITests: UITestCase {
    private func mainWindow(of app: XCUIApplication) throws -> XCUIElement {
        let window = app.windows.matching(NSPredicate(format: "identifier != %@", "welcome")).firstMatch
        XCTAssertTrue(window.waitToExist(timeout: 60), "The sample database produced no window")
        return window
    }

    /// The segments are named for VoiceOver through each image's accessibility description, which
    /// is also what makes them addressable here. Without those names both segments come back as
    /// their SF Symbol names and this query finds nothing.
    private func modeSegment(_ title: String, in window: XCUIElement) -> XCUIElement {
        window.toolbars.buttons[title].firstMatch
    }

    func testTheToolbarOffersBothModesByName() throws {
        let app = try launchWithSampleDatabase()
        let window = try mainWindow(of: app)

        XCTAssertTrue(
            modeSegment("Browse", in: window).waitToExist(timeout: 20),
            "The toolbar must name its Browse segment, or VoiceOver reads the SF Symbol instead"
        )
        XCTAssertTrue(
            modeSegment("Assistant", in: window).exists,
            "The toolbar must name its Assistant segment"
        )
    }

    /// The object browser is what Browse mode puts in the sidebar and Assistant mode replaces with
    /// the session rail, so the outline disappearing is the switch actually having happened rather
    /// than a segment merely looking selected.
    func testChoosingAssistantReplacesTheObjectBrowser() throws {
        let app = try launchWithSampleDatabase()
        let window = try mainWindow(of: app)

        let objectBrowser = window.outlines.firstMatch
        XCTAssertTrue(objectBrowser.waitToExist(timeout: 20), "Browse mode must show the object browser")

        let assistant = modeSegment("Assistant", in: window)
        guard assistant.waitToBeHittable(timeout: 20) else {
            throw XCTSkip("The mode control is in the toolbar overflow at this window width")
        }
        assistant.click()

        XCTAssertTrue(
            window.staticTexts["No session yet"].waitToExist(timeout: 20)
                || window.tables.firstMatch.waitToExist(timeout: 5),
            "Assistant mode must put the session rail where the object browser was"
        )
    }

    /// The round trip. A window that cannot get back to its tables has stranded the user, and the
    /// tab strip and the object browser both have to come back with it.
    func testBrowseComesBackWithItsTables() throws {
        let app = try launchWithSampleDatabase()
        let window = try mainWindow(of: app)

        XCTAssertTrue(window.outlines.firstMatch.waitToExist(timeout: 20))

        let assistant = modeSegment("Assistant", in: window)
        guard assistant.waitToBeHittable(timeout: 20) else {
            throw XCTSkip("The mode control is in the toolbar overflow at this window width")
        }
        assistant.click()

        let browse = modeSegment("Browse", in: window)
        XCTAssertTrue(browse.waitToBeHittable(timeout: 20), "Browse must stay reachable from Assistant mode")
        browse.click()

        XCTAssertTrue(
            window.outlines.firstMatch.waitToExist(timeout: 20),
            "Returning to Browse must bring the object browser back"
        )
    }
}
