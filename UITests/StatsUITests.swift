import XCTest

/// Stats and achievements (#540): You shows the games played, wins, best scores and the favorite game, and the
/// achievements list marks what's earned (a ledger filled by -t2p-ledger-demo: six online games).
final class StatsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testStatsAndAchievements() {
        let app = launch(["-t2p-ledger-demo"])
        tapWhenReady(app.tabBars.buttons["You"])
        let totals = app.descendants(matching: .any)["stats-totals"]
        if !totals.waitForExistence(timeout: 5) { app.swipeUp() }
        XCTAssertTrue(totals.waitForExistence(timeout: 5), "the totals show")
        XCTAssertTrue(totals.label.contains("6"), totals.label)
        XCTAssertTrue(app.staticTexts["Favorite: Hot Dice"].exists || app.descendants(matching: .any)["stats-favorite"].exists)
        shot(app, "540-stats-1-you")
        tapWhenReady(app.buttons["achievements"])
        let first = app.descendants(matching: .any)["achievement-t2p.first_win"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertEqual(first.value as? String, "Earned")
        XCTAssertEqual(app.descendants(matching: .any)["achievement-t2p.games_50"].value as? String, "12 percent")
        shot(app, "540-stats-2-achievements")
    }
}
