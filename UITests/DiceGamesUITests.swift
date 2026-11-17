import XCTest

/// #489: Hot Dice and Roll Call each played start to finish against a bot, offline and seeded (the website's own room
/// cores on the phone, so no network and the same dice each run), with a screenshot of each moment: the lobby and How
/// to play, your roll, a bot's turn in the list of what just happened, a big moment, and the winner screen with Play
/// again and Back to Library.
final class DiceGamesUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// An offline room with one bot, in its lobby (not started).
    private func offlineLobby(_ app: XCUIApplication, _ game: String, bot: String) {
        app.swipeUp()
        tapWhenReady(app.buttons["offline-\(game)"])
        let name = app.textFields["name"]
        if name.waitForExistence(timeout: 10) { name.tap(); name.typeText("Sim"); tapWhenReady(app.buttons["join-room"]) }
        tapWhenReady(app.buttons["addbot-\(bot)"]); sleep(1)
    }

    private func howToPlay(_ app: XCUIApplication, shot name: String, says words: String) {
        tapWhenReady(app.buttons["how-to-play"])
        let lede = app.staticTexts["how-to-lede"]
        XCTAssertTrue(lede.waitForExistence(timeout: 5), "How to play opens in one tap")
        XCTAssertTrue(lede.label.contains(words), "How to play says the room's set-up: \(lede.label)")
        shot(app, name)
        tapWhenReady(app.buttons["how-to-done"])
    }

    private func endScreen(_ app: XCUIApplication, _ prefix: String, why: String) {
        XCTAssertTrue(app.staticTexts["game-over"].waitForExistence(timeout: 20), "the game ends with a winner")
        sleep(1)
        shot(app, "\(prefix)-7-winner")
        let reason = app.staticTexts["game-over-why"]
        XCTAssertTrue(reason.exists && reason.label.contains(why), "the winner screen says why the game ended: \(reason.exists ? reason.label : "(none)")")
        XCTAssertTrue(app.buttons["play-again"].exists, "the owner can play again")
        tapWhenReady(app.buttons["back-to-library"])
        XCTAssertFalse(app.staticTexts["game-over"].waitForExistence(timeout: 3), "Back to Library leaves the room")
        shot(app, "\(prefix)-8-back-to-library")
    }

    func testHotDiceAWholeGameAgainstABot() {
        let app = launch(["-t2p-seed", "5"])
        offlineLobby(app, "farkle", bot: "bold")
        tapWhenReady(app.buttons["2,500"])                      // a short game: to 2,500
        sleep(1)
        shot(app, "489-hd-1-lobby")
        howToPlay(app, shot: "489-hd-2-how-to-play", says: "First to 2,500 wins")
        tapWhenReady(app.buttons["start-game"])

        let roll = app.buttons["roll"], bank = app.buttons["bank"]
        let status = app.descendants(matching: .any)["dice-status"].firstMatch
        let feed = app.descendants(matching: .any)["hd-feed"].firstMatch
        let big = app.descendants(matching: .any)["big-moment"].firstMatch
        let banner = app.descendants(matching: .any)["farkle-banner"].firstMatch
        let scoring = NSPredicate(format: "identifier BEGINSWITH 'die-' AND value == 'scores'")
        var shotRoll = false, shotBot = false, shotBig = false, shotFarkle = false, banks = 0
        let deadline = Date().addingTimeInterval(480)
        while Date() < deadline && !app.staticTexts["game-over"].exists {
            if !shotBig && big.exists { shot(app, "489-hd-5-big-moment"); shotBig = true }
            if !shotBot && feed.exists && feed.label.contains("Rex") { shot(app, "489-hd-4-bot-turn"); shotBot = true }
            if !shotFarkle && banner.exists && banner.label.contains("Rex") { usleep(600_000); shot(app, "489-hd-6-bot-farkle"); shotFarkle = true }
            // your turn: keep what scores, bank once it's allowed, otherwise roll on
            let said = status.exists ? status.label : ""
            if said.contains("Tap the dice") {
                let die = app.buttons.matching(scoring).firstMatch
                if die.exists { die.tap(); usleep(400_000) }
                if !shotRoll { shot(app, "489-hd-3-your-roll"); shotRoll = true }
                if bank.exists && bank.isEnabled { bank.tap(); banks += 1; usleep(500_000); continue }
            }
            guard roll.exists && roll.isEnabled else { usleep(250_000); continue }
            roll.tap()
            usleep(1_600_000)                                      // the dice tumble and land
        }
        XCTAssertGreaterThan(banks, 0, "you banked at least once")
        endScreen(app, "489-hd", why: "reached 2,500")
    }

    func testRollCallAWholeGameAgainstABot() {
        let app = launch(["-t2p-seed", "5"])
        offlineLobby(app, "rollcall", bot: "easy")
        shot(app, "489-rc-1-lobby")
        howToPlay(app, shot: "489-rc-2-how-to-play", says: "thirteen boxes")
        tapWhenReady(app.buttons["start-game"])

        let roll = app.buttons["rc-roll"]
        let feed = app.descendants(matching: .any)["rollcall-last"].firstMatch
        let big = app.descendants(matching: .any)["big-moment"].firstMatch
        let box = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'box-'")).firstMatch
        var shotRoll = false, shotBot = false, shotBig = false, turns = 0
        let deadline = Date().addingTimeInterval(420)
        while Date() < deadline && !app.staticTexts["game-over"].exists {
            if !shotBig && big.exists { shot(app, "489-rc-5-big-moment"); shotBig = true }
            if !shotBot && turns > 0 && feed.exists && feed.label.hasPrefix("Pip scored") && feed.label.contains("with") {
                shot(app, "489-rc-4-bot-scored"); shotBot = true
            }
            guard roll.exists && roll.isEnabled else {
                if box.exists && box.isHittable { box.tap(); turns += 1 }   // no rolls left: a box
                usleep(300_000); continue
            }
            roll.tap()
            XCTAssertTrue(box.waitForExistence(timeout: 10), "the boxes this roll can go in")
            if !shotRoll { shot(app, "489-rc-3-your-roll"); shotRoll = true }
            box.tap(); turns += 1
            usleep(500_000)
        }
        XCTAssertGreaterThanOrEqual(turns, 13, "you filled all thirteen boxes")
        endScreen(app, "489-rc", why: "13 rounds")
    }
}
