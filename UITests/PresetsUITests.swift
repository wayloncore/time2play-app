import XCTest

/// Quick-start presets (#538): set up an offline Hot Dice room (a bot, play to 2,500), save it as a preset, leave, and
/// start it again from Play in one tap: the same bot and the same house rules.
final class PresetsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testSaveAndStartAPreset() {
        let app = launch()
        app.swipeUp()
        tapWhenReady(app.buttons["offline-farkle"])
        let name = app.textFields["name"]
        if name.waitForExistence(timeout: 10) { name.tap(); name.typeText("Sim"); tapWhenReady(app.buttons["join-room"]) }
        tapWhenReady(app.buttons["addbot-bold"]); sleep(1)
        tapWhenReady(app.buttons["2,500"]); sleep(1)
        tapWhenReady(app.buttons["save-preset"])
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20) + "Quick dice")
        shot(app, "538-presets-1-naming")
        app.alerts.buttons["Save"].tap()
        sleep(1)
        tapWhenReady(app.buttons["leave"])
        tapWhenReady(app.buttons["Leave the room"])
        let preset = app.buttons["preset-0"]
        XCTAssertTrue(preset.waitForExistence(timeout: 10), "the preset is on Play")
        XCTAssertTrue(preset.label.contains("Quick dice"), preset.label)
        shot(app, "538-presets-2-on-play")
        preset.tap()
        XCTAssertTrue(app.buttons["start-game"].waitForExistence(timeout: 15), "a room starts from the preset")
        sleep(2)
        XCTAssertTrue(app.buttons["2,500"].isSelected, "the preset's house rule is set")
        XCTAssertFalse(app.buttons["addbot-bold"].isEnabled, "and its bot is seated")
        shot(app, "538-presets-3-started")
    }
}
