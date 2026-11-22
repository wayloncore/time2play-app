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
        var app = launch(["-t2p-3d", "-t2p-dice3d"])
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
        app = launch(["-t2p-3d", "-t2p-dice3d"])
        XCTAssertTrue(app.textFields["room-code"].waitForExistence(timeout: 10))
        joinOffline(app, "farkle")
        tapWhenReady(app.buttons["addbot-bold"]); sleep(1)
        tapWhenReady(app.buttons["start-game"])
        let roll = app.buttons["roll"]
        XCTAssertTrue(waitEnabled(roll, 60))
        roll.tap(); sleep(3)
        shot(app, "store-\(device)-4-hot-dice")

        // The Library
        app = launch(["-t2p-3d", "-t2p-dice3d"])
        XCTAssertTrue(app.textFields["room-code"].waitForExistence(timeout: 10))
        // iPad shows the tabs along the top, not in a tab bar
        let tab = app.tabBars.buttons["Library"]
        tapWhenReady(tab.waitForExistence(timeout: 5) ? tab : app.buttons["Library"].firstMatch); sleep(3)
        // #487: no card named after a real TV game show (App Review checks names, guideline 5.2.1)
        // #720: the Library's rows load lazily, so on a smaller phone (mac.yml's simulator) the website's cards below the
        // fold aren't on screen to find. Wait for them to arrive (more rows than the app's own games and the wheel),
        // then scroll through the whole list: "Live Buzzer" is in it, and no row anywhere is named after a TV show.
        let start = Date()
        // the app's 4 games and the wheel are 5 rows (and a line if the Library can't load)
        while Date().timeIntervalSince(start) < 15 && app.cells.count <= 6 { usleep(300_000) }
        // A row's label is its title, then its line and its details, after commas. #487 leaves out cards NAMED after a
        // show; a line may still mention one (Nov 22: the AI Trainer Prompt Library's "a whole Jeopardy board").
        var found = false
        var titles = Set<String>()
        func look(_ e: XCUIElementSnapshot) {
            if [XCUIElement.ElementType.button, .link, .cell].contains(e.elementType), !e.label.isEmpty {
                titles.insert(e.label.components(separatedBy: ", ").first ?? e.label)
                if e.label.contains("Live Buzzer") { found = true }
            }
            e.children.forEach(look)
        }
        for _ in 0..<14 {
            if let snap = try? app.snapshot() { look(snap) }
            app.swipeUp(velocity: .fast)
        }
        for show in ["Millionaire", "Jeopardy", "America Says", "Chain Reaction", "Impossible"] {
            XCTAssertFalse(titles.contains { $0.localizedCaseInsensitiveContains(show) }, "the Library leaves out \(show): \(titles.sorted())")
        }
        XCTAssertTrue(found, "the website's cards have loaded")
        // back to the top for the picture
        let first = app.buttons["library-start-overdraft"]
        for _ in 0..<20 where !(first.exists && first.isHittable) { app.swipeDown(velocity: .fast) }
        sleep(1)
        shot(app, "store-\(device)-5-library")
    }
}
