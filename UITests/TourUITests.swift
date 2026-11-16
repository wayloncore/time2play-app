import XCTest

/// #405: every main screen at the largest text, and on iPad (the Mac workflow's iPad pass runs this file again),
/// and what a TV shows. Offline rooms where it can, so the tour doesn't depend on the network.
final class TourUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    private var device: String { UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone" }
    private let xxxl = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]

    func testLargestTextTour() {
        let app = launch(xxxl)
        XCTAssertTrue(app.textFields["room-code"].waitForExistence(timeout: 10))
        shot(app, "405-\(device)-home-xxxl")
        app.swipeUp(); app.swipeUp()
        tapWhenReady(app.buttons["offline-overdraft"])
        let name = app.textFields["name"]
        if name.waitForExistence(timeout: 10) { name.tap(); name.typeText("Sim"); shot(app, "405-\(device)-name-xxxl"); tapWhenReady(app.buttons["join-room"]) }
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
