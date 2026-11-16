import XCTest

/// Hot Dice (#401), Roll Call and Close Enough, each with no host and a bot, on the live server.
final class DiceUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testHotDiceTurnAgainstABot() {
        let app = launch()
        startAsOwner(app, game: "farkle", bot: "steady")
        shot(app, "401-lobby")
        tapWhenReady(app.buttons["start-game"])
        let roll = app.buttons["roll"], bank = app.buttons["bank"]
        XCTAssertTrue(waitEnabled(roll, 120), "your turn comes round")
        roll.tap()
        var tookShot = false
        for _ in 0..<12 {
            sleep(2)
            if !roll.exists { break }                         // a Farkle, or banked: the turn has passed
            for i in 0..<6 where app.buttons["die-\(i)"].exists && app.buttons["die-\(i)"].isEnabled { app.buttons["die-\(i)"].tap() }
            if !tookShot { shot(app, "401-your-turn"); tookShot = true }
            if bank.exists && bank.isEnabled { bank.tap(); break }
            if roll.exists && roll.isEnabled { roll.tap() }
        }
        XCTAssertTrue(app.staticTexts["dice-status"].waitForExistence(timeout: 30))
        sleep(3)
        shot(app, "401-after-your-turn")
        XCTAssertFalse(roll.exists && roll.isEnabled && app.staticTexts["dice-status"].label.contains("Roll all six"), "the turn moved on")
    }

    func testRollCallTurn() {
        let app = launch()
        startAsOwner(app, game: "rollcall", bot: "easy")
        tapWhenReady(app.buttons["start-game"])
        let roll = app.buttons["rc-roll"]
        XCTAssertTrue(waitEnabled(roll, 60), "your turn")
        roll.tap()
        sleep(2)
        shot(app, "rollcall-rolled")
        let box = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'box-'")).firstMatch
        XCTAssertTrue(box.waitForExistence(timeout: 10), "the boxes this roll can go in")
        box.tap()
        sleep(2)
        shot(app, "rollcall-scored")
    }

    func testCloseEnoughQuestion() {
        let app = launch()
        startAsOwner(app, game: "closeenough", bot: "medium")
        tapWhenReady(app.buttons["start-game"])
        tapWhenReady(app.buttons["lock-in"], 20)
        shot(app, "closeenough-locked")
        XCTAssertTrue(app.staticTexts["ce-answer"].waitForExistence(timeout: 30), "the answer is revealed once everyone is in")
        shot(app, "closeenough-reveal")
    }
}
