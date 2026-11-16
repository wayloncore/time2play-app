import XCTest

/// Overdraft with no host (#400): start a room, add two bots, deal, and play a whole hand on the live server.
final class OverdraftUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// #489: a whole hand against two bots, with a screenshot of each moment: the lobby and How to play, the deal,
    /// a bot's turn, your turn, a draw, a big moment (Reverse, Skip, a train), the last card, the winner screen and
    /// Play again.
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
        tapWhenReady(app.buttons["how-to-play"])
        XCTAssertTrue(app.staticTexts["how-to-lede"].waitForExistence(timeout: 5), "How to play opens in one tap")
        shot(app, "489-od-1-how-to-play")
        tapWhenReady(app.buttons["how-to-done"])
        tapWhenReady(app.buttons["start-game"])
        XCTAssertTrue(app.buttons["draw"].waitForExistence(timeout: 20), "the table is dealt")
        usleep(350_000)
        shot(app, "489-od-2-deal")

        var shotTurn = false, shotTheirs = false, shotDraw = false, shotFlash = false, shotLast = false, plays = 0, turns = 0
        let deadline = Date().addingTimeInterval(360)
        let legal = NSPredicate(format: "identifier BEGINSWITH 'legal-'")
        while Date() < deadline {
            if app.staticTexts["hand-over"].exists { break }
            if !shotFlash && app.descendants(matching: .any)["od-flash"].exists { shot(app, "489-od-6-big-moment"); shotFlash = true }
            if !shotLast && app.staticTexts["table-over"].exists { shot(app, "489-od-7-last-card"); shotLast = true }
            guard app.staticTexts["your-turn"].exists else {
                if !shotTheirs && app.staticTexts["their-turn"].exists && plays > 0 { shot(app, "489-od-3-bot-turn"); shotTheirs = true }
                usleep(250_000); continue
            }
            if !shotTurn { shot(app, "489-od-4-your-turn"); shotTurn = true }
            turns += 1
            let cards = app.buttons.matching(legal)
            if !shotDraw && turns >= 2 && !app.buttons["keep"].exists {
                // once, draw on purpose (a draw is allowed with cards that could go) to see the card arrive
                app.buttons["draw"].tap()
                usleep(700_000); shot(app, "489-od-5-you-drew"); shotDraw = true
                usleep(400_000); continue
            }
            if cards.count > 0 {
                // tap the card's visible edge (the next card overlaps the rest of it)
                cards.element(boundBy: 0).coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.3)).tap()
                // a Change Suit or a +4 asks for the suit
                let wave = app.buttons["Wave"]
                if wave.waitForExistence(timeout: 1) { wave.tap() }
                plays += 1
                // your last card: the table says so before the winner screen covers it
                if !shotLast && app.staticTexts["table-over"].waitForExistence(timeout: 0.8) { shot(app, "489-od-7-last-card"); shotLast = true }
            } else if app.buttons["keep"].exists {
                app.buttons["keep"].tap()
            } else {
                app.buttons["draw"].tap()
            }
            if plays == 3 { shot(app, "400-mid-hand"); plays += 1 }
            usleep(600_000)
        }
        if !shotLast, app.staticTexts["table-over"].waitForExistence(timeout: 3) { shot(app, "489-od-7-last-card") }
        XCTAssertTrue(app.staticTexts["hand-over"].waitForExistence(timeout: 30), "the hand ends with a winner")
        sleep(1)
        shot(app, "489-od-8-winner")
        XCTAssertTrue(app.buttons["play-again"].exists, "the owner can deal again")
        XCTAssertTrue(app.buttons["back-to-library"].exists, "anyone can go back to the Library")
        app.buttons["play-again"].tap()
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.staticTexts["hand-over"])
        wait(for: [gone], timeout: 20)
        XCTAssertTrue(app.buttons["draw"].waitForExistence(timeout: 20), "Play again deals a new hand")
        usleep(300_000)
        shot(app, "489-od-9-play-again")
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
