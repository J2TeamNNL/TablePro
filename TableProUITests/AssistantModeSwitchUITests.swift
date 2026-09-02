import XCTest

/// What the mode control publishes to assistive clients.
///
/// The control is an `NSToolbarItemGroup` at `.selectOne`, which AppKit publishes as a radio group
/// of radio buttons, not as buttons, and names each segment from its image's
/// `accessibilityDescription`. Both facts are load-bearing: a nil description leaves VoiceOver
/// reading the SF Symbol name, which is what the window's own sidebar toggle still does ("List" and
/// "favorite"), and querying `buttons` finds nothing at all.
///
/// **Switching mode is not driven here, because XCUITest cannot drive it.** Measured: the Assistant
/// segment reports `exists` and `isHittable`, and `click()` leaves `isSelected` false and the window
/// unchanged. AppKit does not route a synthetic click to a segment inside a toolbar item group, and
/// the mode has no menu command to reach it by instead. What the switch does is covered without a
/// pointer: `ConnectionWindowPaneResolverTests` over the pane and chrome decisions,
/// `MainWindowToolbarContentModeTests` over the control and its overflow menu form, and
/// `MainWindowToolbarValidationTests.contentModeFollowsTheSession` over its validation.
@MainActor
final class AssistantModeSwitchUITests: UITestCase {
    private func mainWindow(of app: XCUIApplication) throws -> XCUIElement {
        let window = app.windows.matching(NSPredicate(format: "identifier != %@", "welcome")).firstMatch
        XCTAssertTrue(window.waitToExist(timeout: 60), "The sample database produced no window")
        return window
    }

    func testTheToolbarNamesBothModes() throws {
        let app = try launchWithSampleDatabase()
        let window = try mainWindow(of: app)

        XCTAssertTrue(
            window.toolbars.radioButtons["Browse"].firstMatch.waitToExist(timeout: 20),
            "The toolbar must name its Browse segment, or VoiceOver reads the SF Symbol instead"
        )
        XCTAssertTrue(
            window.toolbars.radioButtons["Assistant"].firstMatch.exists,
            "The toolbar must name its Assistant segment"
        )
    }

    /// One control, one of N. A group that published two independent buttons would let a window be
    /// in both modes at once as far as an assistive client could tell.
    func testTheModeSegmentsAreOneRadioGroup() throws {
        let app = try launchWithSampleDatabase()
        let window = try mainWindow(of: app)

        XCTAssertTrue(window.toolbars.radioButtons["Browse"].firstMatch.waitToExist(timeout: 20))
        XCTAssertEqual(
            window.toolbars.radioButtons.matching(NSPredicate(format: "label IN %@", ["Browse", "Assistant"])).count,
            2,
            "Browse and Assistant must be the two segments of one control"
        )
    }
}
