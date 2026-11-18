import XCTest

/// Tyler, Nov 18: "Make this look like a game option not an apple option." The painted suit chooser on the 3D and the
/// classic table, and the painted dialogs in play (the room menu, End the room, Leave). Offline rooms dealt from seed 7
/// with an easy and a normal bot: you go first holding a Change Suit (c106), as the bundled rules deal it (checked in
/// Node against Core's rules.js), so every run opens the chooser the same way.
final class SuitPickerUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private var device: String { UIDevice.current.userInterfaceIdiom == .pad ? "ipad-" : "" }

    /// An offline Overdraft room from seed 7, on your first turn, with the chooser open.
    private func openChooser(_ threeD: Bool, _ extra: [String] = []) -> XCUIApplication {
        let app = launch((threeD ? ["-t2p-3d"] : []) + ["-t2p-seed", "7"] + extra)
        app.swipeUp()
        tapWhenReady(app.buttons["offline-overdraft"])
        let name = app.textFields["name"]
        if name.waitForExistence(timeout: 10) { name.tap(); name.typeText("Sim"); tapWhenReady(app.buttons["join-room"]) }
        for b in ["addbot-easy", "addbot-normal"] {
            let e = app.buttons[b]
            XCTAssertTrue(e.waitForExistence(timeout: 10), "\(b) is there")
            if !e.isHittable { app.swipeUp() }
            e.tap(); usleep(500_000)
        }
        if !app.buttons["start-game"].isHittable { app.swipeUp() }
        tapWhenReady(app.buttons["start-game"])
        XCTAssertTrue(app.staticTexts["your-turn"].waitForExistence(timeout: 30), "seed 7: you go first")
        sleep(2)   // the deal lands
        let wild = app.buttons["legal-c106"]
        XCTAssertTrue(wild.waitForExistence(timeout: 10), "seed 7: the Change Suit can go")
        wild.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.3)).tap()
        XCTAssertTrue(app.descendants(matching: .any)["suit-picker"].waitForExistence(timeout: 5), "the painted chooser opens")
        XCTAssertFalse(app.sheets.firstMatch.exists, "no iOS sheet")
        XCTAssertFalse(app.alerts.firstMatch.exists, "no iOS alert")
        return app
    }

    /// The chooser stopped at its moments: partway up, settled, a flare, an emblem in flight, a landing.
    private func stills(_ threeD: Bool) {
        let t = threeD ? "3d" : "classic"
        let app = openChooser(threeD, ["-t2p-pick-still"])
        sleep(1)
        for s in ["suit-ember", "suit-wave", "suit-bolt", "suit-leaf"] {
            XCTAssertTrue(app.buttons[s].exists, "\(s) is a button")
        }
        XCTAssertTrue(app.buttons["suit-ember"].frame.width >= 88, "a big target: \(app.buttons["suit-ember"].frame)")
        let names = ["1-rising", "2-settled", "3-ember-flare", "4-wave-flying", "5-leaf-landing"]
        for (i, n) in names.enumerated() {
            if i > 0 { app.buttons["pick-next"].tap() }
            usleep(500_000)
            shot(app, "nov18-\(device)\(t)-pick-\(n)")
        }
        app.terminate()
    }

    func testStills3D() { stills(true) }
    func testStillsClassic() { stills(false) }

    /// A real choice: Bolt flares, flies to the pile and the card goes down; then the painted room menu, End the
    /// room and Leave.
    private func choose(_ threeD: Bool) {
        let t = threeD ? "3d" : "classic"
        let app = openChooser(threeD)
        sleep(1)
        shot(app, "nov18-\(device)\(t)-real-up")
        app.buttons["suit-bolt"].tap()
        usleep(300_000)
        shot(app, "nov18-\(device)\(t)-real-mid")
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.descendants(matching: .any)["suit-picker"])
        wait(for: [gone], timeout: 5)
        XCTAssertFalse(app.buttons["legal-c106"].exists || app.buttons["card-c106"].exists, "the Change Suit was played")
        usleep(400_000)
        shot(app, "nov18-\(device)\(t)-real-landed")
        if threeD { print("SUIT-CHIP:", app.descendants(matching: .any)["od3d-suit"].label) }

        tapWhenReady(app.buttons["room-menu"])
        XCTAssertTrue(app.descendants(matching: .any)["dialog-room-menu"].waitForExistence(timeout: 5), "the painted room menu")
        XCTAssertFalse(app.sheets.firstMatch.exists || app.alerts.firstMatch.exists, "no iOS sheet or alert")
        usleep(500_000)
        shot(app, "nov18-\(device)\(t)-dialog-room-menu")
        tapWhenReady(app.buttons["menu-end-room"])
        XCTAssertTrue(app.descendants(matching: .any)["dialog-end-room"].waitForExistence(timeout: 5), "the painted End the room")
        usleep(500_000)
        shot(app, "nov18-\(device)\(t)-dialog-end-room")
        tapWhenReady(app.buttons["dialog-cancel"])
        let closed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.descendants(matching: .any)["dialog-end-room"])
        wait(for: [closed], timeout: 5)

        tapWhenReady(app.buttons["leave"])
        XCTAssertTrue(app.descendants(matching: .any)["dialog-leave"].waitForExistence(timeout: 5), "the painted Leave")
        usleep(500_000)
        shot(app, "nov18-\(device)\(t)-dialog-leave")
        tapWhenReady(app.buttons["Leave the game"])
        XCTAssertTrue(app.buttons["offline-overdraft"].waitForExistence(timeout: 10) || app.tabBars.firstMatch.exists, "back out of the room")
        app.terminate()
    }

    func testChoose3D() { choose(true) }
    func testChooseClassic() { choose(false) }

    /// Reduce Motion: the chooser fades in and out, and the choice still goes.
    func testReduceMotion() {
        let app = openChooser(true, ["-t2p-reduce-motion"])
        usleep(400_000)
        shot(app, "nov18-\(device)3d-pick-reduce-motion")
        app.buttons["suit-leaf"].tap()
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.descendants(matching: .any)["suit-picker"])
        wait(for: [gone], timeout: 3)
        XCTAssertFalse(app.buttons["legal-c106"].exists || app.buttons["card-c106"].exists, "the Change Suit was played")
        app.terminate()
    }
}
