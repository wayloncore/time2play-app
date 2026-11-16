import XCTest

/// Accounts (#403) and invite links (#404).
final class AccountUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func pickYear(_ app: XCUIApplication, _ year: String) {
        tapWhenReady(app.buttons["birth-year"])
        tapWhenReady(app.buttons[year].firstMatch, 5)
    }

    /// Guest first: signing in is optional and asks the neutral age question first; under 13 stays a guest.
    func testSignInAsksAgeFirst() {
        let app = launch()
        tapWhenReady(app.tabBars.buttons["You"])
        shot(app, "403-you-guest")
        tapWhenReady(app.buttons["sign-in"])
        let year = String(Calendar.current.component(.year, from: Date()) - 9)
        pickYear(app, year)
        shot(app, "403-age-question")
        tapWhenReady(app.buttons["age-continue"])
        XCTAssertTrue(app.staticTexts["under-13"].waitForExistence(timeout: 5) || app.descendants(matching: .any)["under-13"].exists)
        shot(app, "403-under-13")
    }

    func testThirteenAndUpGetsSignInWithApple() {
        let app = launch()
        tapWhenReady(app.tabBars.buttons["You"])
        tapWhenReady(app.buttons["sign-in"])
        pickYear(app, String(Calendar.current.component(.year, from: Date()) - 30))
        tapWhenReady(app.buttons["age-continue"])
        XCTAssertTrue(app.buttons["apple-sign-in"].waitForExistence(timeout: 5) || app.descendants(matching: .any)["apple-sign-in"].exists)
        shot(app, "403-sign-in-with-apple")
    }

    /// App Review's sign-in, friends, then delete account. Needs REVIEW_SIGNIN_KEY (a secret Tyler sets).
    func testReviewSignInFriendsAndDelete() throws {
        guard let key = ProcessInfo.processInfo.environment["REVIEW_KEY"], !key.isEmpty else {
            throw XCTSkip("REVIEW_SIGNIN_KEY isn’t set in the repository's secrets yet")
        }
        let app = launch()
        tapWhenReady(app.tabBars.buttons["You"])
        let version = app.staticTexts["version"]
        XCTAssertTrue(version.waitForExistence(timeout: 5))
        for _ in 0..<5 { version.tap() }
        let field = app.secureTextFields["review-key"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText(key)
        app.buttons["review-sign-in"].tap()
        // the alerts question after signing in (a system alert): allow it if it shows
        addUIInterruptionMonitor(withDescription: "alerts") { alert in
            guard alert.buttons["Allow"].exists else { return false }
            alert.buttons["Allow"].tap()
            return true
        }
        XCTAssertTrue(app.staticTexts["Signed in for review"].waitForExistence(timeout: 20))
        shot(app, "403-signed-in")
        tapWhenReady(app.tabBars.buttons["Friends"])
        XCTAssertTrue(app.buttons["friend-link"].waitForExistence(timeout: 15))
        shot(app, "403-friends")
        tapWhenReady(app.tabBars.buttons["You"])
        tapWhenReady(app.buttons["delete-account"])
        tapWhenReady(app.buttons.matching(NSPredicate(format: "label == 'Delete account' AND identifier != 'delete-account'")).firstMatch, 5)
        XCTAssertTrue(app.buttons["sign-in"].waitForExistence(timeout: 20), "back to a guest")
    }

    /// An invite (the app's own link, as a notification opens it) goes straight to the room.
    func testInviteLinkOpensTheRoom() throws {
        let code = try startRoom("farkle")
        let app = launch()
        XCTAssertTrue(app.textFields["room-code"].waitForExistence(timeout: 10))
        XCUIDevice.shared.system.open(URL(string: "time2play://join/\(code)")!)
        let open = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Open"]
        if open.waitForExistence(timeout: 3) { open.tap() }
        XCTAssertTrue(app.textFields["name"].waitForExistence(timeout: 20), "the room's name and face picker")
        shot(app, "404-invite-opened-room")
    }

    /// Without the app's association (until Tyler's Team ID is set, or with no app), an invite link opens the website.
    func testInviteLinkFallsBackToTheWebsite() throws {
        let code = try startRoom("overdraft")
        XCUIDevice.shared.system.open(URL(string: "https://time2play.live/\(code)")!)
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 20))
        sleep(6)
        let s = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: s); a.name = "404-website-fallback"; a.lifetime = .keepAlways; add(a)
        let home = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] ?? NSTemporaryDirectory()
        try? s.pngRepresentation.write(to: URL(fileURLWithPath: home).appendingPathComponent("t2p-shots/404-website-fallback.png"))
    }
}
