import XCTest

/// The waiting screen's logo and the loading spinner (wayloncore/tyleralocke#543), at real size: the iPad host's
/// waiting screen with its code and QR (landscape and portrait), the TV picture (Show on TV → See what the TV shows),
/// Reduce Motion's still, the phone lobby, the intro replay in place of one pass, the loop gone once the game starts,
/// and the spinner at small and large sizes. The rooms are live ones on tyleralocke.com.
final class WaitingLoopUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    override func tearDown() { XCUIDevice.shared.orientation = .portrait }
    private var device: String { UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone" }

    /// The whole screen as the device shows it (an app screenshot comes out turned wrong in landscape on iPad).
    private func screen(_ name: String) {
        let s = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: s); a.name = name; a.lifetime = .keepAlways; add(a)
        let home = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] ?? NSTemporaryDirectory()
        let dir = URL(fileURLWithPath: home).appendingPathComponent("t2p-shots")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? s.pngRepresentation.write(to: dir.appendingPathComponent("\(name).png"))
    }

    private func logo(_ app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any)["waiting-loop"].firstMatch }

    private func hostRoom(_ app: XCUIApplication, _ game: String) {
        let b = app.buttons["host-\(game)"]
        if !b.waitForExistence(timeout: 10) { app.swipeUp() }
        tapWhenReady(b)
        XCTAssertTrue(app.staticTexts["host-code"].waitForExistence(timeout: 30), "the hosted room opens")
    }

    private func endHostedRoom(_ app: XCUIApplication) {
        tapWhenReady(app.buttons["host-end"])
        tapWhenReady(app.buttons["End the room"])
    }

    /// The spinner, turning and still, from 20 to 80 points, on this device.
    func testSpinnerSizes() {
        let app = launch(["-t2p-spinner-gallery"])
        XCTAssertTrue(app.descendants(matching: .any)["spinner-gallery"].waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(app.descendants(matching: .any).matching(identifier: "spinner").count, 10)
        sleep(1)
        shot(app, "543-\(device)-spinners")
    }

    /// The iPad host's waiting screen: the loop beside the code and the QR, landscape and portrait; the TV picture; and
    /// the loop gone the moment the game starts.
    func testIPadHostWaitingScreen() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "hosting is the iPad's")
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = launch(["-t2p-loop-freeze", "5.4"])   // the T knocked loose, the little character on the "y"
        hostRoom(app, "rollcall")
        XCTAssertTrue(logo(app).waitForExistence(timeout: 10), "the loop on the host's waiting screen")
        sleep(2)
        screen("543-ipad-host-waiting-landscape")
        XCUIDevice.shared.orientation = .portrait
        sleep(2)
        XCTAssertTrue(logo(app).exists)
        screen("543-ipad-host-waiting-portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(1)

        // the TV picture, as the iPad shows it before a TV is picked
        tapWhenReady(app.buttons["host-tv"])
        tapWhenReady(app.buttons["tv-preview"])
        sleep(3)
        XCTAssertTrue(logo(app).exists, "the loop on the TV picture")
        screen("543-ipad-tv-picture")
        tapWhenReady(app.buttons["tv-close"])
        tapWhenReady(app.buttons["Done"])
        sleep(1)

        tapWhenReady(app.buttons["host-addbot-medium"]); sleep(1)
        tapWhenReady(app.buttons["host-addbot-hard"]); sleep(1)
        tapWhenReady(app.buttons["host-start"])
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: logo(app))
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 10), .completed, "the loop stops when the game starts")
        endHostedRoom(app)
    }

    /// Reduce Motion on the iPad host: the still mark, no video.
    func testIPadHostReduceMotion() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "hosting is the iPad's")
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = launch(["-t2p-reduce-motion"])
        hostRoom(app, "closeenough")
        XCTAssertTrue(logo(app).waitForExistence(timeout: 10))
        XCTAssertEqual(logo(app).value as? String, "still", "Reduce Motion shows the still mark")
        sleep(1)
        screen("543-ipad-host-waiting-reduce-motion")
        endHostedRoom(app)
    }

    /// The phone lobby: the loop beside the room's name, the code and the QR below it, readable.
    func testPhoneLobby() {
        let app = launch(["-t2p-loop-freeze", "5.4"])
        startAsOwner(app, game: "rollcall", bot: "easy")
        XCTAssertTrue(logo(app).waitForExistence(timeout: 10), "the loop in the lobby")
        sleep(2)
        shot(app, "543-\(device)-lobby")
        app.buttons["leave"].tap()
        tapWhenReady(app.buttons["Leave the room"], 5)
    }

    /// The intro plays in place of one pass, then the loop comes back; the game starting stops it.
    func testIntroReplayThenGameStarts() {
        let app = launch(["-t2p-loop-pass", "4"])   // the cycle starts on its last loop pass, so the intro is next
        startAsOwner(app, game: "rollcall", bot: "easy")
        let l = logo(app)
        XCTAssertTrue(l.waitForExistence(timeout: 10))
        print("LOOP first pass: \(l.value as? String ?? "nil")")
        let intro = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'intro'"), object: l)
        XCTAssertEqual(XCTWaiter().wait(for: [intro], timeout: 15), .completed, "the intro plays in place of the sixth pass")
        let t0 = Date()
        let back = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'loop'"), object: l)
        XCTAssertEqual(XCTWaiter().wait(for: [back], timeout: 8), .completed, "back to the loop after the intro")
        print("LOOP intro pass took about \(String(format: "%.1f", Date().timeIntervalSince(t0))) s")
        tapWhenReady(app.buttons["start-game"])
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: l)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 10), .completed, "the loop stops when the game starts")
    }
}
