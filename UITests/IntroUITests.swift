import XCTest

/// The intro at launch (wayloncore/tyleralocke#562): its frames at real size, that it gives way to Play on its own,
/// that a tap skips it, Reduce Motion's still, and that a link goes straight in. The Mac workflow's iPad pass runs the
/// frames again, where the portrait clip must sit in the middle on navy, never stretched.
final class IntroUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    override func tearDown() { XCUIDevice.shared.orientation = .portrait }
    private var device: String { UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone" }

    /// Start, middle and end of the clip, stopped there, on this device.
    func testIntroFrames() {
        for (name, at) in [("start", "0"), ("mid", "1.0"), ("end", "2.25")] {
            let app = launch(["-t2p-intro", "-t2p-intro-freeze", at])
            XCTAssertTrue(app.descendants(matching: .any)["intro"].waitForExistence(timeout: 10), "the intro shows at launch")
            sleep(2)   // the clip is ready and on that frame
            shot(app, "562-\(device)-intro-\(name)")
            if name == "end" && device == "ipad" {
                XCUIDevice.shared.orientation = .landscapeLeft
                sleep(2)
                shot(app, "562-ipad-intro-end-landscape")
                XCUIDevice.shared.orientation = .portrait
            }
            app.terminate()
        }
    }

    /// It plays about 2 seconds, then cross-fades into Play by itself.
    func testIntroPlaysThenPlay() {
        let app = launch(["-t2p-intro"])
        let intro = app.descendants(matching: .any)["intro"]
        // launch() returns once the app settles, which can be partway through the clip (testIntroFrames shows it)
        print("INTRO still showing when launch() returned: \(intro.exists)")
        let t0 = Date()
        let gone = NSPredicate(format: "exists == false")
        let wait = XCTNSPredicateExpectation(predicate: gone, object: intro)
        XCTAssertEqual(XCTWaiter().wait(for: [wait], timeout: 6), .completed, "the intro gives way to Play")
        let took = Date().timeIntervalSince(t0)
        print("INTRO took \(String(format: "%.2f", took)) s from launch() returning to gone")
        XCTAssertTrue(app.textFields["room-code"].waitForExistence(timeout: 5))
        sleep(1)
        shot(app, "562-\(device)-play-after")
    }

    /// A tap skips it.
    func testTapSkips() throws {
        let app = launch(["-t2p-intro"])
        let intro = app.descendants(matching: .any)["intro"]
        guard intro.exists else { throw XCTSkip("the clip had ended before launch() returned, so there was nothing to tap") }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let wait = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: intro)
        XCTAssertEqual(XCTWaiter().wait(for: [wait], timeout: 1.5), .completed, "a tap skips the intro")
        XCTAssertTrue(app.textFields["room-code"].waitForExistence(timeout: 3))
    }

    /// Reduce Motion: the finished mark, no clip, then Play.
    func testReduceMotionStill() {
        var app = launch(["-t2p-intro", "-t2p-reduce-motion", "-t2p-intro-freeze", "0"])
        XCTAssertTrue(app.descendants(matching: .any)["intro"].waitForExistence(timeout: 5))
        sleep(1)
        shot(app, "562-\(device)-intro-reduce-motion")
        app.terminate()
        app = launch(["-t2p-intro", "-t2p-reduce-motion"])
        let intro = app.descendants(matching: .any)["intro"]
        let wait = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: intro)
        XCTAssertEqual(XCTWaiter().wait(for: [wait], timeout: 3), .completed, "Reduce Motion's still is quick")
    }

    /// A link that opens the app goes straight in: no intro. The app is opened cold by the system, the way a link,
    /// a widget or an alert opens it, with the intro on (no test switches on that launch).
    func testALinkSkipsTheIntro() {
        let app = launch(["-t2p-intro"])
        app.terminate()
        XCUIDevice.shared.system.open(URL(string: "time2play://play")!)
        // the system may ask first ("Open in Time2Play?")
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let open = springboard.buttons["Open"]
        if open.waitForExistence(timeout: 3) { open.tap() }
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "the link opened the app")
        XCTAssertTrue(app.textFields["room-code"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["intro"].exists, "a link skips the intro")
        shot(app, "562-\(device)-link-straight-in")
    }
}
