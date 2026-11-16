import XCTest

/// The home screen on the simulator: the join box takes a typed code and the button names it.
final class HomeUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testJoinBoxNormalizesTheCode() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Join a game"].waitForExistence(timeout: 10))
        let join = app.buttons["join"]
        XCTAssertFalse(join.isEnabled, "Join waits for a full code")
        let field = app.textFields["room-code"]
        field.tap()
        field.typeText("k7-qp")
        XCTAssertTrue(app.buttons["Join K7QP"].waitForExistence(timeout: 5))
        XCTAssertTrue(join.isEnabled)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "home-typed-code"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
