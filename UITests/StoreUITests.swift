import XCTest

/// The App Store screenshots (#407), taken on the store workflow's iPhone and iPad simulators. Offline rooms with bots
/// only, so the pictures never depend on the network or show a real player. Names sort in the listing's order.
final class StoreUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    private var device: String { UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone" }

    private func joinOffline(_ app: XCUIApplication, _ game: String) {
        let b = app.buttons["offline-\(game)"]
        if !(b.exists && b.isHittable) { app.swipeUp() }
        tapWhenReady(app.buttons["offline-\(game)"])
        let name = app.textFields["name"]
        if name.waitForExistence(timeout: 10) { name.tap(); name.typeText("Alex"); tapWhenReady(app.buttons["join-room"]) }
    }

    func testStoreShots() {
        var app = launch()
        XCTAssertTrue(app.textFields["room-code"].waitForExistence(timeout: 10))
        sleep(1)
        shot(app, "store-\(device)-1-play")

        // Overdraft against bots: the owner's lobby, then the table when it's your turn
        joinOffline(app, "overdraft")
        tapWhenReady(app.buttons["addbot-easy"]); sleep(1)
        app.buttons["addbot-normal"].tap(); sleep(1)
        app.buttons["addbot-normal"].tap(); sleep(1)
        shot(app, "store-\(device)-2-lobby")
        tapWhenReady(app.buttons["start-game"])
        XCTAssertTrue(app.buttons["draw"].waitForExistence(timeout: 10))
        _ = app.staticTexts["your-turn"].waitForExistence(timeout: 90)
        sleep(1)
        shot(app, "store-\(device)-3-overdraft")

        // Hot Dice after a roll
        app = launch()
        XCTAssertTrue(app.textFields["room-code"].waitForExistence(timeout: 10))
        joinOffline(app, "farkle")
        tapWhenReady(app.buttons["addbot-bold"]); sleep(1)
        tapWhenReady(app.buttons["start-game"])
        let roll = app.buttons["roll"]
        XCTAssertTrue(waitEnabled(roll, 60))
        roll.tap(); sleep(3)
        shot(app, "store-\(device)-4-hot-dice")

        // The Library
        app = launch()
        XCTAssertTrue(app.textFields["room-code"].waitForExistence(timeout: 10))
        // iPad shows the tabs along the top, not in a tab bar
        let tab = app.tabBars.buttons["Library"]
        tapWhenReady(tab.waitForExistence(timeout: 5) ? tab : app.buttons["Library"].firstMatch); sleep(3)
        // #487: no card named after a real TV game show (App Review checks names, guideline 5.2.1)
        let labelled = { (words: String) in app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", words)).firstMatch }
        XCTAssertTrue(labelled("Live Buzzer").waitForExistence(timeout: 10), "the website's cards have loaded")
        for show in ["Millionaire", "Jeopardy", "America Says", "Chain Reaction", "Impossible"] {
            XCTAssertFalse(labelled(show).exists, "the Library leaves out \(show)")
        }
        shot(app, "store-\(device)-5-library")
    }
}
