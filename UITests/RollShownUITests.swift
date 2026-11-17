import XCTest

/// #488: a roll tumbles, lands and stays on screen. Faces show before any result, the dice that can score are marked,
/// and a Farkle shows its dice and why nothing scored. Offline and seeded (-t2p-seed), so the same rolls come up each
/// run with no network; the online rooms are checked in DiceUITests.
final class RollShownUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testHotDiceRollLandsAndFarkleShows() {
        let app = launch(["-t2p-seed", "3"])
        startOffline(app, "farkle", bot: "bold")
        let roll = app.buttons["roll"]
        let banner = app.descendants(matching: .any)["farkle-banner"]
        let status = app.descendants(matching: .any)["dice-status"].firstMatch
        var shotAir = false, shotScores = false
        for _ in 0..<20 {
            XCTAssertTrue(waitEnabled(roll, 90), "your roll")
            roll.tap()
            if !shotAir { shot(app, "488-hot-dice-in-the-air"); shotAir = true }
            // the result: a Farkle, your dice to choose from, or hot dice
            let end = Date().addingTimeInterval(15)
            var result = "", said = ""
            while Date() < end && result.isEmpty {
                said = status.exists ? status.label : "(no status)"
                if banner.exists { result = "farkle" }
                else if said.contains("Tap the dice") { result = "choose" }
                else if said.contains("Hot dice") { result = "hot" }
                else { usleep(150_000) }
            }
            if result.isEmpty { shot(app, "488-hot-dice-no-result") }
            XCTAssertFalse(result.isEmpty, "the roll lands; the status says: \(said)")
            if result == "hot" { continue }
            let faces = dieLabels(app)
            XCTAssertFalse(faces.isEmpty, "the dice that came up stay on screen")
            XCTAssertTrue(faces.allSatisfy { $0.hasPrefix("Die showing") }, "faces show with the result, not after it: \(faces)")
            if result == "farkle" {
                XCTAssertTrue(banner.label.contains("Farkle"), banner.label)
                XCTAssertTrue(banner.label.contains("No 1s, no 5s, no three of a kind"), "the Farkle says why: \(banner.label)")
                sleep(1)   // the message comes a beat after the dice
                shot(app, "488-hot-dice-farkle")
                return
            }
            let dice = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'die-'")).allElementsBoundByIndex
            let values = dice.map { ($0.value as? String) ?? "" }
            guard let pick = dice.indices.first(where: { values[$0] == "scores" }) else {
                shot(app, "488-hot-dice-no-scoring-mark")
                XCTFail("a roll you choose from marks the dice that score: \(faces) \(values)")
                return
            }
            if !shotScores { shot(app, "488-hot-dice-scoring-marked"); shotScores = true }
            dice[pick].tap()   // keep one scoring die (or its set), then roll the rest: a Farkle comes soon
            usleep(600_000)
        }
        XCTFail("no Farkle came up in 20 rolls")
    }

    func testRollCallRollLandsBeforeTheBoxes() {
        let app = launch(["-t2p-seed", "3"])
        startOffline(app, "rollcall", bot: "easy")
        let roll = app.buttons["rc-roll"]
        XCTAssertTrue(waitEnabled(roll, 60), "your turn")
        roll.tap()
        shot(app, "488-rollcall-in-the-air")
        let box = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'box-'")).firstMatch
        XCTAssertTrue(box.waitForExistence(timeout: 10), "the boxes this roll can go in")
        let faces = (0..<5).map { app.buttons["rc-die-\($0)"].label }
        XCTAssertTrue(faces.allSatisfy { $0.hasPrefix("Die showing") }, "the dice have landed by the time the boxes show: \(faces)")
        shot(app, "488-rollcall-landed")
        box.tap()
        // the bot's turn: its rolls land on this screen too, and its score keeps the dice it scored with
        let last = app.descendants(matching: .any)["rollcall-last"]
        let end = Date().addingTimeInterval(30)
        var botScored = false
        while Date() < end && !botScored {
            if last.exists && !last.label.hasPrefix("Sim") && last.label.contains("with") { botScored = true } else { usleep(300_000) }
        }
        XCTAssertTrue(botScored, "the bot's score shows the dice it scored with")
        shot(app, "488-rollcall-bot-scored")
    }
}

extension XCTestCase {
    /// An offline practice room (#402) with one bot, started. Leaves you at the table.
    func startOffline(_ app: XCUIApplication, _ game: String, bot: String) {
        app.swipeUp()
        tapWhenReady(app.buttons["offline-\(game)"])
        let name = app.textFields["name"]
        if name.waitForExistence(timeout: 10) { name.tap(); name.typeText("Sim"); tapWhenReady(app.buttons["join-room"]) }
        tapWhenReady(app.buttons["addbot-\(bot)"]); sleep(1)
        tapWhenReady(app.buttons["start-game"])
    }

    /// What each of Hot Dice's live dice says to VoiceOver ("Die showing 5", "Die, rolling"), in one query.
    /// The labels of the dice on screen, read from one snapshot of the screen. Asking each die for its label in turn
    /// failed the test when the dice changed between the count and the read (a bot's roll replacing yours, Nov 17).
    func dieLabels(_ app: XCUIApplication) -> [String] {
        guard let screen = try? app.snapshot() else { return [] }
        var labels: [String] = []
        func walk(_ e: XCUIElementSnapshot) {
            if e.elementType == .button && e.identifier.hasPrefix("die-") { labels.append(e.label) }
            for c in e.children { walk(c) }
        }
        walk(screen)
        return labels
    }
}
