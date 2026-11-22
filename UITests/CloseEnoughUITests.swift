import XCTest

/// Close Enough with no host (#489): a whole six-question game against Rosa and Viktor on the live server, with a
/// screenshot of each moment: the lobby and How to play, a question, locked in and waiting for the bots, the answer on
/// everyone's ranges with the points, what comes next, and the winner screen with Play again and Back to Library.
final class CloseEnoughUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testAWholeGameAgainstBots() {
        let app = launch()
        startAsOwner(app, game: "closeenough", bot: "medium")
        tapWhenReady(app.buttons["addbot-hard"])
        sleep(1)
        tapWhenReady(app.buttons["6"])                       // six questions
        sleep(1)
        shot(app, "489-ce-1-lobby")
        tapWhenReady(app.buttons["how-to-play"])
        XCTAssertTrue(app.staticTexts["how-to-lede"].waitForExistence(timeout: 5), "How to play opens in one tap")
        shot(app, "489-ce-2-how-to-play")
        tapWhenReady(app.buttons["how-to-done"])
        tapWhenReady(app.buttons["start-game"])

        for n in 1...6 {
            let lock = app.buttons["lock-in"]
            XCTAssertTrue(lock.waitForExistence(timeout: 30), "question \(n) is asked")
            if n == 1 {
                setRange(app, 0.35, 0.65)
                shot(app, "489-ce-3-question")
            }
            lock.tap()
            if n == 2 { shot(app, "489-ce-4-locked-in") }   // locked in at once: the bots are still thinking
            XCTAssertTrue(app.staticTexts["ce-answer"].waitForExistence(timeout: 70), "question \(n)'s answer is revealed")
            sleep(1)                                          // the answer lands on the ranges
            if n == 1 || n == 6 {
                shot(app, "489-ce-5-answer-q\(n)")
                app.swipeUp()
                usleep(400_000)
                shot(app, "489-ce-6-points-q\(n)")
            }
            tapWhenReady(app.buttons["ce-next"], 10)
        }
        XCTAssertTrue(app.staticTexts["game-over"].waitForExistence(timeout: 20), "the game ends with a winner")
        sleep(1)
        shot(app, "489-ce-7-winner")
        XCTAssertTrue(app.buttons["play-again"].exists, "the owner can play again")
        app.buttons["back-to-library"].tap()
        XCTAssertFalse(app.staticTexts["game-over"].waitForExistence(timeout: 3), "Back to Library leaves the room")
        shot(app, "489-ce-8-back-to-library")
    }

    /// #707 (Tyler: "make Close Enough actually how it looks on the website"): offline against a bot, the website's
    /// look is what a player gets: a question with a range set, locked in, and the answer with the ranges and points,
    /// shot at the phone's size to set beside time2play.live's own screens.
    func testTheWebsiteLook() {
        let app = launch()
        startOffline(app, "closeenough", bot: "medium")
        let lock = app.buttons["lock-in"]
        XCTAssertTrue(lock.waitForExistence(timeout: 20), "the first question is asked")
        XCTAssertTrue(app.staticTexts["ce-web"].exists, "the website's look is the default")
        XCTAssertFalse(app.descendants(matching: .any)["ce-board3d"].exists, "no 3D board unless it's turned on")
        setRange(app, 0.45, 0.62)
        usleep(400_000)
        XCTAssertTrue(app.staticTexts["ce-worth"].label.contains("worth"), "what the range is worth: \(app.staticTexts["ce-worth"].label)")
        shot(app, "707-ce-1-asking")
        lock.tap()
        if app.descendants(matching: .any)["ce-locked"].waitForExistence(timeout: 2) { shot(app, "707-ce-2-locked-in") }
        XCTAssertTrue(app.staticTexts["ce-answer"].waitForExistence(timeout: 80), "the answer is revealed")
        sleep(1)                                          // the answer's line lands on the scale
        XCTAssertTrue(app.staticTexts["ce-verdict"].exists, "the verdict says how your range did")
        shot(app, "707-ce-3-answer")
        app.swipeUp()
        usleep(400_000)
        shot(app, "707-ce-4-standings")
    }

    /// Sets the range with a finger. #707: the website look's sliders are drawn by the app (a tap or drag puts the knob
    /// there), so XCUITest's adjust can't drive them; the 3D board's are system sliders.
    private func setRange(_ app: XCUIApplication, _ lo: CGFloat, _ hi: CGFloat) {
        for (id, at) in [("ce-low", lo), ("ce-high", hi)] {
            let s = app.sliders[id]
            if app.staticTexts["ce-web"].exists {
                s.coordinate(withNormalizedOffset: CGVector(dx: at, dy: 0.5)).tap()
            } else {
                s.adjust(toNormalizedSliderPosition: at)
            }
            usleep(200_000)
        }
    }
}
