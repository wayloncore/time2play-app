import XCTest

/// #405: every main screen at the largest text, and on iPad (the Mac workflow's iPad pass runs this file again),
/// and what a TV shows. Offline rooms where it can, so the tour doesn't depend on the network.
final class TourUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    private var device: String { UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone" }
    private let xxxl = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-t2p-name", "Sim"]

    func testLargestTextTour() {
        let app = launch(xxxl)
        XCTAssertTrue(app.textFields["room-code"].waitForExistence(timeout: 10))
        shot(app, "405-\(device)-home-xxxl")
        app.swipeUp(); app.swipeUp()
        tapWhenReady(app.buttons["offline-overdraft"])
        // with a name already, an offline room skips the picker
        if app.buttons["join-room"].waitForExistence(timeout: 5) { shot(app, "405-\(device)-name-xxxl"); app.buttons["join-room"].tap() }
        tapWhenReady(app.buttons["addbot-easy"]); sleep(1)
        app.buttons["addbot-normal"].tap(); sleep(1)
        shot(app, "405-\(device)-lobby-xxxl")
        tapWhenReady(app.buttons["start-game"])
        XCTAssertTrue(app.buttons["draw"].waitForExistence(timeout: 10))
        sleep(2)
        shot(app, "405-\(device)-overdraft-xxxl")
    }

    func testRegularTextTablesOnThisDevice() {
        let app = launch()
        XCTAssertTrue(app.textFields["room-code"].waitForExistence(timeout: 10))
        shot(app, "405-\(device)-home")
        app.swipeUp()
        tapWhenReady(app.buttons["offline-farkle"])
        let name = app.textFields["name"]
        if name.waitForExistence(timeout: 10) { name.tap(); name.typeText("Sim"); tapWhenReady(app.buttons["join-room"]) }
        tapWhenReady(app.buttons["addbot-steady"]); sleep(1)
        tapWhenReady(app.buttons["start-game"])
        let roll = app.buttons["roll"]
        XCTAssertTrue(waitEnabled(roll, 60))
        roll.tap(); sleep(3)
        shot(app, "405-\(device)-hot-dice")
    }

    /// What a TV shows for a live room: the room's public table, never a hand.
    func testWhatTheTVShows() throws {
        let code = try startRoom("overdraft")
        let app = launch()
        let field = app.textFields["room-code"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap(); field.typeText(code)
        tapWhenReady(app.buttons["Join \(code)"])
        let name = app.textFields["name"]
        XCTAssertTrue(name.waitForExistence(timeout: 20)); name.tap(); name.typeText("Sim")
        tapWhenReady(app.buttons["join-room"])
        tapWhenReady(app.buttons["show-on-tv"], 20)
        shot(app, "405-\(device)-show-on-tv")
        tapWhenReady(app.buttons["tv-preview"])
        sleep(4)
        shot(app, "405-\(device)-tv-picture")
        tapWhenReady(app.buttons["tv-close"])
    }
}

/// #405's accessibility pass: Apple's audit (labels, hit areas, Dynamic Type, contrast) on the main screens. Each issue
/// is printed into the log as AUDIT lines and doesn't fail the run, so they're read and fixed by hand.
final class AuditUITests: XCTestCase {
    private func audit(_ app: XCUIApplication, _ screen: String) throws {
        try app.performAccessibilityAudit { issue in
            print("AUDIT \(screen) · \(issue.auditType) · \(issue.compactDescription) · \(issue.element?.debugDescription.prefix(160) ?? "")")
            return true
        }
    }

    func testAuditMainScreens() throws {
        let app = launch(["-t2p-name", "Sim"])
        XCTAssertTrue(app.textFields["room-code"].waitForExistence(timeout: 10))
        try audit(app, "home")
        tapWhenReady(app.tabBars.buttons["Library"]); sleep(2)
        try audit(app, "library")
        tapWhenReady(app.tabBars.buttons["You"])
        try audit(app, "you")
        tapWhenReady(app.tabBars.buttons["Play"])
        app.swipeUp()
        tapWhenReady(app.buttons["offline-overdraft"])
        tapWhenReady(app.buttons["addbot-easy"]); sleep(1)
        app.buttons["addbot-normal"].tap(); sleep(1)
        try audit(app, "lobby")
        tapWhenReady(app.buttons["start-game"])
        XCTAssertTrue(app.buttons["draw"].waitForExistence(timeout: 10)); sleep(2)
        try audit(app, "overdraft")
        app.buttons["leave"].tap()
        tapWhenReady(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Leave the'")).firstMatch, 5)
        app.swipeUp()
        tapWhenReady(app.buttons["offline-farkle"])
        tapWhenReady(app.buttons["addbot-steady"]); sleep(1)
        tapWhenReady(app.buttons["start-game"]); sleep(3)
        try audit(app, "hot-dice")
    }
}
