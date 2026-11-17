import XCTest

/// Overdraft's 3D table (#496): stills of every suit, your turn, a card mid-throw and a scene mid-change (a made-up
/// table stopped at an exact moment), and real games against bots at 3, 5 and 10 players with the 3D table on.
/// Overdraft deals 3 to 10, so 2 players is shown as a still only.
final class Table3DUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private var device: String { UIDevice.current.userInterfaceIdiom == .pad ? "ipad-" : "" }

    private func still(_ cfg: String, _ name: String) {
        let app = XCUIApplication()
        app.launchArguments = ["-t2p-3d-still", cfg]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["od3d-ready"].waitForExistence(timeout: 90), "\(name): the still never settled")
        XCTAssertTrue(app.descendants(matching: .any)["od3d-suit"].exists, "\(name): the suit shows between the piles")
        shot(app, "496-\(device)\(name)")
        app.terminate()
    }

    func testStillsEverySuit() {
        for s in ["wave", "ember", "bolt", "leaf"] { still("suit=\(s) n=5", "3d-suit-\(s)") }
        still("suit=bolt n=5 strike=0.16", "3d-bolt-strike")
    }

    func testStillsMoments() {
        still("suit=leaf n=5 mine=1", "3d-your-turn")
        still("suit=wave n=4 mine=1 hand=11", "3d-two-rows")
        still("suit=ember n=5 throw=0.42", "3d-mid-throw")
        still("suit=wave n=5 change=bolt mix=0.5", "3d-mid-transition")
        still("suit=bolt n=6 change=leaf mix=0.55", "3d-mid-transition-2")
    }

    /// Tyler's Nov 17 changes: the cards you can't play see-through on your turn, the turn flow mid-Reverse (slowing,
    /// then running the other way), a double flash in the storm, and the meadow.
    func testStillsNov17() {
        still("suit=bolt n=4 mine=1 hand=9", "3d-see-through")
        still("suit=wave n=5 reverse=0.55", "3d-reverse-slowing")
        still("suit=ember n=5 reverse=1.5", "3d-reverse-back")
        still("suit=bolt n=3 strike=0.2", "3d-bolt-flash-3")
        still("suit=leaf n=7 mine=1 hand=5", "3d-leaf-your-turn")
    }

    func testStillsSeats() {
        for n in [2, 3, 8, 10] { still("suit=wave n=\(n)", "3d-seats-\(n)") }
    }

    /// Three players with nothing set: a new player gets the 3D table (#496, Nov 17: the default for everyone).
    func testPlayThree() { play(bots: 2, seconds: 150, args: ["-t2p-default"]) }
    func testPlayFive() { play(bots: 4, seconds: 150) }
    func testPlayTen() { play(bots: 9, seconds: 180) }

    /// An offline game against bots at the 3D table: you play your cards as your turns come, until the hand ends or
    /// time is up. Shots: the deal, your turn, a card in the air, a bot's turn, the end.
    private func play(bots: Int, seconds: TimeInterval, args: [String] = ["-t2p-3d"]) {
        let n = bots + 1
        let app = launch(args)
        app.swipeUp()
        tapWhenReady(app.buttons["offline-overdraft"])
        let name = app.textFields["name"]
        if name.waitForExistence(timeout: 10) { name.tap(); name.typeText("Sim"); tapWhenReady(app.buttons["join-room"]) }
        for i in 0..<bots {
            let b = app.buttons[i % 2 == 0 ? "addbot-easy" : "addbot-normal"]
            if !b.waitForExistence(timeout: 10) { break }
            if !b.isHittable { app.swipeUp() }
            b.tap()
            usleep(500_000)
        }
        if !app.buttons["start-game"].isHittable { app.swipeUp() }
        tapWhenReady(app.buttons["start-game"])
        XCTAssertTrue(app.descendants(matching: .any)["table-3d"].waitForExistence(timeout: 20), "the 3D table is on")
        XCTAssertTrue(app.buttons["draw"].waitForExistence(timeout: 10), "the table is dealt")
        usleep(800_000)
        let seats = app.descendants(matching: .any).matching(identifier: "od3d-seat")
        XCTAssertEqual(seats.count, n - 1, "every other player has a seat round the table")
        shot(app, "496-\(device)3d-play\(n)-1-deal")

        var shotTurn = false, shotThrow = false, shotTheirs = false, plays = 0, turns = 0
        let deadline = Date().addingTimeInterval(seconds)
        let legal = NSPredicate(format: "identifier BEGINSWITH 'legal-'")
        while Date() < deadline {
            if app.staticTexts["hand-over"].exists || app.staticTexts["table-over"].exists { break }
            guard app.staticTexts["your-turn"].exists else {
                if !shotTheirs && plays > 0 && app.staticTexts["their-turn"].exists { shot(app, "496-\(device)3d-play\(n)-4-bot-turn"); shotTheirs = true }
                usleep(500_000); continue   // every half second: fewer accessibility snapshots of a busy table
            }
            turns += 1
            if !shotTurn { shot(app, "496-\(device)3d-play\(n)-2-your-turn"); shotTurn = true }
            let cards = app.buttons.matching(legal)
            if cards.count > 0 {
                cards.element(boundBy: 0).coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.3)).tap()
                let wave = app.buttons["Wave"]
                if wave.waitForExistence(timeout: 1) { wave.tap() }
                plays += 1
                if !shotThrow { usleep(150_000); shot(app, "496-\(device)3d-play\(n)-3-throw"); shotThrow = true }
            } else if app.buttons["keep"].exists {
                app.buttons["keep"].tap()
            } else {
                app.buttons["draw"].tap()
            }
            usleep(900_000)
            if plays >= 4 && seconds < 100 { break }
        }
        shot(app, "496-\(device)3d-play\(n)-5-end")
        XCTAssertGreaterThan(turns, 0, "play came round to you at the 3D table")
        XCTAssertGreaterThan(plays + (app.staticTexts["hand-over"].exists ? 1 : 0), 0, "you played a card at the 3D table")
        app.terminate()
    }
}
