import XCTest

/// Hot Dice's Bank (Tyler, build 48: "the farkle game (Hot Dice) doesn't let me bank"). Offline against Rex, seeded,
/// with the website's own room core on the phone and the room's default house rules (500 to get on the board, three
/// Farkles cost 1,000): whole turns of roll, keep, roll, keep, bank with the score checked, hot dice, a Farkle, and the
/// end of a game. Played with the 3D dice (what a new player gets) and with the classic dice.
final class HotDiceBankUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    private var device: String { UIDevice.current.userInterfaceIdiom == .pad ? "ipad-" : "" }

    func testBankWith3DDice() { playAGame(["-t2p-dice3d", "-t2p-seed", "5"], name: "3d") }
    func testBankWithClassicDice() { playAGame(["-t2p-seed", "5"], name: "classic") }

    // MARK: the game

    private func playAGame(_ args: [String], name: String) {
        let app = launch(args)
        startOffline(app, short: true)
        let roll = app.buttons["roll"], bank = app.buttons["bank"]
        let status = app.descendants(matching: .any)["dice-status"].firstMatch
        let banner = app.descendants(matching: .any)["farkle-banner"].firstMatch
        var banked = 0, twoKeepBank = false, hot = false, farkled = false, boardWait = false
        let deadline = Date().addingTimeInterval(540)
        while Date() < deadline && !app.staticTexts["game-over"].exists {
            // wait for your turn (or the end)
            guard roll.exists && roll.isEnabled && said(status).contains("Roll all six") else { usleep(300_000); continue }
            let before = myScore(app)
            var keeps = 0, turnRolls = 0
            roll.tap(); turnRolls += 1
            turn: while turnRolls < 20 {
                // the roll lands: dice to choose from, or a Farkle
                let end = Date().addingTimeInterval(15)
                var landed = ""
                while Date() < end && landed.isEmpty {
                    if banner.exists { landed = "farkle" }
                    else if said(status).contains("Tap the dice") { landed = "choose" }
                    else { usleep(150_000) }
                }
                XCTAssertFalse(landed.isEmpty, "\(name): the roll lands; status: \(said(status))")
                if landed == "farkle" {
                    let words = banner.label
                    XCTAssertTrue(words.contains("Farkle"), "\(name): a Farkle says so: \(words)")
                    if !farkled { shot(app, "bank-\(device)\(name)-farkle"); farkled = true }
                    // a Farkle banks nothing: your score stays (or loses 1,000 on a third in a row)
                    sleep(4)
                    let after = myScore(app)
                    XCTAssertTrue(after == before || (words.contains("Three") && after < before), "\(name): a Farkle banks nothing (\(before) → \(after))")
                    break turn
                }
                // keep every die that scores
                keepAllScoring(app)
                keeps += 1
                let total = points(bank.label)
                let s = said(status)
                // Bank is on exactly when the website's is: a scoring keep, and 500 in the turn until you're on the board
                if !bank.isEnabled {
                    XCTAssertTrue(s.contains("You need 500 to get on the board"),
                                  "\(name): Bank is off only while you need 500 to get on the board; status: \(s), bank: \(bank.label)")
                    if !boardWait { shot(app, "bank-\(device)\(name)-needs-500"); boardWait = true }
                } else {
                    XCTAssertTrue(s.contains("Bank it for"), "\(name): with Bank on, the status says what banking makes: \(s)")
                }
                if bank.isEnabled && keeps >= 2 && total >= 300 {
                    XCTAssertTrue(bank.isHittable, "\(name): Bank can be tapped (nothing covers it): \(bank.frame)")
                    shot(app, "bank-\(device)\(name)-before-bank")
                    bank.tap()
                    let want = before + total
                    let ok = waitFor(8) { self.myScore(app) == want }
                    if !ok { shot(app, "bank-\(device)\(name)-bank-failed") }
                    XCTAssertTrue(ok, "\(name): Bank adds the turn to your score: \(before) + \(total) should be \(want), shows \(myScore(app)); status: \(said(status))")
                    banked += 1
                    if keeps >= 2 { twoKeepBank = true }
                    if banked == 1 { usleep(700_000); shot(app, "bank-\(device)\(name)-after-bank") }
                    break turn
                }
                // roll on (every die kept is hot dice: all six go again)
                XCTAssertTrue(roll.isEnabled, "\(name): Roll is on after a scoring keep")
                let allSix = roll.label.contains("6 dice") && keeps > 0
                roll.tap(); turnRolls += 1
                if allSix {
                    hot = true
                    XCTAssertTrue(waitFor(15) { self.liveDice(app) == 6 || banner.exists }, "\(name): hot dice roll all six again")
                    if banner.exists == false { shot(app, "bank-\(device)\(name)-hot-dice") }
                }
            }
        }
        XCTAssertGreaterThan(banked, 0, "\(name): you banked")
        XCTAssertTrue(twoKeepBank, "\(name): a whole turn of roll, keep, roll, keep, bank")
        XCTAssertTrue(farkled, "\(name): a Farkle came up")
        XCTAssertTrue(hot, "\(name): hot dice came up")
        // the end of the game: someone reached 2,500, everyone else had one more turn
        XCTAssertTrue(app.staticTexts["game-over"].waitForExistence(timeout: 60), "\(name): the game ends")
        sleep(1)
        shot(app, "bank-\(device)\(name)-game-over")
        let why = app.staticTexts["game-over-why"]
        XCTAssertTrue(why.exists && why.label.contains("reached 2,500") && why.label.contains("one last turn"),
                      "\(name): the end says why: \(why.exists ? why.label : "(none)")")
    }

    // MARK: helpers

    /// An offline room against Rex, played to 2,500 (the house rules left as they are), and started.
    private func startOffline(_ app: XCUIApplication, short: Bool) {
        app.swipeUp()
        tapWhenReady(app.buttons["offline-farkle"])
        let name = app.textFields["name"]
        if name.waitForExistence(timeout: 10) { name.tap(); name.typeText("Sim"); tapWhenReady(app.buttons["join-room"]) }
        tapWhenReady(app.buttons["addbot-bold"]); sleep(1)
        if short { tapWhenReady(app.buttons["2,500"]); sleep(1) }
        tapWhenReady(app.buttons["start-game"])
    }

    private func said(_ e: XCUIElement) -> String { e.exists ? e.label : "" }

    /// Your banked score, from the score strip ("You, 1250 points, their turn").
    private func myScore(_ app: XCUIApplication) -> Int {
        let me = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'You, '")).firstMatch
        guard me.exists else { return -1 }
        let words = me.label.dropFirst(5)
        return Int(words.prefix { $0.isNumber }) ?? -1
    }

    /// The points after the "+" in Bank's label ("Bank, +650").
    private func points(_ label: String) -> Int {
        guard let plus = label.lastIndex(of: "+") else { return 0 }
        return Int(label[plus...].filter(\.isNumber)) ?? 0
    }

    /// Taps every die that scores, one at a time (a die in a set takes its whole set with it).
    private func keepAllScoring(_ app: XCUIApplication) {
        let scoring = NSPredicate(format: "identifier BEGINSWITH 'die-' AND value == 'scores'")
        for _ in 0..<6 {
            let die = app.buttons.matching(scoring).allElementsBoundByIndex.first { $0.isHittable }
            guard let die else { break }
            die.tap()
            usleep(600_000)
        }
    }

    /// The live dice on the felt (the 3D dice and the flat ones both name them die-0 … die-5).
    private func liveDice(_ app: XCUIApplication) -> Int {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'die-' AND label BEGINSWITH 'Die showing'")).count
    }

    private func waitFor(_ seconds: TimeInterval, _ check: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { if check() { return true }; usleep(250_000) }
        return false
    }
}
