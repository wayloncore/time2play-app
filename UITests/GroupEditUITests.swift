import XCTest

/// wayloncore/tyleralocke#575: Edit on your own groups (rename, put friends in, take people out), painted, and friend
/// and group links that say whose they are before adding ("Add Sam as a friend?", "Join Board game night?"), with the
/// old question when the server has no peek. The test build's stand-in friends (-t2p-social-demo) fill in.
final class GroupEditUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    private var device: String { UIDevice.current.userInterfaceIdiom == .pad ? "ipad-" : "" }
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    private func tab(_ app: XCUIApplication, _ name: String) {
        let t = app.tabBars.buttons[name]
        tapWhenReady(t.waitForExistence(timeout: 5) ? t : app.buttons[name].firstMatch)
    }
    /// A painted dialog's words (its title is drawn in capitals).
    private func says(_ app: XCUIApplication, _ words: String) -> Bool {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", words)).firstMatch.waitForExistence(timeout: 5)
    }

    func testEditYourGroup() {
        let app = launch(["-t2p-social-demo"])
        tab(app, "Friends")
        let edit = app.buttons["group-edit-g_demo_thursday"]
        XCTAssertTrue(app.buttons["friend-link"].waitForExistence(timeout: 10))
        for _ in 0..<4 where !(edit.exists && edit.isHittable) { app.swipeUp() }
        XCTAssertTrue(edit.isHittable, "your own group has Edit")
        XCTAssertFalse(app.buttons["group-edit-g_demo_lunch"].exists, "someone else's group doesn't")
        sleep(1)
        shot(app, "575-\(device)groups-edit-button")
        edit.tap()
        XCTAssertTrue(any(app, "edit-group").waitForExistence(timeout: 5), "the painted edit sheet")
        XCTAssertFalse(app.buttons["group-save"].isEnabled, "nothing to save yet")
        sleep(1)
        shot(app, "575-\(device)group-edit-sheet")
        // a new name, Jo taken out, Marcus put in
        let field = app.textFields["group-name"]
        field.tap()
        if let old = field.value as? String { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count)) }
        field.typeText("Friday crew")
        tapWhenReady(app.buttons["group-pick-a_demo_jo"])
        tapWhenReady(app.buttons["group-pick-a_demo_marcus"])
        XCTAssertTrue(app.buttons["group-save"].isEnabled)
        usleep(500_000)
        shot(app, "575-\(device)group-edit-changed")
        app.buttons["group-save"].tap()
        XCTAssertTrue(app.staticTexts["Friday crew"].waitForExistence(timeout: 5), "the group has its new name")
        // the menu has Edit too
        tapWhenReady(app.buttons["group-more-g_demo_thursday"])
        XCTAssertTrue(app.buttons["group-edit"].waitForExistence(timeout: 5), "Edit the group, in the group's menu")
        sleep(1)
        shot(app, "575-\(device)group-menu-edit")
    }

    private func openLink(_ app: XCUIApplication, _ code: String) {
        XCUIDevice.shared.system.open(URL(string: "time2play://f/\(code)")!)
        let open = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Open"]
        if open.waitForExistence(timeout: 3) { open.tap() }
        XCTAssertTrue(any(app, "dialog-friend-link").waitForExistence(timeout: 10), "the painted link question")
    }

    func testLinksSayWhoseTheyAre() {
        var app = launch(["-t2p-social-demo"])
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10) || app.buttons["Friends"].waitForExistence(timeout: 5))
        openLink(app, "AB12CD34")
        XCTAssertTrue(says(app, "Add Sam as a friend?"), "a friend link names whose it is")
        usleep(500_000)
        shot(app, "575-\(device)link-friend-question")
        tapWhenReady(app.buttons["link-open"])
        XCTAssertTrue(any(app, "dialog-link-done").waitForExistence(timeout: 10))
        tapWhenReady(app.buttons["dialog-cancel"])
        sleep(1)
        openLink(app, "GRP23456")
        XCTAssertTrue(says(app, "Join Board game night?"), "a group link names the group")
        usleep(500_000)
        shot(app, "575-\(device)link-group-question")
        tapWhenReady(app.buttons["link-open"])
        XCTAssertTrue(any(app, "dialog-link-done").waitForExistence(timeout: 10))
        XCTAssertTrue(says(app, "You joined Board game night"))
        app.terminate()
        // an older server with no peek: the question as before
        app = launch(["-t2p-social-demo", "-t2p-old-server"])
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10) || app.buttons["Friends"].waitForExistence(timeout: 5))
        openLink(app, "AB12CD34")
        XCTAssertTrue(says(app, "Open this friend link?"), "the old question when the server has no peek")
        usleep(500_000)
        shot(app, "575-\(device)link-old-server")
    }
}
