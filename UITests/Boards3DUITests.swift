import XCTest

/// The 3D boards (#535): Close Enough's board while a question is asked and as the answer drops, offline against two
/// bots; and the Wheel of Names, in 3D at rest, mid-spin (stopped a second in) and picked, then the flat wheel.
final class Boards3DUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    private var device: String { UIDevice.current.userInterfaceIdiom == .pad ? "ipad-" : "" }

    func testCloseEnoughBoard() {
        let app = launch(["-t2p-ce3d"])
        startOffline(app, "closeenough", bot: "medium")
        let lock = app.buttons["lock-in"]
        XCTAssertTrue(lock.waitForExistence(timeout: 20), "the first question is asked")
        XCTAssertTrue(app.descendants(matching: .any)["ce-board3d"].exists, "the 3D board is on")
        if app.sliders["ce-low"].waitForExistence(timeout: 20) {
            app.sliders["ce-low"].adjust(toNormalizedSliderPosition: 0.3)
            app.sliders["ce-high"].adjust(toNormalizedSliderPosition: 0.6)
        }
        sleep(1)
        shot(app, "535-\(device)ce-1-asking")
        lock.tap()
        XCTAssertTrue(app.staticTexts["ce-answer"].waitForExistence(timeout: 80), "the answer is revealed")
        usleep(700_000)
        shot(app, "535-\(device)ce-2-dropping")
        sleep(3)
        shot(app, "535-\(device)ce-3-landed")
        XCTAssertTrue(app.descendants(matching: .any)["ce-ranges"].exists, "the ranges board stands in for the chart")
    }

    private func openWheel(_ app: XCUIApplication) {
        // iPad (iOS 18 and up) draws its tabs at the top, outside a tab bar
        let tab = app.tabBars.buttons["Library"]
        if tab.waitForExistence(timeout: 5) { tab.tap() } else { tapWhenReady(app.buttons["Library"].firstMatch) }
        tapWhenReady(app.buttons["library-wheel"])
        XCTAssertTrue(app.buttons["wheel-spin"].waitForExistence(timeout: 10), "the wheel opens")
    }

    func testWheel3D() {
        var app = launch(["-t2p-wheel3d", "-t2p-wheel-pick", "2"])
        openWheel(app)
        XCTAssertTrue(app.descendants(matching: .any)["wheel-3d"].exists)
        sleep(1)
        shot(app, "535-\(device)wheel-1-3d")
        app.buttons["wheel-spin"].tap()
        let winner = app.staticTexts["wheel-winner"]
        XCTAssertTrue(winner.waitForExistence(timeout: 12), "the wheel stops on a name")
        XCTAssertEqual(winner.label, "Casey", "it lands where it planned")
        sleep(1)
        shot(app, "535-\(device)wheel-2-3d-picked")
        app.terminate()

        app = launch(["-t2p-wheel3d", "-t2p-wheel-freeze", "0.9"])
        openWheel(app)
        app.buttons["wheel-spin"].tap()
        sleep(2)
        shot(app, "535-\(device)wheel-3-3d-spinning")
        app.terminate()

        app = launch(["-t2p-wheel-flat", "-t2p-wheel-pick", "5"])
        openWheel(app)
        XCTAssertTrue(app.descendants(matching: .any)["wheel-flat"].exists)
        app.buttons["wheel-spin"].tap()
        XCTAssertTrue(app.staticTexts["wheel-winner"].waitForExistence(timeout: 12))
        XCTAssertEqual(app.staticTexts["wheel-winner"].label, "Finley")
        shot(app, "535-\(device)wheel-4-flat-picked")
    }
}
