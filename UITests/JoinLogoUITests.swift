import XCTest

/// The logo as a joined room opens (wayloncore/tyleralocke#596): the intro's clip plays once over a room you join by
/// its code, a tap skips it, Reduce Motion shows the still mark, and the lobby's loop carries on while the room waits.
/// Your own new room goes straight in. The rooms are real ones on tyleralocke.com, started the way the app starts one.
final class JoinLogoUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    private var device: String { UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone" }

    private func joinByCode(_ app: XCUIApplication, _ code: String) {
        let field = app.textFields["room-code"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap(); field.typeText(code)
        tapWhenReady(app.buttons["Join \(code)"])
    }

    /// Its frame mid-clip at real size, stopped there.
    func testJoinLogoFrame() throws {
        let code = try startRoom("rollcall")
        let app = launch(["-t2p-join-intro", "-t2p-join-freeze", "1.0"])
        joinByCode(app, code)
        let logo = app.descendants(matching: .any)["join-intro"]
        XCTAssertTrue(logo.waitForExistence(timeout: 20), "the logo plays as the joined room opens")
        sleep(2)
        shot(app, "596-\(device)-join-logo")
    }

    /// It plays about 2 seconds and gives way to the room; then the lobby's loop. A tap skips it next time.
    func testJoinLogoPlaysThenLobby() throws {
        let code = try startRoom("rollcall")
        var app = launch(["-t2p-join-intro", "-t2p-name", "Sim"])
        joinByCode(app, code)
        let logo = app.descendants(matching: .any)["join-intro"]
        XCTAssertTrue(logo.waitForExistence(timeout: 20), "the logo plays as the joined room opens")
        let t0 = Date()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: logo)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 6), .completed, "it gives way to the room by itself")
        print("JOINLOGO gone after \(String(format: "%.2f", Date().timeIntervalSince(t0))) s")
        let name = app.textFields["name"]
        if name.waitForExistence(timeout: 10) { tapWhenReady(app.buttons["join-room"]) }
        XCTAssertTrue(app.staticTexts["room-code-shown"].waitForExistence(timeout: 20), "in the room's lobby")
        let loop = app.descendants(matching: .any)["waiting-loop"].firstMatch
        XCTAssertTrue(loop.waitForExistence(timeout: 10), "the lobby's loop while the room waits")
        XCTAssertEqual(loop.value as? String, "loop")
        sleep(1)
        shot(app, "596-\(device)-lobby-loop")
        app.terminate()

        // a tap skips it (a new room, so this phone has no seat in it)
        let code2 = try startRoom("rollcall")
        app = launch(["-t2p-join-intro", "-t2p-name", "Sim"])
        joinByCode(app, code2)
        let logo2 = app.descendants(matching: .any)["join-intro"]
        XCTAssertTrue(logo2.waitForExistence(timeout: 20))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let skipped = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: logo2)
        XCTAssertEqual(XCTWaiter().wait(for: [skipped], timeout: 1.5), .completed, "a tap skips it")
    }

    /// Reduce Motion: the still mark, then the room. Your own new room: straight in, no logo.
    func testReduceMotionAndOwnRoom() throws {
        let code = try startRoom("closeenough")
        var app = launch(["-t2p-join-intro", "-t2p-reduce-motion", "-t2p-join-freeze", "0"])
        joinByCode(app, code)
        let logo = app.descendants(matching: .any)["join-intro"]
        XCTAssertTrue(logo.waitForExistence(timeout: 20))
        XCTAssertEqual(logo.value as? String, "still", "Reduce Motion shows the still mark")
        sleep(1)
        shot(app, "596-\(device)-join-logo-reduce-motion")
        app.terminate()

        app = launch(["-t2p-join-intro", "-t2p-name", "Sim"])
        tapWhenReady(app.buttons["start-rollcall"])
        XCTAssertTrue(app.descendants(matching: .any)["owner-chip"].waitForExistence(timeout: 20), "your own room opens")
        XCTAssertFalse(app.descendants(matching: .any)["join-intro"].exists, "no logo for a room you start")
    }
}
