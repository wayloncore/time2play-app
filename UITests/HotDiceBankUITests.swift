import XCTest

/// Hot Dice's Bank (Tyler, build 48: "the farkle game (Hot Dice) doesn't let me bank"). Offline against Rex, seeded,
/// with the website's own room core on the phone and the room's default house rules (500 to get on the board, three
/// Farkles cost 1,000): whole turns of roll, keep, roll, keep, bank with the score checked, hot dice, a Farkle, and the
/// end of a game. Played with the 3D dice (what a new player gets) and with the classic dice.
final class HotDiceBankUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    private var device: String { UIDevice.current.userInterfaceIdiom == .pad ? "ipad-" : "" }

    func testBankWith3DDice() { playAGame(["-t2p-dice3d", "-t2p-seed", "5", "-t2p-arena-debug"], name: "3d") }
    /// The 3D dice through a longer game (to 10,000, about seven minutes of it): every roll of yours lands and can be
    /// kept, however many there are.
    func testEveryRollLands3D() { playAGame(["-t2p-dice3d", "-t2p-seed", "11", "-t2p-arena-debug"], name: "3d-long", long: true) }
    /// Also earns an achievement at the end (-t2p-earn-test: nine games played already, and this practice game counts):
    /// its line at the top goes away on its own, stays clear of the game, and isn't said again.
    func testBankWithClassicDice() { playAGame(["-t2p-seed", "5", "-t2p-earn-test"], name: "classic", achievement: true) }

    // MARK: the game

    /// A roll of yours that didn't land within 15 seconds: what the room, the screen and the 3D scene said.
    private var stalls: [String] = []
    /// A tap on Roll or Bank the room never got (tapped again, and listed at the end).
    private var dropped: [String] = []
    /// The achievement line, the first time a look saw it (it lasts about 3 seconds, so every wait looks for it).
    private var toastSeen: (at: Date, words: String, clear: Bool)?
    private var watchToast = false
    private var rescueSeen = false

    private func playAGame(_ args: [String], name: String, achievement: Bool = false, long: Bool = false) {
        let app = launch(args)
        watchToast = achievement
        startOffline(app, short: !long)
        let roll = app.buttons["roll"], bank = app.buttons["bank"]
        let status = app.descendants(matching: .any)["dice-status"].firstMatch
        let banner = app.descendants(matching: .any)["farkle-banner"].firstMatch
        var banked = 0, twoKeepBank = false, hot = false, farkled = false, boardWait = false
        let deadline = Date().addingTimeInterval(long ? 420 : 540)
        while Date() < deadline && !app.staticTexts["game-over"].exists {
            // wait for your turn (or the end)
            guard roll.exists && roll.isEnabled && said(status).contains("Roll all six") else { peekToast(app); usleep(300_000); continue }
            let before = myScore(app)
            var keeps = 0, turnRolls = 0
            // the 3D scene has landed every roll so far by itself (the safety net settled none)
            let line = debug(app)
            if let r = line.range(of: "rescued="), !line[r.upperBound...].hasPrefix("0"), !rescueSeen {
                rescueSeen = true
                XCTFail("\(name): the 3D scene didn't land a roll by itself (the safety net settled it): \(line)")
            }
            roll.tap(); turnRolls += 1
            turn: while turnRolls < 20 {
                // the roll lands: dice to choose from, or a Farkle
                var end = Date().addingTimeInterval(15)
                let tapped = Date()
                var landed = "", retapped = false
                while Date() < end && landed.isEmpty {
                    if banner.exists { landed = "farkle" }
                    else if said(status).contains("Tap the dice") { landed = "choose" }
                    else if !retapped && Date().timeIntervalSince(tapped) > 3 && roll.exists && roll.isEnabled && said(status).contains("Roll all six") {
                        // the room never got the roll: say so, and tap again
                        dropped.append("Roll at turn start: \(debug(app))")
                        retapped = true
                        roll.tap()
                        end = Date().addingTimeInterval(15)
                    }
                    else { usleep(150_000) }
                }
                if landed.isEmpty {
                    // the roll never landed: what the room, the screen and the 3D scene each think, now and 30 s later;
                    // the game goes on if it lands after all, and the test fails at the end with every stall listed
                    let first = debug(app)
                    if stalls.isEmpty { shot(app, "bank-\(device)\(name)-never-landed") }
                    let later = Date().addingTimeInterval(30)
                    while Date() < later && !said(status).contains("Tap the dice") && !banner.exists { usleep(300_000) }
                    stalls.append("status \(said(status)); at 15 s: \(first); 30 s later: \(debug(app))")
                    if banner.exists { landed = "farkle" } else if said(status).contains("Tap the dice") { landed = "choose" }
                    else { XCTFail("\(name): a roll of yours never landed: \(stalls.joined(separator: " || "))"); return }
                }
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
                    var ok = waitFor(8) { self.myScore(app) == want }
                    if !ok && bank.exists && bank.isEnabled {
                        dropped.append("Bank: \(debug(app))")
                        bank.tap()
                        ok = waitFor(8) { self.myScore(app) == want }
                    }
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
        XCTAssertTrue(stalls.isEmpty, "\(name): every roll of yours lands within 15 seconds: \(stalls.joined(separator: " || "))")
        XCTAssertTrue(dropped.isEmpty, "\(name): every tap on Roll and Bank reaches the room: \(dropped.joined(separator: " || "))")

        XCTAssertGreaterThan(banked, 0, "\(name): you banked")
        if long { return }
        XCTAssertTrue(twoKeepBank, "\(name): a whole turn of roll, keep, roll, keep, bank")
        XCTAssertTrue(farkled, "\(name): a Farkle came up")
        XCTAssertTrue(hot, "\(name): hot dice came up")
        // the end of the game: someone reached 2,500, everyone else had one more turn
        XCTAssertTrue(app.staticTexts["game-over"].waitForExistence(timeout: 60), "\(name): the game ends")
        if achievement { checkAchievementLine(app) }
        sleep(1)
        shot(app, "bank-\(device)\(name)-game-over")
        let why = app.staticTexts["game-over-why"]
        XCTAssertTrue(why.exists && why.label.contains("reached 2,500") && why.label.contains("one last turn"),
                      "\(name): the end says why: \(why.exists ? why.label : "(none)")")
    }

    /// Build 48 (Tyler: "the achievements 10,000 popped up on the top and never went away"): the line comes once, at the
    /// top, clear of the game's buttons, and goes by itself in about 3 seconds.
    private func checkAchievementLine(_ app: XCUIApplication) {
        let toast = app.descendants(matching: .any)["toast"].firstMatch
        if toastSeen == nil { _ = toast.waitForExistence(timeout: 3); peekToast(app) }
        guard let seen = toastSeen else { XCTFail("the game's end earns Regular (10 games), said at the top"); return }
        XCTAssertTrue(seen.words.contains("Achievement") && seen.words.contains("Regular"), "it says which: \(seen.words)")
        XCTAssertTrue(seen.clear, "it sits at the top, over no button or die")
        XCTAssertTrue(waitFor(6) { !toast.exists }, "it goes by itself (still up after \(Date().timeIntervalSince(seen.at)) s): \(seen.words)")
        let gone = Date().timeIntervalSince(seen.at)
        XCTAssertLessThan(gone, 5, "gone in about 3 seconds, not \(gone)")
        shot(app, "bank-\(device)achievement-gone")
        // never said again as the room's view refreshes
        XCTAssertFalse(toast.waitForExistence(timeout: 4), "the achievement isn't announced again")
    }

    /// Looks for the achievement line once (cheap enough to do in every wait while it's being watched for).
    private func peekToast(_ app: XCUIApplication) {
        guard watchToast, toastSeen == nil else { return }
        let toast = app.descendants(matching: .any)["toast"].firstMatch
        // one snapshot: the line can go between two questions about it
        guard toast.exists, let snap = try? toast.snapshot() else { return }
        let f = snap.frame
        let covers = ["roll", "bank", "play-again", "back-to-library"].contains { app.buttons[$0].exists && app.buttons[$0].frame.intersects(f) }
            || app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'die-'")).allElementsBoundByIndex.contains { $0.frame.intersects(f) }
        toastSeen = (Date(), snap.label, f.maxY < app.frame.height * 0.2 && !covers)
        shot(app, "bank-\(device)achievement-shown")
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

    /// The test-only lines (-t2p-arena-debug): the room's turn and the screen's, and the 3D scene's own state.
    private func debug(_ app: XCUIApplication) -> String {
        ["hd-debug", "dice3d-debug"].map { id in
            let e = app.descendants(matching: .any)[id].firstMatch
            return e.exists ? e.label : "(no \(id))"
        }.joined(separator: " | ")
    }

    /// Your banked score, from the score strip ("You, 1250 points, their turn").
    private func myScore(_ app: XCUIApplication) -> Int {
        let me = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'You, '")).firstMatch
        guard me.exists else { return -1 }
        // "You, 1250 points" on the table; "You, 3,250" on the winner screen
        let words = me.label.dropFirst(5)
        return Int(words.prefix { $0.isNumber || $0 == "," }.filter(\.isNumber)) ?? -1
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
        while Date() < end { if check() { return true }; peekToast(XCUIApplication()); usleep(250_000) }
        return false
    }
}
