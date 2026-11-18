import XCTest

/// Tyler, Nov 18: the painted style everywhere (no iOS alerts, dialogs or menus), a confirmed Leave taking a live room
/// off Recent rooms (a drop-out or a solo room stays), each game's own picture in place of the symbols, and friends and
/// invites with full use: Invite friends from the lobby and the iPad host (Friends | Groups), the painted Friends
/// screen, friend links, and the invite banner. Where a real friend list isn't there, the test build's stand-in friends
/// (-t2p-social-demo) fill in; rooms are live ones on tyleralocke.com.
final class PaintFriendsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    override func tearDown() { XCUIDevice.shared.appearance = .light }
    private var device: String { UIDevice.current.userInterfaceIdiom == .pad ? "ipad-" : "" }
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    /// The code the lobby shows ("Room code K 7 Q P").
    private func shownCode(_ app: XCUIApplication) -> String {
        let e = app.staticTexts["room-code-shown"]
        XCTAssertTrue(e.waitForExistence(timeout: 20), "in the lobby")
        return e.label.replacingOccurrences(of: "Room code", with: "").replacingOccurrences(of: " ", with: "")
    }

    private func backToPlay(_ app: XCUIApplication) {
        XCTAssertTrue(app.textFields["room-code"].waitForExistence(timeout: 15), "back on Play")
    }

    // MARK: pictures

    /// Each game's picture at its real sizes (a Start card, a row, a preset, the banner), dark and light.
    func testGamePictures() {
        for light in [false, true] {
            let app = launch(["-t2p-art-gallery"] + (light ? ["-t2p-light"] : []))
            XCTAssertTrue(any(app, "art-gallery").waitForExistence(timeout: 10))
            sleep(1)
            shot(app, "nov18p-\(device)art-\(light ? "light" : "dark")")
            app.terminate()
        }
    }

    // MARK: the lobby's painted dialogs, signed-out invites, and a confirmed Leave

    func testLobbyDialogsAndConfirmedLeave() {
        let app = launch()
        startAsOwner(app, game: "farkle", bot: "steady")
        let code = shownCode(app)
        XCTAssertTrue(app.buttons["invite-friends"].waitForExistence(timeout: 5), "the owner's Invite friends")
        shot(app, "nov18p-\(device)lobby-invite-bar")

        // Take a bot out: painted, not an iOS sheet
        let bot = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'player-' AND label CONTAINS 'Bot'")).firstMatch
        XCTAssertTrue(bot.waitForExistence(timeout: 10), "the bot's row")
        bot.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertTrue(any(app, "dialog-remove").waitForExistence(timeout: 5), "the painted Take out")
        XCTAssertEqual(app.sheets.count, 0, "no iOS dialog")
        usleep(500_000)
        shot(app, "nov18p-\(device)lobby-take-out")
        app.buttons["dialog-cancel"].tap()

        // End the room: painted
        let end = app.buttons["lobby-end-room"]
        if !end.isHittable { app.swipeUp() }
        tapWhenReady(end)
        XCTAssertTrue(any(app, "dialog-end-room").waitForExistence(timeout: 5))
        usleep(500_000)
        shot(app, "nov18p-\(device)lobby-end-room")
        app.buttons["dialog-cancel"].tap()

        // Invite friends, signed out: one line and Sign in, right there
        app.swipeDown()
        tapWhenReady(app.buttons["invite-friends"])
        XCTAssertTrue(any(app, "invite-needs-sign-in").waitForExistence(timeout: 10), "the invite screen says invites need sign-in")
        XCTAssertTrue(app.buttons["sign-in"].exists, "with Sign in there")
        sleep(1)
        shot(app, "nov18p-\(device)invite-signed-out")
        tapWhenReady(app.buttons["invite-close"])
        sleep(1)

        // a confirmed Leave in a live room: it comes off Recent rooms (dark mode for this one)
        XCUIDevice.shared.appearance = .dark
        sleep(1)
        tapWhenReady(app.buttons["leave"])
        XCTAssertTrue(any(app, "dialog-leave").waitForExistence(timeout: 5))
        usleep(500_000)
        shot(app, "nov18p-\(device)leave-live-dark")
        tapWhenReady(app.buttons["Leave the room"], 5)
        backToPlay(app)
        sleep(4)   // Play checks which recent rooms are open
        XCTAssertFalse(app.buttons["rejoin-\(code)"].exists, "a confirmed Leave takes the room off Recent rooms")
        shot(app, "nov18p-\(device)recent-after-leave")
    }

    /// A drop-out (the app closed mid-room): the room stays, with its picture, who's in it and Rejoin. A long press
    /// asks, painted, whether to take it off.
    func testDropOutKeepsTheRoom() {
        let app = launch()
        startAsOwner(app, game: "farkle", bot: "steady")
        let code = shownCode(app)
        sleep(1)
        XCUIDevice.shared.press(.home)   // the app goes to the background (who's in it is saved then)
        sleep(2)
        app.terminate()
        app.launchArguments = ["-t2p-classic", "-t2p-classic-dice"]
        app.launch()
        let rejoin = app.buttons["rejoin-\(code)"]
        XCTAssertTrue(rejoin.waitForExistence(timeout: 25), "a drop-out keeps the room in Recent rooms")
        XCTAssertTrue(rejoin.label.contains("Rejoin"), rejoin.label)
        sleep(1)
        shot(app, "nov18p-\(device)recent-after-dropout")
        XCUIDevice.shared.appearance = .dark
        sleep(1)
        shot(app, "nov18p-\(device)recent-after-dropout-dark")
        rejoin.press(forDuration: 0.9)
        XCTAssertTrue(any(app, "dialog-recent-remove").waitForExistence(timeout: 5), "the painted Remove question")
        usleep(500_000)
        shot(app, "nov18p-\(device)recent-remove")
        tapWhenReady(app.buttons["recent-remove"])
        sleep(1)
        XCTAssertFalse(rejoin.exists, "removed")
    }

    /// A solo room (Roll Call, just you and a bot): Leave keeps it, with Resume.
    func testSoloLeaveKeepsResume() {
        let app = launch()
        startAsOwner(app, game: "rollcall", bot: "easy")
        let code = shownCode(app)
        tapWhenReady(app.buttons["leave"])
        XCTAssertTrue(any(app, "dialog-leave").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["LEAVE FOR NOW?"].exists || any(app, "dialog-leave").label.contains("LEAVE FOR NOW"), "the solo wording")
        usleep(500_000)
        shot(app, "nov18p-\(device)leave-solo")
        tapWhenReady(app.buttons["Leave the room"], 5)
        backToPlay(app)
        let resume = app.buttons["rejoin-\(code)"]
        XCTAssertTrue(resume.waitForExistence(timeout: 15), "a solo room stays in Recent rooms")
        XCTAssertTrue(resume.label.contains("Resume"), resume.label)
        sleep(1)
        shot(app, "nov18p-\(device)recent-solo-resume")
        resume.tap()
        XCTAssertTrue(app.staticTexts["room-code-shown"].waitForExistence(timeout: 20), "back in the room, seat and all")
        XCTAssertTrue(any(app, "owner-chip").exists, "still its owner")
    }

    // MARK: invites

    /// The invite screen with friends: pick two, look at Groups, send; the lobby says who's invited; invite more.
    func testInviteFriendsAndGroups() {
        let app = launch(["-t2p-social-demo"])
        startAsOwner(app, game: "farkle", bot: "steady")
        tapWhenReady(app.buttons["invite-friends"])
        XCTAssertTrue(any(app, "invite-screen").waitForExistence(timeout: 10))
        sleep(1)
        shot(app, "nov18p-\(device)invite-friends")
        tapWhenReady(app.buttons["invite-friend-a_demo_sam"])
        tapWhenReady(app.buttons["invite-friend-a_demo_jo"])
        XCTAssertEqual(app.buttons["invite-send"].label, "Invite 2 friends")
        shot(app, "nov18p-\(device)invite-friends-picked")
        tapWhenReady(app.buttons["invite-tab-groups"])
        tapWhenReady(app.buttons["invite-group-g_demo_thursday"])
        XCTAssertEqual(app.buttons["invite-send"].label, "Invite Thursday crew")
        usleep(500_000)
        shot(app, "nov18p-\(device)invite-groups")
        tapWhenReady(app.buttons["invite-tab-friends"])
        XCTAssertEqual(app.buttons["invite-send"].label, "Invite 2 friends", "the picks are kept")
        tapWhenReady(app.buttons["invite-send"])
        let bar = app.buttons["invite-friends"]
        let invited = NSPredicate(format: "label CONTAINS 'Invited: Sam, Jo'")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: invited, object: bar)], timeout: 10), .completed, "the lobby says who's invited: \(bar.label)")
        sleep(1)
        shot(app, "nov18p-\(device)lobby-invited")
        // invite more: the group this time
        tapWhenReady(bar)
        XCTAssertTrue(app.buttons["invite-friend-a_demo_sam"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["invite-friend-a_demo_sam"].label.contains("invited"), "Sam shows as invited")
        tapWhenReady(app.buttons["invite-tab-groups"])
        tapWhenReady(app.buttons["invite-group-g_demo_thursday"])
        tapWhenReady(app.buttons["invite-send"])
        let more = NSPredicate(format: "label CONTAINS 'Thursday crew'")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: more, object: bar)], timeout: 10), .completed, bar.label)
        shot(app, "nov18p-\(device)lobby-invited-more")
    }

    /// No friends yet: the friend link in place of an empty list; no groups: what a group is.
    func testInviteWithNoFriends() {
        let app = launch(["-t2p-social-demo-empty"])
        startAsOwner(app, game: "rollcall", bot: "easy")
        tapWhenReady(app.buttons["invite-friends"])
        XCTAssertTrue(app.buttons["invite-friend-link"].waitForExistence(timeout: 10), "Send your friend link")
        sleep(1)
        shot(app, "nov18p-\(device)invite-no-friends")
        tapWhenReady(app.buttons["invite-tab-groups"])
        usleep(500_000)
        shot(app, "nov18p-\(device)invite-no-groups")
    }

    /// The server refusing an invite (before wayloncore/tyleralocke#566, a Roll Call room): painted, over the screen.
    func testInviteRefusedIsPainted() {
        let app = launch(["-t2p-social-demo", "-t2p-invite-fail"])
        startAsOwner(app, game: "rollcall", bot: "easy")
        tapWhenReady(app.buttons["invite-friends"])
        tapWhenReady(app.buttons["invite-friend-a_demo_sam"])
        tapWhenReady(app.buttons["invite-send"])
        XCTAssertTrue(any(app, "dialog-invite-failed").waitForExistence(timeout: 10), "the refusal, painted")
        XCTAssertEqual(app.alerts.count, 0)
        usleep(500_000)
        shot(app, "nov18p-\(device)invite-refused")
        tapWhenReady(app.buttons["dialog-cancel"])
        XCTAssertTrue(any(app, "invite-screen").exists, "the invite screen stays, to try again")
    }

    // MARK: Friends

    func testFriendsScreen() {
        let app = launch(["-t2p-social-demo"])
        tapWhenReady(app.tabBars.buttons["Friends"])
        XCTAssertTrue(app.buttons["friend-link"].waitForExistence(timeout: 10))
        sleep(1)
        shot(app, "nov18p-\(device)friends-top")
        // a friend's choices, then Remove's confirm, painted
        tapWhenReady(app.buttons["friend-more-a_demo_sam"])
        XCTAssertTrue(any(app, "dialog-person").waitForExistence(timeout: 5))
        usleep(500_000)
        shot(app, "nov18p-\(device)friends-person")
        tapWhenReady(app.buttons["person-remove"])
        XCTAssertTrue(any(app, "dialog-remove-friend").waitForExistence(timeout: 5))
        usleep(500_000)
        shot(app, "nov18p-\(device)friends-remove-confirm")
        tapWhenReady(app.buttons["dialog-cancel"])
        sleep(1)
        // Invite: the painted game picker
        tapWhenReady(app.buttons["friend-invite-a_demo_jo"])
        XCTAssertTrue(any(app, "game-picker").waitForExistence(timeout: 5))
        sleep(1)
        shot(app, "nov18p-\(device)friends-game-picker")
        tapWhenReady(app.buttons["picker-cancel"])
        sleep(1)
        // groups
        let more = app.buttons["group-more-g_demo_thursday"]
        for _ in 0..<4 where !(more.exists && more.isHittable) { app.swipeUp() }
        sleep(1)
        shot(app, "nov18p-\(device)friends-groups")
        tapWhenReady(more)
        XCTAssertTrue(any(app, "dialog-group").waitForExistence(timeout: 5))
        usleep(500_000)
        shot(app, "nov18p-\(device)friends-group-menu")
        tapWhenReady(app.buttons["group-leave"])
        XCTAssertTrue(any(app, "dialog-group-leave").waitForExistence(timeout: 5))
        usleep(500_000)
        shot(app, "nov18p-\(device)friends-group-delete-confirm")
        tapWhenReady(app.buttons["dialog-cancel"])
        sleep(1)
        tapWhenReady(app.buttons["make-group"])
        XCTAssertTrue(any(app, "new-group").waitForExistence(timeout: 5))
        sleep(1)
        shot(app, "nov18p-\(device)friends-make-group")
        tapWhenReady(app.buttons["group-cancel"])
    }

    /// The Friends screen with the phone in light mode (it stays painted), and signed out.
    func testFriendsLightAndSignedOut() {
        let app = launch(["-t2p-social-demo", "-t2p-light"])
        tapWhenReady(app.tabBars.buttons["Friends"])
        XCTAssertTrue(app.buttons["friend-link"].waitForExistence(timeout: 10))
        sleep(1)
        shot(app, "nov18p-\(device)friends-light")
        app.terminate()
        let guest = launch()
        tapWhenReady(guest.tabBars.buttons["Friends"])
        XCTAssertTrue(guest.buttons["sign-in"].waitForExistence(timeout: 10))
        sleep(1)
        shot(guest, "nov18p-\(device)friends-signed-out")
    }

    // MARK: the app's own dialogs, friend links and the banner

    func testAppDialogsAndFriendLinks() {
        let app = launch(["-t2p-social-demo"])
        tapWhenReady(app.tabBars.buttons["You"])
        tapWhenReady(app.buttons["delete-account"])
        XCTAssertTrue(any(app, "dialog-delete-account").waitForExistence(timeout: 5), "Delete account, painted")
        XCTAssertEqual(app.sheets.count, 0)
        usleep(500_000)
        shot(app, "nov18p-\(device)delete-account")
        tapWhenReady(app.buttons["dialog-cancel"])
        sleep(1)
        tapWhenReady(app.buttons["sign-out"])
        XCTAssertTrue(any(app, "dialog-sign-out").waitForExistence(timeout: 5))
        usleep(500_000)
        shot(app, "nov18p-\(device)sign-out")
        tapWhenReady(app.buttons["dialog-cancel"])
        sleep(1)
        // a friend link from outside the app: a painted question, then who it was
        XCUIDevice.shared.system.open(URL(string: "time2play://f/AB12CD34")!)
        let open = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Open"]
        if open.waitForExistence(timeout: 3) { open.tap() }
        XCTAssertTrue(any(app, "dialog-friend-link").waitForExistence(timeout: 10), "the painted friend-link question")
        usleep(500_000)
        shot(app, "nov18p-\(device)friend-link-question")
        tapWhenReady(app.buttons["link-open"])
        XCTAssertTrue(any(app, "dialog-link-done").waitForExistence(timeout: 10))
        usleep(500_000)
        shot(app, "nov18p-\(device)friend-link-done")
        tapWhenReady(app.buttons["dialog-cancel"])
        app.terminate()
        // signed out, the link says to sign in
        let guest = launch()
        XCTAssertTrue(guest.textFields["room-code"].waitForExistence(timeout: 10))
        XCUIDevice.shared.system.open(URL(string: "time2play://f/AB12CD34")!)
        if open.waitForExistence(timeout: 3) { open.tap() }
        XCTAssertTrue(any(guest, "dialog-link-sign-in").waitForExistence(timeout: 10))
        usleep(500_000)
        shot(guest, "nov18p-\(device)friend-link-signed-out")
    }

    /// An invite while the app is open: the painted banner with Join.
    func testInviteBanner() {
        let app = launch(["-t2p-social-demo", "-t2p-demo-banner"])
        XCTAssertTrue(any(app, "invite-banner").waitForExistence(timeout: 10), "the painted banner")
        XCTAssertTrue(app.buttons["banner-join"].exists)
        usleep(600_000)
        shot(app, "nov18p-\(device)invite-banner")
        tapWhenReady(app.buttons["banner-close"])
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: any(app, "invite-banner"))
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed)
    }

    // MARK: the iPad host

    func testIPadHostInvite() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "hosting is the iPad's")
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch(["-t2p-social-demo"])
        let b = app.buttons["host-farkle"]
        if !b.waitForExistence(timeout: 10) { app.swipeUp() }
        tapWhenReady(b)
        XCTAssertTrue(app.staticTexts["host-code"].waitForExistence(timeout: 30), "the hosted room opens")
        tapWhenReady(app.buttons["invite-friends"])
        XCTAssertTrue(any(app, "invite-screen").waitForExistence(timeout: 10))
        tapWhenReady(app.buttons["invite-friend-a_demo_priya"])
        sleep(1)
        shot(app, "nov18p-ipad-host-invite")
        tapWhenReady(app.buttons["invite-send"])
        let invited = NSPredicate(format: "label CONTAINS 'Invited: Priya'")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: invited, object: app.buttons["invite-friends"])], timeout: 10), .completed)
        sleep(1)
        shot(app, "nov18p-ipad-host-invited")
        tapWhenReady(app.buttons["host-end"])
        tapWhenReady(app.buttons["End the room"])
    }
}
