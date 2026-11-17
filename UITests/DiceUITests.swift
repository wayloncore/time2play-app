import XCTest

/// Hot Dice (#401), Roll Call and Close Enough, each with no host and a bot, on the live server.
final class DiceUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testHotDiceTurnAgainstABot() {
        let app = launch()
        startAsOwner(app, game: "farkle", bot: "steady")
        shot(app, "401-lobby")
        let roll = app.buttons["roll"], bank = app.buttons["bank"]
        let status = app.descendants(matching: .any)["dice-status"].firstMatch
        var tookShot = false
        /// One turn of yours: roll, keep what scores, bank when you can (or Farkle).
        func playATurn() {
            XCTAssertTrue(waitEnabled(roll, 120), "your turn comes round")
            roll.tap()
            for _ in 0..<12 {
                sleep(2)
                if !roll.exists { break }                         // a Farkle, or banked: the turn has passed
                for i in 0..<6 where app.buttons["die-\(i)"].exists && app.buttons["die-\(i)"].isEnabled { app.buttons["die-\(i)"].tap() }
                if !tookShot { shot(app, "401-your-turn"); tookShot = true }
                if bank.exists && bank.isEnabled { bank.tap(); break }
                if roll.exists && roll.isEnabled { roll.tap() }
            }
            XCTAssertTrue(status.waitForExistence(timeout: 30))
        }
        /// #488: the bot's roll lands on this phone too, faces showing, not just its result. Watched from the moment
        /// your turn ends: a bot that Farkles on its first roll can be done (and the turn back to you) in a few seconds.
        func watchJunesRoll() -> (seen: Bool, said: String, faces: [String]) {
            let end = Date().addingTimeInterval(30)
            var said = "", faces: [String] = []
            while Date() < end {
                said = status.exists ? status.label : "(no status)"
                faces = dieLabels(app)
                if said.contains("June") && !faces.isEmpty && faces.allSatisfy({ $0.hasPrefix("Die showing") }) { return (true, said, faces) }
                if said.contains("Roll all six") && roll.exists && roll.isEnabled { break }   // June's turn came and went
                usleep(300_000)
            }
            return (false, said, faces)
        }
        tapWhenReady(app.buttons["start-game"])
        playATurn()
        var watched = watchJunesRoll()
        shot(app, "401-after-your-turn")
        if !watched.seen {
            // June's whole turn fit between two looks (the live server can bunch its messages up): one more round.
            playATurn()
            watched = watchJunesRoll()
        }
        if !watched.seen { shot(app, "488-online-bot-roll-missing") }
        XCTAssertTrue(watched.seen, "the turn moves on and June's roll lands on your screen; last status: \(watched.said), dice: \(watched.faces)")
        shot(app, "488-online-bot-roll")
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
