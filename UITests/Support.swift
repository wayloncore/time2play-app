import XCTest

/// Shared by the UI tests: launching the app clean, and saving screenshots where the Mac workflow prints them from.
extension XCTestCase {
    /// Overdraft's 3D table and the 3D dice are the default (#496, #521, Nov 17); these tests check the classic table
    /// and the flat dice, which stay as the fallback, unless they ask for the 3D ones (-t2p-3d, -t2p-dice3d) or for
    /// whatever a new player gets (-t2p-default).
    func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        let fresh = extra.contains("-t2p-default")
        let table = extra.contains("-t2p-3d") || fresh ? [] : ["-t2p-classic"]
        let dice = extra.contains("-t2p-dice3d") || fresh ? [] : ["-t2p-classic-dice"]
        app.launchArguments = ["-uitest-reset"] + table + dice + extra
        app.launch()
        return app
    }

    /// Saves a full-size screenshot as <name>.png in ~/t2p-shots on the Mac (the workflow prints them into its log),
    /// and attaches it to the test result too.
    func shot(_ app: XCUIApplication, _ shotName: String) {
        // a second simulator's run names its shots apart (mac.yml's older iPhone: "older-")
        let name = (ProcessInfo.processInfo.environment["T2P_SHOT_PREFIX"] ?? "") + shotName
        let s = app.screenshot()
        let a = XCTAttachment(screenshot: s); a.name = name; a.lifetime = .keepAlways; add(a)
        let home = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] ?? NSTemporaryDirectory()
        let dir = URL(fileURLWithPath: home).appendingPathComponent("t2p-shots")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? s.pngRepresentation.write(to: dir.appendingPathComponent("\(name).png"))
    }

    /// A real room on the live server, started the way the app starts one (no host screen). Returns its code.
    func startRoom(_ game: String) throws -> String {
        let url = URL(string: "https://tyleralocke.com/live/\(game)/new?hostless=1")!
        var code: String?
        let done = expectation(description: "room")
        URLSession.shared.dataTask(with: url) { data, _, _ in
            if let d = data, let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { code = o["code"] as? String }
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 20)
        return try XCTUnwrap(code, "the server started no room")
    }

    func tapWhenReady(_ e: XCUIElement, _ timeout: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(e.waitForExistence(timeout: timeout), "\(e) never appeared", file: file, line: line)
        e.tap()
    }
}

extension XCTestCase {
    /// Starts a game from Play as its owner (picking a name the first time) and adds one bot. Leaves you in the lobby.
    func startAsOwner(_ app: XCUIApplication, game: String, bot: String) {
        tapWhenReady(app.buttons["start-\(game)"])
        let name = app.textFields["name"]
        if name.waitForExistence(timeout: 20) {
            name.tap(); name.typeText("Sim")
            tapWhenReady(app.buttons["join-room"])
        }
        XCTAssertTrue(app.descendants(matching: .any)["owner-chip"].waitForExistence(timeout: 20), "you own the room you start")
        tapWhenReady(app.buttons["addbot-\(bot)"])
        sleep(1)
    }

    func waitEnabled(_ e: XCUIElement, _ timeout: TimeInterval) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end { if e.exists && e.isEnabled { return true }; usleep(300_000) }
        return false
    }
}

extension XCTestCase {
    /// Types the player's name once the field has the keyboard (an iPad simulator can take a moment to give it focus).
    func typeName(_ app: XCUIApplication, _ field: XCUIElement, _ text: String = "Sim") {
        for _ in 0..<3 {
            field.tap()
            if app.keyboards.firstMatch.waitForExistence(timeout: 5) { break }
        }
        field.typeText(text)
    }
}

extension XCTestCase {
    /// A tab of the app: the tab bar on an iPhone; on an iPad (iOS 18 and later) the tabs sit at the top, where the
    /// tab bar query doesn't always find them.
    func openTab(_ app: XCUIApplication, _ name: String) {
        let bar = app.tabBars.buttons[name]
        if bar.waitForExistence(timeout: 8) { bar.tap(); return }
        tapWhenReady(app.buttons[name].firstMatch, 10)
    }
}
