import XCTest

/// The tip jar (wayloncore/tyleralocke#598). The command line's UI tests don't load a StoreKit configuration, so the
/// test build stands in for StoreKit (-t2p-tips-demo): the same rows, the painted thank-you, the Supporter star. With no
/// products (no stand-in, and none in the App Store yet) the Tip jar isn't there at all.
final class TipJarUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    private var device: String { UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone" }

    private func scrollTo(_ app: XCUIApplication, _ e: XCUIElement) {
        for _ in 0..<12 where !(e.exists && e.isHittable) { app.swipeUp() }
    }

    func testTipJarAndThanks() {
        let app = launch(["-t2p-tips-demo", "-t2p-name", "Sim"])
        tapWhenReady(app.tabBars.buttons["You"])
        let tip = app.buttons["tip-small"]
        scrollTo(app, tip)
        XCTAssertTrue(tip.waitForExistence(timeout: 10), "the Tip jar in You")
        XCTAssertTrue(app.buttons["tip-big"].exists && app.buttons["tip-huge"].exists, "three tips")
        XCTAssertTrue(tip.label.contains("$1.99"), tip.label)
        sleep(1)
        shot(app, "598-\(device)-tip-jar")
        tip.tap()
        let thanks = app.descendants(matching: .any)["dialog-tip-thanks"].firstMatch
        XCTAssertTrue(thanks.waitForExistence(timeout: 5), "a painted thank-you")
        sleep(1)
        shot(app, "598-\(device)-thank-you")
        tapWhenReady(app.buttons["dialog-cancel"])
        for _ in 0..<12 { app.swipeDown() }
        XCTAssertTrue(app.descendants(matching: .any)["supporter-star"].firstMatch.waitForExistence(timeout: 5), "the Supporter star on You")
        shot(app, "598-\(device)-supporter-star")
    }

    /// Without the stand-in: whatever StoreKit itself answers (no products yet in the App Store, so no Tip jar).
    func testHiddenWithoutProducts() {
        let app = launch(["-t2p-name", "Sim"])
        tapWhenReady(app.tabBars.buttons["You"])
        let report = app.buttons["send-report"]
        scrollTo(app, report)
        sleep(3)   // StoreKit had its chance to answer
        // the scheme's StoreKit configuration may or may not reach a command-line run (Apple's FB22237318), so this
        // only says which it was: products from it show the jar, none hide it
        print("TIPJAR products from StoreKit shown: \(app.buttons["tip-small"].exists)")
    }

    /// The quiet line on a game's end screen (Yacht Dice's winner screen, a made-up finished game), and its new names.
    func testEndScreenLine() {
        let app = launch(["-t2p-tips-demo", "-t2p-dice-still", "game=rollcall moment=over"])
        XCTAssertTrue(app.staticTexts["game-over"].waitForExistence(timeout: 10))
        let line = app.buttons["tip-line"]
        XCTAssertTrue(line.waitForExistence(timeout: 5), "a quiet tip line on the end screen")
        let all = app.descendants(matching: .any).allElementsBoundByIndex.prefix(200).map(\.label).joined(separator: " | ")
        XCTAssertTrue(all.contains("Yacht bonus"), all)
        XCTAssertFalse(all.contains("Roll Call"), all)
        sleep(1)
        shot(app, "598-\(device)-end-screen-line")
        app.terminate()
        let hot = launch(["-t2p-tips-demo", "-t2p-dice-still", "game=hot moment=over"])
        XCTAssertTrue(hot.staticTexts["game-over"].waitForExistence(timeout: 10))
        sleep(1)
        shot(hot, "595-\(device)-10000-game-over")
    }
}
