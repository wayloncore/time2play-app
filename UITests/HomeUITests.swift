import XCTest

/// Play (#399): the code boxes, joining a real room by code, the Library, light mode and the largest text.
final class HomeUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testJoinBoxNormalizesTheCode() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Join with a room code"].waitForExistence(timeout: 10))
        shot(app, "399-home")
        let join = app.buttons["join"]
        XCTAssertFalse(join.isEnabled, "Join waits for a full code")
        let field = app.textFields["room-code"]
        field.tap()
        field.typeText("k7-q0p")   // the dash and the 0 (a lookalike) are dropped
        XCTAssertTrue(app.buttons["Join K7QP"].waitForExistence(timeout: 5))
        XCTAssertTrue(join.isEnabled)
        shot(app, "399-home-typed-code")
    }

    /// Done-when for #399: join a real room by its code from the simulator. (Staging is behind the studio's sign-in,
    /// which a GitHub Mac can't pass, so this uses a live room; hostless rooms are on there since Nov 16.)
    func testJoinARealRoomByCode() throws {
        let code = try startRoom("overdraft")
        let app = launch()
        let field = app.textFields["room-code"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap(); field.typeText(code)
        tapWhenReady(app.buttons["Join \(code)"])
        let name = app.textFields["name"]
        XCTAssertTrue(name.waitForExistence(timeout: 20), "the name and face picker opens once the room is found")
        name.tap(); name.typeText("Sim")
        shot(app, "399-name-and-face")
        tapWhenReady(app.buttons["join-room"])
        XCTAssertTrue(app.staticTexts["room-code-shown"].waitForExistence(timeout: 20), "in the room's lobby")
        XCTAssertTrue(app.descendants(matching: .any)["owner-chip"].exists, "the first person in a hostless room owns it")
        shot(app, "399-joined-lobby")
        app.buttons["leave"].tap()
        tapWhenReady(app.buttons["Leave the room"], 5)
        XCTAssertTrue(app.staticTexts["Join with a room code"].waitForExistence(timeout: 10))
    }

    func testAWrongCodeSaysSo() {
        let app = launch()
        let field = app.textFields["room-code"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap(); field.typeText("ZZZ9")
        app.buttons["Join ZZZ9"].tap()
        XCTAssertTrue(app.alerts["Can’t join"].waitForExistence(timeout: 20))
        shot(app, "399-no-such-room")
        app.alerts.buttons["OK"].tap()
    }

    func testLibrary() {
        let app = launch()
        tapWhenReady(app.tabBars.buttons["Library"])
        XCTAssertTrue(app.buttons["library-start-overdraft"].waitForExistence(timeout: 10))
        sleep(3)  // the server's Library loads
        shot(app, "399-library")
    }

    func testLightModeAndLargestText() {
        let app = launch(["-t2p-light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(app.textFields["room-code"].waitForExistence(timeout: 10))
        shot(app, "399-home-light-largest-text")
        app.swipeUp()
        shot(app, "399-home-light-largest-text-start")
    }
}
