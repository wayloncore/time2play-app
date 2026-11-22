import XCTest

/// The 3D dice arena (#521): stills of a Hot Dice roll mid-tumble, the dice settled, two kept and a Farkle, and Roll
/// Call settled and with two held (a made-up turn stopped at an exact moment), then real offline games against a bot
/// with the 3D dice on: tap a die and it goes to the keep row, tap it again and it comes back.
final class Dice3DUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private var device: String { UIDevice.current.userInterfaceIdiom == .pad ? "ipad-" : "" }

    @discardableResult
    private func still(_ cfg: String, _ name: String, extra: [String] = [], check: (XCUIApplication) -> Void = { _ in }) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-t2p-dice-still", cfg] + extra
        app.launch()
        // a slow simulator (the iPad) can time out on a snapshot while the scene starts: let it start first
        sleep(UIDevice.current.userInterfaceIdiom == .pad ? 6 : 1)
        XCTAssertTrue(app.descendants(matching: .any)["dice3d-ready"].waitForExistence(timeout: 60), "\(name): the still never stopped")
        usleep(300_000)
        shot(app, name.hasPrefix("561-") || name.hasPrefix("706-") ? name : "521-\(device)\(name)")
        XCTAssertFalse(app.staticTexts["SCORES"].exists, "\(name): no SCORES labels on the dice")
        check(app)
        app.terminate()
        return app
    }

    func testStills() {
        // the iPad simulator can start so slowly that the made-up roll has landed before the scene's first frame,
        // so there's no tumble to stop on: the mid-tumble frame is shot on the iPhone only
        if device.isEmpty { still("game=hot moment=tumble", "hot-1-mid-tumble") }
        still("game=hot moment=settled", "hot-2-settled") { app in
            XCTAssertEqual(app.buttons["die-0"].value as? String, "scores", "the 5 could score (said to VoiceOver, not drawn on the die)")
            XCTAssertEqual(app.buttons["die-2"].value as? String, "doesn’t score")
            XCTAssertEqual(app.staticTexts["dice3d-camera"].label, "eased", "your roll landed: the camera eased in")
            self.checkTapTargets(app, "die-")
        }
        // build 45 (Tyler: "the zoom goes in and right out that is wrong"): three seconds on, it's still eased in
        // (the old push-in was back out by 2.3 s), like the website's Hot Dice
        still("game=hot moment=settled after=3", "561-\(device)hot-held-3s") { app in
            XCTAssertEqual(app.staticTexts["dice3d-camera"].label, "eased", "the camera holds on the dice")
        }
        still("game=hot moment=kept", "hot-3-two-kept") { app in
            XCTAssertEqual(app.buttons["die-0"].value as? String, "kept")
            XCTAssertEqual(app.buttons["die-1"].value as? String, "kept")
            XCTAssertTrue(app.staticTexts["keep-line"].label.contains("150"), "what you're keeping: \(app.staticTexts["keep-line"].label)")
            XCTAssertEqual(app.staticTexts["dice3d-camera"].label, "eased", "picking dice leaves the camera eased in (build 45)")
        }
        still("game=hot moment=farkle", "hot-4-farkle") { app in
            XCTAssertEqual(app.staticTexts["dice3d-camera"].label, "fitted", "a Farkle never eases in")
            let banner = app.descendants(matching: .any)["farkle-banner"]
            XCTAssertTrue(banner.exists, "a Farkle shows why")
            XCTAssertTrue(banner.label.contains("No 1s, no 5s"), banner.label)
        }
        // #523: pinched in and turned a little; the dice still answer where they are on screen
        still("game=hot moment=settled zoom=1.8", "hot-5-zoomed") { app in
            XCTAssertEqual(app.buttons["die-0"].value as? String, "scores")
            XCTAssertTrue(app.buttons["dice-reset-view"].exists, "a moved view offers its reset")
        }
        // Yacht Dice (Roll Call) has no arena since Nov 20: its stills are in YachtDiceUITests
    }

    /// #706 (Tyler: "increase the zoom on the dice animation as well"): your roll closes in while the dice tumble and
    /// settle, at the default text size and at a large accessibility size (AX3), and Reduce Motion gets the closer
    /// framing with no ease. Shot mid-roll and settled so they can be compared.
    func testRollCloseUp() {
        let ax3 = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
        for (tag, extra) in [("default", [String]()), ("ax3", ax3)] {
            if device.isEmpty { still("game=hot moment=tumble after=0.9", "706-\(device)\(tag)-1-mid-roll", extra: extra) }
            still("game=hot moment=settled", "706-\(device)\(tag)-2-settled", extra: extra) { app in
                XCTAssertEqual(app.staticTexts["dice3d-camera"].label, "eased", "\(tag): your roll landed close up")
                for i in 0..<6 {
                    let die = app.buttons["die-\(i)"]
                    // the die's button is a little bigger than the die: its middle half must be on screen
                    let f = die.frame.insetBy(dx: die.frame.width / 4, dy: die.frame.height / 4)
                    XCTAssertTrue(die.exists && app.frame.contains(f), "\(tag): die \(i) is wholly on screen at \(die.frame)")
                }
                let words = app.descendants(matching: .any)["dice-status"].firstMatch
                if words.exists {
                    for i in 0..<6 where app.buttons["die-\(i)"].frame.midY < words.frame.maxY - 4 {
                        XCTFail("\(tag): die \(i) is under the words (\(app.buttons["die-\(i)"].frame) vs \(words.frame))")
                    }
                }
            }
        }
        still("game=hot moment=settled", "706-\(device)reduce-motion-settled", extra: ["-t2p-reduce-motion"]) { app in
            XCTAssertEqual(app.staticTexts["dice3d-camera"].label, "eased", "Reduce Motion: the closer framing, no ease")
        }
    }

    /// Hot Dice offline against Rex with the 3D dice: roll, keep a scoring die (it goes to the keep row), put it back,
    /// keep it again, roll on, until a Farkle shows why.
    func testHotDicePlayed() {
        let app = launch(["-t2p-dice3d", "-t2p-seed", "3"])
        startOffline(app, "farkle", bot: "bold")
        XCTAssertTrue(app.descendants(matching: .any)["dice-3d"].waitForExistence(timeout: 20), "the 3D dice are on")
        let roll = app.buttons["roll"]
        let banner = app.descendants(matching: .any)["farkle-banner"]
        let status = app.descendants(matching: .any)["dice-status"].firstMatch
        var shotAir = false, shotKept = false, putBack = false, eased = 0
        for _ in 0..<16 {
            XCTAssertTrue(waitEnabled(roll, 90), "your roll")
            roll.tap()
            if !shotAir { usleep(1_500_000); shot(app, "521-\(device)play-1-rolling"); shotAir = true }
            let end = Date().addingTimeInterval(15)
            var result = "", said = "", farkleSaid = ""
            while Date() < end && result.isEmpty {
                said = status.exists ? status.label : "(no status)"
                if banner.exists, let b = try? banner.snapshot() { result = "farkle"; farkleSaid = b.label }   // one look: it can go
                else if said.contains("Tap the dice") { result = "choose" }
                else if said.contains("Hot dice") { result = "hot" }
                else { usleep(150_000) }
            }
            XCTAssertFalse(result.isEmpty, "the roll lands; the status says: \(said)")
            if result == "hot" { continue }
            if result == "farkle" {
                // the banner shows for 2.4 s after the dice land: read it as soon as it's seen (a busy simulator's
                // queries can take most of that), then shoot
                shot(app, "521-\(device)play-4-farkle")
                XCTAssertTrue(farkleSaid.contains("No 1s, no 5s, no three of a kind"), "the Farkle says why: \(farkleSaid)")
                XCTAssertTrue(shotKept, "a die went to the keep row before the Farkle")
                XCTAssertGreaterThan(eased, 0, "your rolls eased the camera in (build 45)")
                return
            }
            let dice = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'die-'")).allElementsBoundByIndex
            guard let pick = dice.first(where: { ($0.value as? String) == "scores" }) else {
                XCTFail("a roll you choose from has a die that scores: \(dice.map { "\($0.label) \(String(describing: $0.value))" })")
                return
            }
            let camera = app.staticTexts["dice3d-camera"].label
            if camera == "eased" { eased += 1 }
            let id = pick.identifier
            pick.tap()
            XCTAssertTrue(waitValue(app.buttons[id], "kept", 4), "a tapped die goes to the keep row")
            XCTAssertEqual(app.staticTexts["dice3d-camera"].label, camera, "picking a die leaves the camera where it is")
            if !shotKept { usleep(500_000); shot(app, "521-\(device)play-2-kept"); shotKept = true }
            if !putBack {
                app.buttons[id].tap()
                XCTAssertTrue(waitValue(app.buttons[id], "scores", 4), "tapped again, it comes back to the felt")
                usleep(500_000)
                shot(app, "521-\(device)play-3-put-back")
                putBack = true
                app.buttons[id].tap()
                XCTAssertTrue(waitValue(app.buttons[id], "kept", 4))
            }
            usleep(300_000)
        }
        XCTFail("no Farkle came up in 16 rolls")
    }

    /// #523: Hot Dice with the board pinched in: a die still picks where it is on screen, and the reset puts the view back.
    func testHotDiceZoomed() {
        let app = launch(["-t2p-dice3d", "-t2p-seed", "3"])
        startOffline(app, "farkle", bot: "bold")
        let arena = app.descendants(matching: .any)["dice-3d"].firstMatch
        XCTAssertTrue(arena.waitForExistence(timeout: 20), "the 3D dice are on")
        let roll = app.buttons["roll"]
        let status = app.descendants(matching: .any)["dice-status"].firstMatch
        for _ in 0..<12 {
            XCTAssertTrue(waitEnabled(roll, 90), "your roll")
            roll.tap()
            let end = Date().addingTimeInterval(15)
            while Date() < end && !(status.exists && status.label.contains("Tap the dice")) { usleep(200_000) }
            guard status.exists && status.label.contains("Tap the dice") else { continue }   // a Farkle or hot dice: next roll
            arena.pinch(withScale: 2.0, velocity: 1.5)
            usleep(900_000)
            shot(app, "523-\(device)hd-pinched")
            XCTAssertTrue(app.buttons["dice-reset-view"].waitForExistence(timeout: 3), "a moved view offers its reset")
            let dice = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'die-'")).allElementsBoundByIndex
            // a die the zoom took off the screen isn't asked whether it's hittable (XCUITest fails the question itself)
            let screen = app.frame
            if let pick = dice.first(where: { d in
                guard let s = try? d.snapshot(), s.value as? String == "scores", screen.contains(CGPoint(x: s.frame.midX, y: s.frame.midY)) else { return false }
                return d.isHittable
            }) {
                let id = pick.identifier
                pick.tap()
                XCTAssertTrue(waitValue(app.buttons[id], "kept", 4), "a die picks where it is on the zoomed board")
                usleep(500_000)
                shot(app, "523-\(device)hd-pinched-kept")
            }
            app.buttons["dice-reset-view"].tap()
            usleep(900_000)
            XCTAssertFalse(app.buttons["dice-reset-view"].exists, "the view is back where it was")
            shot(app, "523-\(device)hd-reset")
            return
        }
        XCTFail("no roll to choose from in 12 tries")
    }

    /// Yacht Dice (Roll Call) offline against Pip with the 3D dice on: since Nov 20 it rolls in place anyway (no
    /// arena). Roll, hold two (they stay in their places, marked HOLD), roll again, score.
    func testRollCallPlayed() {
        let app = launch(["-t2p-dice3d", "-t2p-seed", "3"])
        startOffline(app, "rollcall", bot: "easy")
        let roll = app.buttons["rc-roll"]
        XCTAssertTrue(waitEnabled(roll, 60), "your turn")
        XCTAssertFalse(app.descendants(matching: .any)["dice-3d"].exists, "Yacht Dice rolls in place, even with the 3D dice on")
        roll.tap()
        let box = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'box-'")).firstMatch
        XCTAssertTrue(box.waitForExistence(timeout: 12), "the boxes show once the dice land")
        let faces = (0..<5).map { app.buttons["rc-die-\($0)"].label }
        XCTAssertTrue(faces.allSatisfy { $0.hasPrefix("Die showing") }, "landed: \(faces)")
        app.buttons["rc-die-0"].tap()
        XCTAssertTrue(waitValue(app.buttons["rc-die-0"], "held", 4), "a held die stays in its place, marked held")
        app.buttons["rc-die-1"].tap()
        XCTAssertTrue(waitValue(app.buttons["rc-die-1"], "held", 4))
        usleep(600_000)
        shot(app, "521-\(device)rc-play-1-two-held")
        XCTAssertTrue(waitEnabled(roll, 5))
        roll.tap()
        usleep(1_200_000)
        shot(app, "521-\(device)rc-play-2-reroll")
        XCTAssertTrue(box.waitForExistence(timeout: 12))
        XCTAssertEqual(app.buttons["rc-die-0"].value as? String, "held", "held dice stay in their places through a roll")
        box.tap()
        sleep(3)
        shot(app, "521-\(device)rc-play-3-bot-rolls")
    }

    /// Build 45: the dice are drawn smaller, and every die's button is still at least 44 points.
    private func checkTapTargets(_ app: XCUIApplication, _ prefix: String) {
        let dice = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).allElementsBoundByIndex
        XCTAssertFalse(dice.isEmpty, "the dice have buttons")
        for d in dice where d.isHittable {
            XCTAssertGreaterThanOrEqual(d.frame.width, 43.5, "\(d.identifier) is easy to tap: \(d.frame)")
            XCTAssertGreaterThanOrEqual(d.frame.height, 43.5, "\(d.identifier) is easy to tap: \(d.frame)")
        }
    }

    private func waitValue(_ e: XCUIElement, _ v: String, _ timeout: TimeInterval) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end { if e.exists && (e.value as? String) == v { return true }; usleep(200_000) }
        return false
    }
}
