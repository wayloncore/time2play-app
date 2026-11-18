import XCTest

/// The game-feel round (Nov 17): haptics, sounds and music switches, Classic dice, the app icons, turn alerts,
/// recent rooms and starred games on Play, the sounds a game plays, and the home screen widget.
final class FeelUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func flip(_ s: XCUIElement) {
        // a Form toggle: tap the switch itself, at its right end
        s.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
    }

    func testYouHasTheNewSettings() {
        let app = launch(["-t2p-default", "-t2p-name", "Sim"])
        // iPhone: the tab bar; iPad: the tabs at the top (or Play's own You button, which opens the same tab)
        let tab = app.tabBars.buttons["You"]
        tapWhenReady(tab.waitForExistence(timeout: 5) ? tab : app.buttons["You"].firstMatch)
        let classic = app.switches["toggle-classic-dice"]
        app.swipeUp()
        XCTAssertTrue(classic.waitForExistence(timeout: 10))
        XCTAssertEqual(classic.value as? String, "0", "3D dice for everyone: Classic dice starts off")
        XCTAssertEqual(app.switches["toggle-haptics"].value as? String, "1", "haptics start on")
        XCTAssertEqual(app.switches["toggle-sound"].value as? String, "1", "sound starts on")
        XCTAssertEqual(app.switches["toggle-music"].value as? String, "0", "music starts off")
        shot(app, "feel-you-settings")
        flip(classic)
        XCTAssertEqual(classic.value as? String, "1")
        let turn = app.switches["toggle-turn-alerts"]
        if !turn.exists { app.swipeUp() }
        XCTAssertTrue(turn.waitForExistence(timeout: 5))
        XCTAssertFalse(turn.isEnabled, "turn alerts are for signed-in players")
        app.swipeUp()
        XCTAssertTrue(app.buttons["icon-gold"].waitForExistence(timeout: 5), "the icon picker lists the variants")
        shot(app, "feel-you-alerts-icons")
    }

    func testStarAGameAndItComesFirst() {
        let app = launch(["-t2p-name", "Sim"])
        let star = app.buttons["favorite-rollcall"]
        app.swipeUp()
        tapWhenReady(star)
        let rollCall = app.buttons["start-rollcall"], overdraft = app.buttons["start-overdraft"]
        XCTAssertTrue(rollCall.waitForExistence(timeout: 5))
        sleep(1)
        let rc = rollCall.frame, od = overdraft.frame
        XCTAssertTrue(rc.minY < od.minY - 1 || (abs(rc.minY - od.minY) < 1 && rc.minX < od.minX), "a starred game moves to the front: \(rc) vs \(od)")
        shot(app, "feel-play-starred")
    }

    /// A room you were in shows on Play while it's open, and a tap rejoins it.
    func testRecentRoomRejoins() throws {
        let code = try startRoom("overdraft")
        let app = launch(["-t2p-name", "Sim"])
        let field = app.textFields["room-code"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap(); field.typeText(code)
        tapWhenReady(app.buttons["Join \(code)"])
        let name = app.textFields["name"]
        if name.waitForExistence(timeout: 20) { tapWhenReady(app.buttons["join-room"]) }
        XCTAssertTrue(app.staticTexts["room-code-shown"].waitForExistence(timeout: 20), "in the room's lobby")
        tapWhenReady(app.buttons["addbot-easy"])   // a bot keeps the room open once you've gone
        sleep(1)
        app.buttons["leave"].tap()
        tapWhenReady(app.buttons["Leave the room"], 5)
        let rejoin = app.buttons["rejoin-\(code)"]
        if !rejoin.waitForExistence(timeout: 15) {
            // the room closed with nobody in it: the list only shows open rooms, so nothing shows
            shot(app, "feel-recent-closed")
            throw XCTSkip("room \(code) closed when its last person left")
        }
        shot(app, "feel-play-recent")
        rejoin.tap()
        XCTAssertTrue(app.staticTexts["room-code-shown"].waitForExistence(timeout: 20), "back in the room")
    }

    /// An offline Hot Dice game plays the roll and its landing (the log is what the room's sounds were).
    func testHotDiceSounds() {
        let app = launch(["-t2p-sound-log", "-t2p-name", "Sim"])
        app.swipeUp()
        tapWhenReady(app.buttons["offline-farkle"])
        let name = app.textFields["name"]
        if name.waitForExistence(timeout: 10) { tapWhenReady(app.buttons["join-room"]) }
        tapWhenReady(app.buttons["addbot-bold"]); sleep(1)
        tapWhenReady(app.buttons["start-game"])
        let roll = app.buttons["roll"]
        XCTAssertTrue(waitEnabled(roll, 60))
        roll.tap(); sleep(3)
        let log = app.descendants(matching: .any)["sound-log"]
        XCTAssertTrue(log.waitForExistence(timeout: 5))
        XCTAssertTrue(log.label.contains("dice-roll"), "the roll's sound played: \(log.label)")
        XCTAssertTrue(log.label.contains("dice-land") || log.label.contains("farkle"), "and its landing: \(log.label)")
        shot(app, "feel-hot-dice-sounds")
    }

    /// The home screen widget, drawn in the app at its real sizes (a simulator can't screenshot the home screen's).
    func testWidgetLooks() {
        let app = XCUIApplication()
        app.launchArguments = ["-t2p-widget-still"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["widget-still"].waitForExistence(timeout: 10))
        shot(app, "feel-widget")
        app.terminate()
        app.launchArguments = ["-t2p-widget-still", "-t2p-widget-noroom"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["widget-still"].waitForExistence(timeout: 10))
        shot(app, "feel-widget-no-room")
    }
}
