import Foundation
import XCTest
@testable import T2PCore

/// Quick-start presets (#538): captured from the rooms' real lobby views, saved and read back, and replayed as the
/// same options and bots.
final class PresetsTests: XCTestCase {
    func fixture(_ name: String) throws -> JSON {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try XCTUnwrap(JSON.parse(try Data(contentsOf: url)))
    }

    func testCaptureFromEachLobby() throws {
        let hd = Preset.capture(name: " Friday dice ", game: .hotDice, view: try fixture("hotdice-lobby"), offline: false)
        XCTAssertEqual(hd.name, "Friday dice"); XCTAssertEqual(hd.bots, ["steady"])
        XCTAssertEqual(hd.options, ["ones": 1000, "target": 10000, "board": true, "three": true])
        XCTAssertNil(hd.offline)
        let od = Preset.capture(name: "Family", game: .overdraft, view: try fixture("overdraft-lobby"), offline: true)
        XCTAssertEqual(od.bots, ["easy", "normal"]); XCTAssertEqual(od.options, ["jumpIn": false, "stacking": false])
        XCTAssertEqual(od.offline, true)
        let ce = Preset.capture(name: "Quiz", game: .closeEnough, view: try fixture("closeenough-lobby"), offline: false)
        XCTAssertEqual(ce.options, ["set": "general", "count": 10, "timer": 60])
        XCTAssertEqual(ce.summary, "1 bot · 10 questions · 60s each")
        let rc = Preset.capture(name: "Solo", game: .rollCall, view: try fixture("rollcall-lobby"), offline: false)
        XCTAssertEqual(rc.options, ["quick": false])
    }

    func testBotsToAdd() {
        let p = Preset(name: "x", game: .overdraft, bots: ["easy", "easy", "normal"], options: [:])
        XCTAssertEqual(p.botsToAdd(seated: ["easy"], game: .overdraft), ["easy", "normal"])
        let q = Preset(name: "y", game: .hotDice, bots: ["steady", "bold"], options: [:])
        XCTAssertEqual(q.botsToAdd(seated: ["bold"], game: .hotDice), ["steady"], "the dice games' bots are one each")
    }

    func testSavedListReadsBackAndReplacesByName() throws {
        let a = Preset(name: "Family", game: .overdraft, bots: ["easy"], options: ["jumpIn": true])
        let b = Preset(name: "family", game: .overdraft, bots: [], options: [:])
        let c = Preset(name: "Family", game: .hotDice, bots: [], options: [:])
        let l = Presets.adding(c, to: Presets.adding(b, to: Presets.adding(a, to: [])))
        XCTAssertEqual(l.map(\.id), [c.id, b.id], "the same name for the same game replaces it; another game's stays")
        XCTAssertEqual(Presets.decode(Presets.encode(l)), l)
        // a list saved with a field this version doesn't know still reads
        let newer = #"[{"id":"1","name":"N","game":"farkle","bots":[],"options":{},"created":1,"color":"gold"}]"#
        XCTAssertEqual(Presets.decode(Data(newer.utf8)).first?.gameValue, .hotDice)
        XCTAssertTrue(Presets.decode(Data("nonsense".utf8)).isEmpty)
    }
}
