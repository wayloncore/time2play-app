import XCTest

/// Bots with no signal (#402): the server's own rules in JavaScriptCore. Practice games never reach the server.
final class OfflineUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testOfflineOverdraftAgainstBots() {
        let app = launch()
        app.swipeUp()
        tapWhenReady(app.buttons["offline-overdraft"])
        let name = app.textFields["name"]
        if name.waitForExistence(timeout: 10) { name.tap(); name.typeText("Sim"); tapWhenReady(app.buttons["join-room"]) }
        tapWhenReady(app.buttons["addbot-easy"]); sleep(1)
        app.buttons["addbot-normal"].tap(); sleep(1)
        shot(app, "402-offline-lobby")
        tapWhenReady(app.buttons["start-game"])
        XCTAssertTrue(app.buttons["draw"].waitForExistence(timeout: 10), "the offline table is dealt")
        XCTAssertTrue(app.staticTexts["your-turn"].waitForExistence(timeout: 90) || app.staticTexts["hand-over"].exists, "the bots play and it comes round to you")
        shot(app, "402-offline-table")
    }

    func testOfflineHotDice() {
        let app = launch()
        app.swipeUp()
        tapWhenReady(app.buttons["offline-farkle"])
        let name = app.textFields["name"]
        if name.waitForExistence(timeout: 10) { name.tap(); name.typeText("Sim"); tapWhenReady(app.buttons["join-room"]) }
        tapWhenReady(app.buttons["addbot-bold"]); sleep(1)
        tapWhenReady(app.buttons["start-game"])
        let roll = app.buttons["roll"]
        XCTAssertTrue(waitEnabled(roll, 60))
        roll.tap(); sleep(2)
        shot(app, "402-offline-hot-dice")
    }
}
