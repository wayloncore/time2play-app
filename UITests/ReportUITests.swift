import XCTest

/// "Something slow or broken? Send a report" (wayloncore/tyleralocke#594 part 2): You opens the sheet, it shows what
/// goes with it, and Send thanks you. Under the UI tests nothing is sent (-uitest-reset): the app prints it instead.
final class ReportUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    private var device: String { UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone" }

    func testReportSheet() {
        let app = launch(["-t2p-name", "Sim"])
        tapWhenReady(app.tabBars.buttons["You"])
        let open = app.buttons["send-report"]
        for _ in 0..<12 where !(open.exists && open.isHittable) { app.swipeUp() }
        tapWhenReady(open)
        let send = app.buttons["report-send"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        XCTAssertFalse(send.isEnabled, "nothing to send until something's picked or written")
        tapWhenReady(app.buttons["report-slow"])
        XCTAssertTrue(send.isEnabled)
        let facts = app.staticTexts.matching(identifier: "report-fact").allElementsBoundByIndex.map(\.label)
        XCTAssertTrue(facts.contains { $0.hasPrefix("Device: ") } && facts.contains { $0.hasPrefix("iOS: ") }
                      && facts.contains { $0.hasPrefix("App: ") } && facts.contains { $0.hasPrefix("Last game: ") }, "\(facts)")
        sleep(1)
        shot(app, "594-\(device)-report")
        send.tap()
        XCTAssertTrue(app.descendants(matching: .any)["dialog-report-sent"].firstMatch.waitForExistence(timeout: 8), "thanks once it's sent")
        shot(app, "594-\(device)-report-sent")
    }
}
