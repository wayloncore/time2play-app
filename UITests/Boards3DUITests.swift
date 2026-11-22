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

    /// #728 (Tyler: "I never want to scroll"): the 3D board look, offline against two bots, fits one screen with no page
    /// scroll while asking, and at the answer the result comes up as a pop-up card under the board with the standings
    /// and Next in it. Tapping outside hides it; "See the result" brings it back. The Mac run takes it on the iPhone SE
    /// and the largest iPhone too (older_only, largest_only).
    func testCloseEnoughBoardFits728() {
        let app = launch(["-t2p-ce3d"])
        startOfflineCE(app)
        let lock = app.buttons["lock-in"]
        XCTAssertTrue(lock.waitForExistence(timeout: 20), "the first question is asked")
        XCTAssertTrue(app.descendants(matching: .any)["ce-board3d"].exists, "the 3D board is on")
        sleep(1)
        shot(app, "728-\(device)ce-1-asking")
        checkAskingFits(app)
        lock.tap()
        checkAnswer(app, "728-\(device)ce")
    }

    /// #728 at the largest text the game takes, with Reduce Motion: still no page scroll, and the pop-up keeps Next
    /// pinned with only its middle scrolling if it must.
    func testCloseEnoughBoardFitsLargeText728() {
        let app = launch(["-t2p-ce3d", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-t2p-reduce-motion"])
        startOfflineCE(app)
        let lock = app.buttons["lock-in"]
        XCTAssertTrue(lock.waitForExistence(timeout: 20), "the first question is asked")
        sleep(1)
        shot(app, "728-ce-large-1-asking")
        checkAskingFits(app)
        lock.tap()
        checkAnswer(app, "728-ce-large")
    }

    /// Asking: the sliders and Lock are on screen, and a swipe up from the bottom moves nothing (no page scroll).
    private func checkAskingFits(_ app: XCUIApplication) {
        let lock = app.buttons["lock-in"], menu = app.buttons["room-menu"], board = app.descendants(matching: .any)["ce-board3d"]
        print("728 \(app.frame.size): lock \(lock.frame), board \(board.frame), menu \(menu.frame), scrolls: \(app.scrollViews.count)")
        XCTAssertTrue(lock.isHittable, "Lock is on screen")
        XCTAssertTrue(app.sliders["ce-low"].isHittable && app.sliders["ce-high"].isHittable, "both sliders are on screen")
        XCTAssertLessThanOrEqual(lock.frame.maxY, app.frame.maxY, "Lock isn't below the screen")
        XCTAssertGreaterThanOrEqual(menu.frame.minY, 0, "the bar isn't above the screen")
        let y0 = menu.frame.minY
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.97)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.25)))
        usleep(500_000)
        XCTAssertEqual(menu.frame.minY, y0, accuracy: 1, "the page doesn't scroll")
    }

    /// The answer: the board stays in view with every range, the result is a pop-up under it with the standings, Next is
    /// on screen; tap outside hides it, "See the result" brings it back, and Next goes on.
    private func checkAnswer(_ app: XCUIApplication, _ prefix: String) {
        XCTAssertTrue(app.staticTexts["ce-answer"].waitForExistence(timeout: 80), "the answer is revealed")
        let result = app.descendants(matching: .any)["ce-result"]
        XCTAssertTrue(result.waitForExistence(timeout: 6), "the result comes up as a pop-up")
        sleep(1)
        shot(app, "\(prefix)-2-answer")
        let board = app.descendants(matching: .any)["ce-ranges"], answer = app.staticTexts["ce-answer"]
        let st = app.descendants(matching: .any)["ce-standings"], next = app.buttons["ce-next"]
        let scrolls = app.descendants(matching: .any)["ce-result-scrolls"].exists
        print("728 \(app.frame.size): board \(board.frame), result \(result.frame), standings \(st.frame), next \(next.frame), middle scrolls: \(scrolls)")
        // (a slow simulator can run out the answer's clock before these checks: then they're skipped)
        if result.exists {
            XCTAssertGreaterThanOrEqual(result.frame.minY, board.frame.maxY + 4, "the pop-up stops under the board")
            XCTAssertLessThan(answer.frame.maxY, result.frame.minY, "the answer stays in view")
            XCTAssertTrue(st.exists, "the standings are in the pop-up")
            XCTAssertTrue(next.exists && next.isHittable, "Next is on screen")
            XCTAssertLessThanOrEqual(next.frame.maxY, app.frame.maxY)
        }
        // tap outside (on the board): the board whole; "See the result" brings it back (if the answer is still up)
        if answer.exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
            if app.buttons["ce-show-result"].waitForExistence(timeout: 3) {
                XCTAssertFalse(result.exists, "tapping outside hides the pop-up")
                shot(app, "\(prefix)-3-hidden")
                app.buttons["ce-show-result"].tap()
                XCTAssertTrue(result.waitForExistence(timeout: 3) || !answer.exists, "See the result brings it back")
            }
        }
        // tapped by where it is, so a clock that runs out between the check and the tap doesn't fail the test
        if next.exists, let f = Optional(next.frame), !f.isEmpty {
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: f.midX, dy: f.midY)).tap()
        }
        XCTAssertTrue(app.buttons["lock-in"].waitForExistence(timeout: 30), "the next question is asked")
        shot(app, "\(prefix)-4-next")
    }

    /// Practice Close Enough against two bots (three lanes on the board at the answer). On a small iPhone its button sits
    /// off to the side of the offline row, so the row is swiped along to it first.
    private func startOfflineCE(_ app: XCUIApplication) {
        app.swipeUp()
        let b = app.buttons["offline-closeenough"]
        XCTAssertTrue(b.waitForExistence(timeout: 20), "Practice Close Enough is offered")
        var tries = 0
        while b.frame.maxX > app.frame.maxX - 4 && tries < 4 {
            let y = b.frame.midY / max(1, app.frame.height)
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: y)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: y)))
            tries += 1
        }
        tapWhenReady(b)
        let name = app.textFields["name"]
        if name.waitForExistence(timeout: 10) { typeName(app, name); tapWhenReady(app.buttons["join-room"]) }
        tapWhenReady(app.buttons["addbot-medium"]); sleep(1)
        if app.buttons["addbot-hard"].waitForExistence(timeout: 3) { app.buttons["addbot-hard"].tap(); sleep(1) }
        tapWhenReady(app.buttons["start-game"])
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
