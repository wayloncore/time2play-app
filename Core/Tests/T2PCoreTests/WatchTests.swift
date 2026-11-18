import Foundation
import XCTest
@testable import T2PCore

/// Watching a room (#539): join with { watch: true }, no seat; the spectator view (or the floor) is the room's view,
/// and a dropped watcher comes back as a watcher. A server without watching never sees the message (the button hides).
final class WatchTests: XCTestCase {
    func testWatchJoinsWithoutASeat() {
        let t = FakeTransport()
        let s = RoomSession(game: .hotDice, code: "K7QP", appVersion: "1.0", transport: t, store: MemorySeatStore())
        s.start(); t.onEvent?(.opened)
        t.server(#"{"t":"hello","v":1,"min":1,"game":"farkle","update":false}"#)
        s.watch(name: "Sam")
        XCTAssertEqual(t.sent.last?.text, #"{"name":"Sam","t":"join","watch":true}"#)
        XCTAssertEqual(s.status, .joining)
        t.server(#"{"t":"you","ok":true,"phase":"playing","spectator":true,"players":[]}"#)
        XCTAssertEqual(s.status, .inRoom); XCTAssertNil(s.seat); XCTAssertTrue(s.watching)
        // dropped, then back: it watches again (no seat to resume)
        t.onEvent?(.closed(code: 1006))
        s.reconnect(); t.onEvent?(.opened)
        t.server(#"{"t":"hello","v":1,"min":1,"game":"farkle","update":false}"#)
        XCTAssertEqual(t.sent.last?["watch"].bool, true)
        t.server(#"{"t":"floor","phase":"playing","players":[{"id":"p1"}]}"#)
        XCTAssertEqual(s.view?["players"].array.count, 1, "a floor sent to a watcher is its view")
        XCTAssertEqual(Out.watch(name: nil).text, #"{"t":"join","watch":true}"#)
    }

    func testExistsSaysWhetherWatchingIsOn() async throws {
        let api = API(fetch: { req in
            let u = req.url!.absoluteString
            if u.contains("/live/farkle/K7QP/exists") { return (200, Data(#"{"inUse":true,"phase":"playing","players":3,"taken":[1],"watch":true}"#.utf8)) }
            return (200, Data(#"{"inUse":false}"#.utf8))
        })
        let f = try await api.find(code: "K7QP")
        XCTAssertEqual(f?.game, .hotDice); XCTAssertEqual(f?.watch, true)
        let old = API(fetch: { req in req.url!.absoluteString.contains("/live/farkle/") ? (200, Data(#"{"inUse":true}"#.utf8)) : (200, Data(#"{"inUse":false}"#.utf8)) })
        let g = try await old.find(code: "K7QP")
        XCTAssertEqual(g?.watch, false, "a server without watching: the button stays hidden")
    }
}
