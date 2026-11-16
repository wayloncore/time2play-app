import XCTest

/// Overdraft with no host (#400): start a room, add two bots, deal, and play a whole hand on the live server.
final class OverdraftUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testPlayAHandAgainstBots() throws {
        let app = launch()
        tapWhenReady(app.buttons["start-overdraft"])
        let name = app.textFields["name"]
        if name.waitForExistence(timeout: 20) {            // a first-time player picks a name and a face first
            name.tap(); name.typeText("Sim")
            tapWhenReady(app.buttons["join-room"])
        }
        XCTAssertTrue(app.descendants(matching: .any)["owner-chip"].waitForExistence(timeout: 20), "you own the room you start")
        tapWhenReady(app.buttons["addbot-easy"])
        sleep(1)
        app.buttons["addbot-normal"].tap()
        sleep(1)
        shot(app, "400-lobby-owner")
        tapWhenReady(app.buttons["start-game"])
        XCTAssertTrue(app.buttons["draw"].waitForExistence(timeout: 20), "the table is dealt")

        var shotTurn = false, plays = 0
        let deadline = Date().addingTimeInterval(300)
        let legal = NSPredicate(format: "identifier BEGINSWITH 'legal-'")
        while Date() < deadline {
            if app.staticTexts["hand-over"].exists { break }
            guard app.staticTexts["your-turn"].exists else { usleep(400_000); continue }
            if !shotTurn { shot(app, "400-your-turn"); shotTurn = true }
            let cards = app.buttons.matching(legal)
            if cards.count > 0 {
                // tap the card's visible edge (the next card overlaps the rest of it)
                cards.element(boundBy: 0).coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.3)).tap()
                // a Change Suit or a +4 asks for the suit
                let wave = app.buttons["Wave"]
                if wave.waitForExistence(timeout: 1) { wave.tap() }
                plays += 1
            } else if app.buttons["keep"].exists {
                app.buttons["keep"].tap()
            } else {
                app.buttons["draw"].tap()
            }
            if plays == 3 { shot(app, "400-mid-hand"); plays += 1 }
            usleep(900_000)
        }
        XCTAssertTrue(app.staticTexts["hand-over"].waitForExistence(timeout: 30), "the hand ends with a winner")
        shot(app, "400-hand-over")
        XCTAssertTrue(app.buttons["play-again"].exists, "the owner can deal again")
        app.buttons["leave"].tap()
        tapWhenReady(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Leave the'")).firstMatch, 5)
    }

    /// An app older than the server's oldest protocol shows Please update (the real server says so).
    func testPleaseUpdate() throws {
        let code = try startRoom("overdraft")
        let app = launch(["-t2p-old-protocol"])
        let field = app.textFields["room-code"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap(); field.typeText(code)
        tapWhenReady(app.buttons["Join \(code)"])
        XCTAssertTrue(app.staticTexts["please-update"].waitForExistence(timeout: 20))
        shot(app, "400-please-update")
    }
}
