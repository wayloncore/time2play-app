import Foundation
import XCTest
@testable import T2PCore

#if canImport(JavaScriptCore)
/// #402: the same seeded games in Node (the fixture, scripts/rules-bundle.mjs) and in JavaScriptCore, move for move.
final class OfflineTests: XCTestCase {
    func testParityWithNode() throws {
        let rules = try XCTUnwrap(OfflineRules.load(), "the bundled rules load in JavaScriptCore")
        let url = try XCTUnwrap(Bundle.module.url(forResource: "parity", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try XCTUnwrap(JSON.parse(try Data(contentsOf: url)))
        XCTAssertGreaterThan(fixture["runs"].array.count, 0)
        for run in fixture["runs"].array {
            let game = run["game"].string!, seed = run["seed"].int!
            let mine = try XCTUnwrap(rules.parity(game, seed: seed))
            XCTAssertEqual(mine["steps"].int, run["steps"].int, "\(game) seed \(seed): the same number of steps")
            let a = mine["hashes"].array, b = run["hashes"].array
            for i in 0..<min(a.count, b.count) where a[i] != b[i] {
                XCTFail("\(game) seed \(seed): step \(i) differs (\(a[i].string ?? "") in the app, \(b[i].string ?? "") in Node)")
                break
            }
            XCTAssertEqual(mine["phase"].string, "done", "\(game) seed \(seed) plays to the end")
        }
    }

    /// #488: the faces in a roll that can score, by the website's own scoring.
    func testScoringFaces() throws {
        let rules = try XCTUnwrap(OfflineRules.load())
        XCTAssertEqual(rules.scoringFaces([1, 2, 3, 4, 6, 6], ones: 1000), [1])
        XCTAssertEqual(rules.scoringFaces([5, 4, 4, 4, 2], ones: 1000), [4, 5])
        XCTAssertEqual(rules.scoringFaces([2, 3, 4, 6], ones: 1000), [], "a Farkle: nothing scores")
        XCTAssertEqual(rules.scoringFaces([2, 2, 3, 3, 6, 6], ones: 1000), [2, 3, 6], "three pairs")
    }

    /// An offline room through the same RoomSession the screens use: join, two bots, deal, and the bots play.
    func testOfflineOverdraftThroughTheSession() throws {
        let rules = try XCTUnwrap(OfflineRules.load())
        let t = OfflineTransport(rules: rules, game: .overdraft, seed: 7)
        var clock = 1_800_000_000_000.0
        t.now = { clock }
        var pending: [() -> Void] = []
        t.schedule = { _, f in pending.append(f) }
        let s = RoomSession(game: .overdraft, code: "SOLO", appVersion: "test", transport: t, store: MemorySeatStore())
        s.join(name: "Sim", face: 9)
        s.start()
        XCTAssertEqual(s.status, .inRoom)
        XCTAssertEqual(Overdraft.View(s.view!).isOwner, true, "you own your offline room")
        s.send(Out.addBot(level: "easy")); s.send(Out.addBot(level: "normal")); s.send(Out.deal)
        let v = Overdraft.View(try XCTUnwrap(s.view))
        XCTAssertEqual(v.phase, "playing"); XCTAssertEqual(v.hand.count, 7)
        // let the room's clock run (bots' turns, a timed-out turn of ours): the table moves on by itself
        let seqBefore = v.table?.seq ?? 0
        for _ in 0..<30 { clock += 50_000; let p = pending; pending = []; p.forEach { $0() } }
        XCTAssertGreaterThan(Overdraft.View(s.view!).table?.seq ?? 0, seqBefore)
    }
}
#endif
