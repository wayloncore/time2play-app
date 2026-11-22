import XCTest

/// Nov 20's batch: Yacht Dice's in-place board (before a roll, mid-tumble, landed, two held, and a real game against
/// a bot), every Overdraft action card the same size as its neighbors in the classic and 3D hands (#609), and the
/// Bolt storm mid-flash behind the 3D table (#610).
final class YachtDiceUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private var device: String { UIDevice.current.userInterfaceIdiom == .pad ? "ipad-" : "" }

    // MARK: Yacht Dice

    private func board(_ moment: String, _ name: String, _ extra: [String] = [], check: (XCUIApplication) -> Void = { _ in }) {
        let app = XCUIApplication()
        app.launchArguments = ["-t2p-dice-still", "game=rollcall moment=\(moment)"] + extra
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["yacht-ready"].waitForExistence(timeout: 30), "\(name): the board never came")
        XCTAssertFalse(app.descendants(matching: .any)["dice-3d"].exists, "\(name): no arena")
        shot(app, "yacht-\(device)\(name)")
        check(app)
        app.terminate()
    }

    func testBoard() {
        board("before", "1-before-roll") { app in
            XCTAssertTrue(app.buttons["rc-roll"].exists, "Roll under the dice")
            XCTAssertEqual(app.buttons["rc-die-0"].label, "Die, not rolled yet")
            XCTAssertTrue(app.staticTexts["rc-bonus-progress"].label.contains("so far, need 63"), app.staticTexts["rc-bonus-progress"].label)
        }
        board("tumble", "2-mid-tumble") { app in
            XCTAssertEqual(app.buttons["rc-die-0"].label, "Die, rolling")
        }
        board("settled", "3-landed") { app in
            XCTAssertEqual(app.buttons["rc-die-2"].label, "Die showing 5")
            XCTAssertTrue(app.buttons["box-threes"].exists, "the boxes this roll can go in, with their points")
            XCTAssertTrue(app.buttons["box-threes"].label.contains("Score 6"), app.buttons["box-threes"].label)
            for i in 0..<5 {
                let d = app.buttons["rc-die-\(i)"]
                XCTAssertGreaterThanOrEqual(d.frame.width, 43.5, "\(d.identifier) is easy to tap: \(d.frame)")
                XCTAssertGreaterThanOrEqual(d.frame.height, 43.5, "\(d.identifier) is easy to tap: \(d.frame)")
            }
            // the dice in one row, at the bottom, under the scorecard
            let ys = (0..<5).map { app.buttons["rc-die-\($0)"].frame.midY }
            XCTAssertLessThan((ys.max() ?? 0) - (ys.min() ?? 0), 1, "one row: \(ys)")
            XCTAssertGreaterThan(ys[0], app.buttons["box-threes"].frame.maxY, "the dice sit under the scorecard")
        }
        board("kept", "4-two-held") { app in
            XCTAssertEqual(app.buttons["rc-die-0"].value as? String, "held")
            XCTAssertEqual(app.buttons["rc-die-1"].value as? String, "held")
            XCTAssertEqual(app.buttons["rc-die-2"].value as? String, "")
        }
    }

    /// #724, #725: four held dice in white and gold (white HOLD letters, a lit gold ring), beside build 91's gunmetal
    /// (-t2p-725-before).
    func testHeld724() {
        for (extra, tag) in [([String](), ""), (["-t2p-725-before"], "-before91")] {
            board("kept4", "725-four-held\(tag)", extra) { app in
                for i in 0..<4 { XCTAssertEqual(app.buttons["rc-die-\(i)"].value as? String, "held") }
                XCTAssertEqual(app.buttons["rc-die-4"].value as? String, "")
            }
        }
    }

    /// A real game against Pip: roll (the dice tumble in place and land), hold one, roll again, take a box.
    func testPlayed() {
        let app = launch(["-t2p-seed", "4"])
        app.swipeUp()
        tapWhenReady(app.buttons["offline-rollcall"])
        let name = app.textFields["name"]
        if name.waitForExistence(timeout: 10) { typeName(app, name); tapWhenReady(app.buttons["join-room"]) }
        tapWhenReady(app.buttons["addbot-easy"]); sleep(1)
        tapWhenReady(app.buttons["start-game"])
        let roll = app.buttons["rc-roll"]
        XCTAssertTrue(waitEnabled(roll, 60), "your turn")
        roll.tap()
        usleep(250_000)
        shot(app, "yacht-\(device)5-played-tumbling")
        let box = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'box-'")).firstMatch
        XCTAssertTrue(box.waitForExistence(timeout: 12), "the boxes show once the dice land")
        XCTAssertTrue(app.buttons["rc-die-0"].label.hasPrefix("Die showing"), app.buttons["rc-die-0"].label)
        app.buttons["rc-die-0"].tap()
        let end = Date().addingTimeInterval(4)
        while Date() < end && (app.buttons["rc-die-0"].value as? String) != "held" { usleep(200_000) }
        XCTAssertEqual(app.buttons["rc-die-0"].value as? String, "held")
        XCTAssertTrue(waitEnabled(roll, 5))
        roll.tap()
        XCTAssertTrue(box.waitForExistence(timeout: 12))
        XCTAssertEqual(app.buttons["rc-die-0"].value as? String, "held", "a held die stays put through a roll")
        shot(app, "yacht-\(device)6-played-second-roll")
        box.tap()
        sleep(2)
        shot(app, "yacht-\(device)7-played-scored")
    }

    // MARK: Overdraft (#609, #610)

    private func table(_ cfg: String, _ name: String) {
        let app = XCUIApplication()
        app.launchArguments = ["-t2p-3d-still", cfg, "-t2p-card-size", "medium"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["od3d-ready"].waitForExistence(timeout: 90), "\(name): never settled")
        usleep(300_000)
        shot(app, "609-\(device)\(name)")
        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'legal-' OR identifier BEGINSWITH 'card-'")).allElementsBoundByIndex
        XCTAssertGreaterThanOrEqual(cards.count, 9, "\(name): the whole hand")
        // the classic hand's cards lie flat: every one the same size (the action cards were drawn short; a playable
        // card's 3-point gold ring adds 3 to its frame, so allow that). The 3D fan
        // tilts each card a little differently, so its frames differ; that hand is checked in its screenshot.
        if cfg.contains("classic=1") {
            let heights = cards.map { $0.frame.height.rounded() }, widths = cards.map { $0.frame.width.rounded() }
            XCTAssertLessThanOrEqual((heights.max() ?? 0) - (heights.min() ?? 0), 3, "\(name): one height: \(heights)")
            XCTAssertLessThanOrEqual((widths.max() ?? 0) - (widths.min() ?? 0), 3, "\(name): one width: \(widths)")
        }
        app.terminate()
    }

    func testEveryActionCardOneSize() {
        table("classic=1 actions=1 mine=1 suit=bolt", "classic-hand-actions")
        table("suit=bolt n=4 mine=1 actions=1", "3d-hand-actions")
    }

    /// #610: the Bolt storm mid-flash (two bolts, the rim lit) and between strikes, with your hand over it.
    func testBoltStorm() {
        table("suit=bolt n=5 mine=1 actions=1 strike=0.05", "610-bolt-mid-flash")
        table("suit=bolt n=5 mine=1 actions=1 strike=1.6", "610-bolt-between-strikes")
    }
}
