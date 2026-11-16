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
                app.sliders["ce-low"].adjust(toNormalizedSliderPosition: 0.35)
                app.sliders["ce-high"].adjust(toNormalizedSliderPosition: 0.65)
                shot(app, "489-ce-3-question")
            }
            lock.tap()
            if n == 1 { usleep(500_000); shot(app, "489-ce-4-locked-in") }
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
}
