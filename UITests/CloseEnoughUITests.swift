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

    /// #726 (Tyler: "Can you not see the Close Enough game on my website? It looks nothing like it."): offline against a
    /// bot, the Library game's brass look is what a player gets: a question with the range set by dragging the brass
    /// handles, the plate moved by dragging it, locked in, and the answer with the needle, the result and the standings,
    /// shot at the phone's size to set beside the Library game's own screens.
    func testTheLibraryLook726() {
        let app = launch()
        startOfflineCE(app)
        let lock = app.buttons["lock-in"]
        XCTAssertTrue(lock.waitForExistence(timeout: 20), "the first question is asked")
        XCTAssertTrue(app.staticTexts["ce-web"].exists, "the brass look is the default")
        XCTAssertFalse(app.descendants(matching: .any)["ce-board3d"].exists, "no 3D board unless it's turned on")
        let serif = app.staticTexts["ce-serif"].label
        print("726 serif: \(serif)")
        XCTAssertEqual(serif, "Iowan Old Style", "the Library's serif")
        shot(app, "726-ce-0-opened")
        let before = app.staticTexts["ce-range"].label
        setRange(app, 0.45, 0.62)
        usleep(400_000)
        let after = app.staticTexts["ce-range"].label
        XCTAssertNotEqual(before, after, "dragging the handles changes the range: \(before) → \(after)")
        let worth = app.descendants(matching: .any)["ce-worth"].label
        XCTAssertTrue(worth.contains("Worth"), "what the range is worth: \(worth)")
        shot(app, "726-ce-1-asking")
        // the plate between the handles moves both
        let track = app.descendants(matching: .any)["ce-track"]
        let mid = track.coordinate(withNormalizedOffset: CGVector(dx: 0.535, dy: 0.55))
        mid.press(forDuration: 0.15, thenDragTo: track.coordinate(withNormalizedOffset: CGVector(dx: 0.36, dy: 0.55)))
        usleep(400_000)
        let moved = app.staticTexts["ce-range"].label
        print("726 ranges: \(before) → \(after) → \(moved)")
        XCTAssertNotEqual(after, moved, "dragging the plate moves the range")
        app.buttons["ce-type"].tap()
        XCTAssertTrue(app.textFields["ce-low-number"].waitForExistence(timeout: 2), "Type exact numbers opens the fields")
        shot(app, "726-ce-2-typed")
        app.buttons["ce-type"].tap()
        lock.tap()
        if app.descendants(matching: .any)["ce-locked"].waitForExistence(timeout: 2) { shot(app, "726-ce-3-locked-in") }
        XCTAssertTrue(app.staticTexts["ce-answer"].waitForExistence(timeout: 80), "the answer is revealed")
        sleep(1)                                          // the needle lands on the track
        XCTAssertTrue(app.staticTexts["ce-verdict"].exists, "the verdict says how your range did")
        shot(app, "726-ce-4-answer")
        scrollDown(app)
        usleep(400_000)
        shot(app, "726-ce-5-standings")
    }

    /// #726 at the largest text the game takes, with Reduce Motion: nothing cut off, the glow still.
    func testTheLibraryLookLargeText726() {
        let app = launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-t2p-reduce-motion"])
        startOfflineCE(app)
        XCTAssertTrue(app.buttons["lock-in"].waitForExistence(timeout: 20), "the first question is asked")
        sleep(1)
        shot(app, "726-ce-6-large-text")
        scrollDown(app)
        usleep(400_000)
        shot(app, "726-ce-7-large-text-lower")
    }

    /// Scrolls from low on the screen: the brass track takes a drag that starts on it, as the Library's does.
    private func scrollDown(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)))
    }

    /// Practice Close Enough against a bot. On a small iPhone its button sits off to the side of the offline row, so the
    /// row is swiped along to it first.
    private func startOfflineCE(_ app: XCUIApplication) {
        app.swipeUp()
        let b = app.buttons["offline-closeenough"]
        XCTAssertTrue(b.waitForExistence(timeout: 20), "Practice Close Enough is offered")
        var tries = 0
        while !b.isHittable && tries < 4 {
            let y = b.frame.midY / max(1, app.frame.height)
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: y)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: y)))
            tries += 1
        }
        tapWhenReady(b)
        let name = app.textFields["name"]
        if name.waitForExistence(timeout: 10) { typeName(app, name); tapWhenReady(app.buttons["join-room"]) }
        tapWhenReady(app.buttons["addbot-medium"]); sleep(1)
        tapWhenReady(app.buttons["start-game"])
    }

    /// Sets the range with a finger. #726: the brass handles are drawn by the app, so each is dragged along the track
    /// (the track's frame is the scale, end to end); the 3D board's are system sliders.
    private func setRange(_ app: XCUIApplication, _ lo: CGFloat, _ hi: CGFloat) {
        let track = app.descendants(matching: .any)["ce-track"]
        for (id, at) in [("ce-low", lo), ("ce-high", hi)] {
            let s = track.exists ? app.descendants(matching: .any)[id] : app.sliders[id]
            if track.exists {
                let f = track.frame, k = s.frame
                let from = track.coordinate(withNormalizedOffset: CGVector(dx: (k.midX - f.minX) / max(1, f.width), dy: 0.6))
                from.press(forDuration: 0.12, thenDragTo: track.coordinate(withNormalizedOffset: CGVector(dx: at, dy: 0.6)))
            } else {
                s.adjust(toNormalizedSliderPosition: at)
            }
            usleep(200_000)
        }
    }
}
