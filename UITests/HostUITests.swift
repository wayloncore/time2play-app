import XCTest

/// Hosting from an iPad (#537), on the live server: the iPad starts a hosted room and shows its code and QR; a phone
/// (this test, over the room's own socket, as the website's phone page talks) joins and shows up on the iPad; then the
/// iPad runs Roll Call and Hot Dice with bots, landscape and portrait, and ends the room.
final class HostUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// The whole screen as the device shows it (an app screenshot comes out turned wrong in landscape on iPad).
    private func screen(_ name: String) {
        let s = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: s); a.name = name; a.lifetime = .keepAlways; add(a)
        let home = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] ?? NSTemporaryDirectory()
        let dir = URL(fileURLWithPath: home).appendingPathComponent("t2p-shots")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? s.pngRepresentation.write(to: dir.appendingPathComponent("\(name).png"))
    }

    private func code(_ app: XCUIApplication) -> String {
        let e = app.staticTexts["host-code"]
        XCTAssertTrue(e.waitForExistence(timeout: 30), "the hosted room opens")
        return e.label.replacingOccurrences(of: "Room code ", with: "").replacingOccurrences(of: " ", with: "")
    }

    private func host(_ app: XCUIApplication, _ game: String) {
        let b = app.buttons["host-\(game)"]
        if !b.waitForExistence(timeout: 10) { app.swipeUp() }
        tapWhenReady(b)
    }

    /// A phone joining the way the website's phone page does: the room's socket, a join message.
    private func phoneJoins(_ path: String, _ code: String, name: String) -> URLSessionWebSocketTask {
        let t = URLSession.shared.webSocketTask(with: URL(string: "wss://tyleralocke.com/live/\(path)/\(code)")!)
        t.resume()
        t.send(.string(#"{"t":"join","name":"\#(name)","face":3}"#)) { _ in }
        return t
    }

    func testHostRollCallWithAPhone() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "hosting is the iPad's")
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = launch()
        host(app, "rollcall")
        let c = code(app)
        XCTAssertEqual(c.count, 4)
        let phone = phoneJoins("rollcall", c, name: "Pat")
        XCTAssertTrue(app.staticTexts["Pat"].waitForExistence(timeout: 20), "the phone shows up on the iPad")
        tapWhenReady(app.buttons["host-addbot-medium"]); sleep(1)
        screen("537-host-1-lobby-landscape")
        // the phone leaves before the start, so only bots play (a person's turns would wait for them)
        phone.cancel(with: .normalClosure, reason: nil)
        let pat = app.descendants(matching: .any)["host-player-p1"]
        if pat.waitForExistence(timeout: 3) { pat.buttons.firstMatch.tap(); tapWhenReady(app.buttons["Remove"]) }
        sleep(1)
        tapWhenReady(app.buttons["host-start"])
        sleep(6)
        screen("537-host-2-rollcall-playing")
        XCUIDevice.shared.orientation = .portrait
        sleep(2)
        shot(app, "537-host-3-rollcall-portrait")
        tapWhenReady(app.buttons["host-end"])
        tapWhenReady(app.buttons["End the room"])
        XCTAssertTrue(app.buttons["host-rollcall"].waitForExistence(timeout: 10), "back on Play")
    }

    func testHostCloseEnoughWithBots() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "hosting is the iPad's")
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = launch()
        host(app, "closeenough")
        _ = code(app)
        tapWhenReady(app.buttons["host-addbot-easy"]); sleep(1)
        tapWhenReady(app.buttons["host-addbot-hard"]); sleep(1)
        tapWhenReady(app.buttons["30s"]); sleep(1)
        tapWhenReady(app.buttons["host-start"])
        sleep(4)
        screen("537-host-5-close-enough-asking")
        // the bots lock in; the answer drops onto the 3D board
        XCTAssertTrue(app.staticTexts["host-answer"].waitForExistence(timeout: 45), "the answer is revealed on the iPad")
        sleep(3)
        screen("537-host-6-close-enough-answer")
        tapWhenReady(app.buttons["host-end"])
        tapWhenReady(app.buttons["End the room"])
        XCUIDevice.shared.orientation = .portrait
    }

    func testHostHotDiceWithBots() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "hosting is the iPad's")
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = launch()
        host(app, "farkle")
        _ = code(app)
        tapWhenReady(app.buttons["host-addbot-cautious"]); sleep(1)
        tapWhenReady(app.buttons["host-addbot-bold"]); sleep(1)
        tapWhenReady(app.buttons["host-start"])
        // the iPad shows each roll and tells the room, so the bots keep playing
        sleep(10)
        screen("537-host-4-hot-dice")
        XCTAssertTrue(app.descendants(matching: .any)["host-stage"].exists)
        tapWhenReady(app.buttons["host-end"])
        tapWhenReady(app.buttons["End the room"])
        XCUIDevice.shared.orientation = .portrait
    }
}
