import XCTest

/// Overdraft's 3D table (#496): stills of every suit, your turn, a card mid-throw and a scene mid-change (a made-up
/// table stopped at an exact moment), and real games against bots at 3, 5 and 10 players with the 3D table on.
/// Overdraft deals 3 to 10, so 2 players is shown as a still only.
final class Table3DUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private var device: String { UIDevice.current.userInterfaceIdiom == .pad ? "ipad-" : "" }

    private func still(_ cfg: String, _ name: String, _ extra: [String] = []) {
        let app = XCUIApplication()
        app.launchArguments = ["-t2p-3d-still", cfg] + extra
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["od3d-ready"].waitForExistence(timeout: 90), "\(name): the still never settled")
        XCTAssertTrue(app.descendants(matching: .any)["od3d-suit"].exists, "\(name): the suit shows between the piles")
        shot(app, name.hasPrefix("561-") ? "561-\(device)" + name.dropFirst(4) : "496-\(device)\(name)")
        app.terminate()
    }

    /// #719: the website's direction arrows and the brighter turn glow, at the moments Tyler compares with
    /// time2play.live: your turn, someone else's turn, a Reverse stopping, sweeping round and just after, in every
    /// element. The same
    /// stills at the oldest phones' tier (-t2p-3d-tier low) carry "-low".
    func testStills719() {
        for tier in ["high", "low"] {
            let t = tier == "low" ? "-low" : "", x = ["-t2p-3d-tier", tier]
            still("suit=wave n=5 mine=1", "719-your-turn\(t)", x)
            still("suit=wave n=5", "719-their-turn\(t)", x)
            still("suit=wave n=5 reverse=0.6", "719-reverse-slowing\(t)", x)
            still("suit=wave n=5 reverse=0.95", "719-reverse-sweep\(t)", x)
            still("suit=wave n=5 reverse=2.2", "719-reverse-after\(t)", x)
        }
        for s in ["ember", "bolt", "leaf"] { still("suit=\(s) n=5", "719-their-turn-\(s)") }
        still("suit=leaf n=5 mine=1", "719-your-turn-leaf")
        still("suit=wave n=10", "719-their-turn-10")
    }

    /// #721 (Tyler, after build 87: the arrows weren't fully on the table): the chevrons ride a slightly darker border
    /// inside the glass's edge, whole at every angle. Your turn, their turn, a Reverse mid-sweep and 10 players, in
    /// every element, at both quality tiers. testStills721Sizes takes the four moments to the smallest and largest phones.
    func testStills721() {
        for tier in ["high", "low"] {
            let t = tier == "low" ? "-low" : "", x = ["-t2p-3d-tier", tier]
            still("suit=wave n=5 mine=1", "721-your-turn\(t)", x)
            still("suit=wave n=5", "721-their-turn\(t)", x)
            still("suit=wave n=5 reverse=0.95", "721-reverse-sweep\(t)", x)
            still("suit=wave n=10", "721-their-turn-10\(t)", x)
        }
        for s in ["ember", "bolt", "leaf"] { still("suit=\(s) n=5", "721-their-turn-\(s)") }
        still("suit=leaf n=10 reverse=0.95", "721-reverse-sweep-10-leaf")
    }

    /// #721 on the smallest and largest phones (mac.yml's older_only and largest_only): the four moments Tyler named.
    func testStills721Sizes() {
        still("suit=wave n=5 mine=1", "721-your-turn")
        still("suit=wave n=5", "721-their-turn")
        still("suit=wave n=5 reverse=0.95", "721-reverse-sweep")
        still("suit=wave n=10", "721-their-turn-10")
    }

    /// #721: the border's frame rate against build 87's rail (-t2p-721-before), the way #719 measured: the same still,
    /// before and after twice each in turn, at both tiers; prints "FPS 721 …" lines.
    func testFrameRate721() { frameRate("721", beforeArg: "-t2p-721-before") }

    /// #719: the frame rate before and after (Tyler turned down #708's options because they dropped frames). The
    /// same still drawn with -t2p-719-before (the comets and the ring the app had) and without, twice each in turn,
    /// sixteen seconds apiece; prints "FPS 719 before|after …" lines for the report. A simulator's rate comes from
    /// the Mac's GPU, so the two compare; they don't promise a phone's rate.
    func testFrameRate719() { frameRate("719", beforeArg: "-t2p-719-before") }

    private func frameRate(_ issue: String, beforeArg: String) {
        for tier in ["high", "low"] {
            var got: [String: [Double]] = [:]
            for round in 0..<2 {
                for mode in round == 0 ? ["before", "after"] : ["after", "before"] {
                    let app = XCUIApplication()
                    app.launchArguments = ["-t2p-3d-still", "suit=ember n=6", "-t2p-arena-debug", "-t2p-fps", "-t2p-3d-tier", tier]
                        + (mode == "before" ? [beforeArg] : [])
                    app.launch()
                    XCTAssertTrue(app.descendants(matching: .any)["od3d-ready"].waitForExistence(timeout: 90), "the still never settled")
                    sleep(3)
                    for _ in 0..<8 {
                        sleep(2)
                        let l = (try? app.descendants(matching: .any)["od3d-debug"].firstMatch.snapshot())?.label ?? ""
                        if let r = l.range(of: "fps="), let v = Double(l[r.upperBound...].prefix { $0.isNumber || $0 == "." }), v > 0 {
                            got[mode, default: []].append(v)
                        }
                    }
                    app.terminate()
                    sleep(2)   // the simulator lets go of the last launch first (Nov 22: "does not have a process ID")
                }
            }
            for mode in ["before", "after"] {
                let v = (got[mode] ?? []).sorted()
                let med = v.isEmpty ? 0 : v[v.count / 2]
                print(String(format: "FPS %@ %@ %@ median %.1f lowest %.1f (%ld samples)", issue, tier, mode, med, v.first ?? 0, v.count))
            }
            XCTAssertFalse((got["after"] ?? []).isEmpty, "no frame-rate samples")
        }
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

    /// Build 45 (Tyler, Nov 18: "the card acts very stiff when moving"): frames of a card's flight, stopped on the
    /// scene's clock. A bot's card: picked up, in the air on its curve, touching down, and settling just past its spot.
    /// Your card: picked up from your hand, and in the air. A card drawn to your hand, on its way to its own spot.
    func testStillsCardMotion() {
        for (t, name) in [(0.05, "1-pickup"), (0.36, "2-air"), (0.7, "3-touchdown"), (0.92, "4-settle")] {
            still("suit=ember n=5 throw=\(t)", "561-card-seat-\(name)")
        }
        for (t, name) in [(0.07, "1-pickup"), (0.42, "2-air")] {
            still("suit=wave n=4 mine=1 hand=6 play=\(t)", "561-card-yours-\(name)")
        }
        still("suit=leaf n=4 mine=1 hand=6 draw=0.45", "561-card-drawn")
    }

    /// #722 (Tyler, Nov 22: the played card "wobbles, making it phase in and out of the card under it"): a bot's card
    /// and yours, just before touchdown, at the rock's deepest and through the settle, each beside build 87's
    /// (-t2p-722-before). The new card stays wholly above the pile.
    func testStills722() {
        for (extra, tag) in [([String](), ""), (["-t2p-722-before"], "-before")] {
            for t in [0.7, 0.72, 0.78, 0.86] { still("suit=ember n=5 throw=\(t)", "722-seat-\(t)\(tag)", extra) }
            for t in [0.8, 0.86] { still("suit=wave n=4 mine=1 hand=6 play=\(t)", "722-yours-\(t)\(tag)", extra) }
        }
    }

    /// #723: the scene change is half a second, so its sweep a quarter of a second in (mix=0.5), in two pairs of
    /// elements and at the oldest phones' tier.
    func testStills723() {
        still("suit=wave n=5 change=bolt mix=0.5", "723-sweep-quarter-second")
        still("suit=bolt n=6 change=leaf mix=0.5", "723-sweep-quarter-second-2")
        still("suit=wave n=5 change=ember mix=0.5", "723-sweep-quarter-second-low", ["-t2p-3d-tier", "low"])
    }

    func testStillsSeats() {
        for n in [2, 3, 8, 10] { still("suit=wave n=\(n)", "3d-seats-\(n)") }
    }

    /// Three players with nothing set: a new player gets the 3D table (#496, Nov 17: the default for everyone).
    /// #524 (Tyler, Nov 17, 5:51 PM): at 9 cards, a playable card in the back row (the Bolt 7) comes in front of the
    /// see-through cards and rises; at 12, none is buried. Each card size.
    func testStillsHandSizes() {
        for size in ["small", "medium", "large"] {
            still("suit=bolt n=4 mine=1 hand=9", "3d-hand9-\(size)", ["-t2p-card-size", size])
        }
        still("suit=bolt n=4 mine=1 hand=12", "3d-hand12-medium", ["-t2p-card-size", "medium"])
        still("suit=bolt n=4 mine=0 hand=9", "3d-hand9-off-turn", ["-t2p-card-size", "medium"])
    }

    /// A real game grown to 9 or more cards (you draw instead of playing), shot on your turn, at each card size.
    func testHandNineSmall() { growHand("small") }
    func testHandNineMedium() { growHand("medium") }
    func testHandNineLarge() { growHand("large") }

    private func growHand(_ size: String) {
        let app = launch(["-t2p-3d", "-t2p-card-size", size])
        app.swipeUp()
        tapWhenReady(app.buttons["offline-overdraft"])
        let name = app.textFields["name"]
        if name.waitForExistence(timeout: 10) { name.tap(); name.typeText("Sim"); tapWhenReady(app.buttons["join-room"]) }
        for i in 0..<2 {
            let b = app.buttons[i == 0 ? "addbot-easy" : "addbot-normal"]
            if !b.waitForExistence(timeout: 10) { break }
            if !b.isHittable { app.swipeUp() }
            b.tap(); usleep(500_000)
        }
        if !app.buttons["start-game"].isHittable { app.swipeUp() }
        tapWhenReady(app.buttons["start-game"])
        XCTAssertTrue(app.buttons["draw"].waitForExistence(timeout: 20), "the 3D table is dealt")
        let cards = NSPredicate(format: "identifier BEGINSWITH 'legal-' OR identifier BEGINSWITH 'card-'")
        let legal = NSPredicate(format: "identifier BEGINSWITH 'legal-'")
        var shots = 0
        let deadline = Date().addingTimeInterval(200)
        while Date() < deadline && shots < 2 {
            if app.staticTexts["hand-over"].exists || app.staticTexts["table-over"].exists { break }
            guard app.staticTexts["your-turn"].exists else { usleep(500_000); continue }
            let n = app.buttons.matching(cards).count
            if n >= 9 && app.buttons.matching(legal).count > 0 {
                usleep(600_000)
                shot(app, "524-\(device)3d-game-\(size)-\(n)cards-\(shots)")
                shots += 1
            }
            // grow the hand: draw, and keep what's drawn
            if app.buttons["keep"].exists { app.buttons["keep"].tap() }
            else if app.buttons["draw"].isEnabled { app.buttons["draw"].tap() }
            else if app.buttons.matching(legal).count > 0 { app.buttons.matching(legal).element(boundBy: 0).tap() }
            usleep(900_000)
        }
        XCTAssertGreaterThan(shots, 0, "the hand reached 9 cards on your turn")
        app.terminate()
    }

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
                let wave = app.buttons["suit-wave"]   // the painted suit chooser (Nov 18)
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
