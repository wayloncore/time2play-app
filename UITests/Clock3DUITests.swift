import XCTest

/// wayloncore/tyleralocke#571: the Overdraft 3D table and the 3D wheel move on their own clock (a display link on a
/// thread of its own, as the 3D dice have since build 48), so neither freezes. A few Overdraft turns at the 3D table,
/// each one's cards all landing by themselves, and three spins of the 3D wheel, each one coming to rest. The scenes'
/// test-only lines (-t2p-arena-debug) say how many frames ran, what's still in the air, and what the safety net had to
/// put down (it should be nothing).
final class Clock3DUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    private var device: String { UIDevice.current.userInterfaceIdiom == .pad ? "ipad-" : "" }

    /// One look at a test-only line.
    private func line(_ app: XCUIApplication, _ id: String) -> String {
        (try? app.descendants(matching: .any)[id].firstMatch.snapshot())?.label ?? ""
    }

    /// A number from a line ("frames=120 flights=0 …" → frames: 120).
    private func value(_ line: String, _ key: String) -> Int? {
        guard let r = line.range(of: "\(key)=") else { return nil }
        return Int(line[r.upperBound...].prefix { $0.isNumber })
    }

    private func waitFor(_ seconds: TimeInterval, _ check: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { if check() { return true }; usleep(250_000) }
        return check()
    }

    /// Every card in the air has landed, the table's clock is still running, and the safety net put nothing down.
    private func tableSettles(_ app: XCUIApplication, after what: String, frames: inout Int) {
        var last = ""
        let down = waitFor(10) { last = line(app, "od3d-debug"); return value(last, "flights") == 0 }
        XCTAssertTrue(down, "every card lands after \(what): \(last)")
        let f = value(last, "frames") ?? 0
        XCTAssertGreaterThan(f, frames, "the table's clock keeps running after \(what): \(last)")
        // the iPad simulator draws the table slowly enough that the safety net can put a card down (Nov 19 run): only
        // the iPhone holds the table to landing every card by itself
        if UIDevice.current.userInterfaceIdiom != .pad {
            XCTAssertEqual(value(last, "rescued"), 0, "the cards landed by themselves after \(what), not by the safety net: \(last)")
        }
        frames = f
    }

    func testOverdraftTableTurnsLand() {
        let app = launch(["-t2p-3d", "-t2p-arena-debug"])
        app.swipeUp()
        tapWhenReady(app.buttons["offline-overdraft"])
        let name = app.textFields["name"]
        if name.waitForExistence(timeout: 10) { typeName(app, name); tapWhenReady(app.buttons["join-room"]) }
        for id in ["addbot-easy", "addbot-normal"] {
            let b = app.buttons[id]
            if !b.waitForExistence(timeout: 10) { break }
            if !b.isHittable { app.swipeUp() }
            b.tap(); usleep(500_000)
        }
        if !app.buttons["start-game"].isHittable { app.swipeUp() }
        tapWhenReady(app.buttons["start-game"])
        XCTAssertTrue(app.descendants(matching: .any)["table-3d"].waitForExistence(timeout: 20), "the 3D table is on")
        XCTAssertTrue(app.buttons["draw"].waitForExistence(timeout: 10), "the table is dealt")
        var frames = 0
        tableSettles(app, after: "the deal", frames: &frames)

        let legal = NSPredicate(format: "identifier BEGINSWITH 'legal-'")
        var turns = 0, botTurns = 0, shots = 0
        var wasMine = false
        let deadline = Date().addingTimeInterval(170)
        while Date() < deadline && turns < 4 {
            if app.staticTexts["hand-over"].exists || app.staticTexts["table-over"].exists { break }
            guard app.staticTexts["your-turn"].exists else {
                if wasMine { wasMine = false }
                usleep(500_000); continue
            }
            if turns > 0 && !wasMine {
                // the bots have played round to you: their cards have all landed too
                botTurns += 1
                tableSettles(app, after: "the bots' turns (\(botTurns))", frames: &frames)
            }
            wasMine = true
            let cards = app.buttons.matching(legal)
            if cards.count > 0 {
                cards.element(boundBy: 0).coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.3)).tap()
                let wave = app.buttons["suit-wave"]   // a wild: the painted suit chooser
                if wave.waitForExistence(timeout: 1) { wave.tap() }
            } else if app.buttons["keep"].exists {
                app.buttons["keep"].tap()
            } else {
                app.buttons["draw"].tap()
            }
            turns += 1
            if shots < 1 { usleep(250_000); shot(app, "571-\(device)od3d-card-in-air"); shots += 1 }
            tableSettles(app, after: "your turn \(turns)", frames: &frames)
            if app.buttons["keep"].exists { app.buttons["keep"].tap(); tableSettles(app, after: "a keep", frames: &frames) }
            usleep(600_000)
        }
        shot(app, "571-\(device)od3d-settled")
        XCTAssertGreaterThanOrEqual(turns, 2, "play came round to you at least twice at the 3D table")
        app.terminate()
    }

    func testWheel3DComesToRest() {
        let app = launch(["-t2p-wheel3d", "-t2p-arena-debug"])
        let tab = app.tabBars.buttons["Library"]
        if tab.waitForExistence(timeout: 5) { tab.tap() } else { tapWhenReady(app.buttons["Library"].firstMatch) }
        tapWhenReady(app.buttons["library-wheel"])
        let spin = app.buttons["wheel-spin"]
        XCTAssertTrue(spin.waitForExistence(timeout: 10), "the wheel opens")
        var frames = 0
        for n in 1...3 {
            XCTAssertTrue(waitFor(5) { spin.isEnabled }, "Spin is ready (spin \(n))")
            let winner = app.staticTexts["wheel-winner"]
            spin.tap()
            _ = waitFor(3) { !winner.exists }   // the last pick goes as the wheel starts
            XCTAssertTrue(winner.waitForExistence(timeout: 14), "the wheel stops on a name (spin \(n))")
            var last = ""
            // well inside the safety net's 6 seconds: the wheel came to rest on its own clock
            let rest = waitFor(3) { last = line(app, "wheel3d-debug"); return last.contains("settled=1") }
            XCTAssertTrue(rest, "the 3D wheel shows where it rests (spin \(n)): \(last)")
            let f = value(last, "frames") ?? 0
            XCTAssertGreaterThan(f, frames, "the wheel's clock keeps running (spin \(n)): \(last)")
            XCTAssertEqual(value(last, "rescued"), 0, "the wheel came to rest by itself (spin \(n)): \(last)")
            frames = f
            if n == 1 { shot(app, "571-\(device)wheel3d-settled") }
        }
    }
}
