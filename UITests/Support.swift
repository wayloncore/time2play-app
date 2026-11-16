import XCTest

/// Shared by the UI tests: launching the app clean, and saving screenshots where the Mac workflow prints them from.
extension XCTestCase {
    func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset"] + extra
        app.launch()
        return app
    }

    /// Saves a full-size screenshot as <name>.png in ~/t2p-shots on the Mac (the workflow prints them into its log),
    /// and attaches it to the test result too.
    func shot(_ app: XCUIApplication, _ name: String) {
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
