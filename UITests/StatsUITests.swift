import XCTest

/// Stats and achievements (#540): You shows the games played, wins, best scores and the favorite game, and the
/// achievements list marks what's earned (a ledger filled by -t2p-ledger-demo: six online games).
final class StatsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testStatsAndAchievements() {
        let app = launch(["-t2p-ledger-demo"])
        tapWhenReady(app.tabBars.buttons["You"])
        let totals = app.descendants(matching: .any)["stats-totals"].firstMatch
        if !totals.waitForExistence(timeout: 5) { app.swipeUp() }
        XCTAssertTrue(totals.waitForExistence(timeout: 5), "the totals show")
        XCTAssertTrue(totals.label.contains("6"), totals.label)
        shot(app, "540-stats-1-you")
        // the list draws rows as they come on screen
        let fav = app.descendants(matching: .any)["stats-favorite"].firstMatch
        if !fav.waitForExistence(timeout: 3) { app.swipeUp() }
        XCTAssertTrue(fav.waitForExistence(timeout: 5), "the favorite game shows")
        XCTAssertTrue(fav.label.contains("Hot Dice"), fav.label)
        let ach = app.buttons["achievements"]
        if !ach.waitForExistence(timeout: 3) { app.swipeUp() }
        tapWhenReady(ach)
        let first = app.descendants(matching: .any)["achievement-t2p.first_win"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertEqual(first.value as? String, "Earned")
        XCTAssertEqual(app.descendants(matching: .any)["achievement-t2p.games_50"].firstMatch.value as? String, "12 percent")
        shot(app, "540-stats-2-achievements")
    }
}
