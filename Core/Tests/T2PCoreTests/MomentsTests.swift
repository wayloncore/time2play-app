import Foundation
import XCTest
@testable import T2PCore

/// #489: what just happened at a Hot Dice or Roll Call table, worked out from two views, and #487: the Library leaves
/// out cards named after real TV game shows.
final class MomentsTests: XCTestCase {
    private func hot(_ text: String) throws -> HotDice.View { HotDice.View(try XCTUnwrap(JSON.parse(text))) }
    private func rc(_ text: String) throws -> RollCall.View { RollCall.View(try XCTUnwrap(JSON.parse(text))) }

    private let players = #""players":[{"id":"p1","name":"Ada","score":0},{"id":"p2","name":"June","bot":"steady","score":1200}]"#

    func testHotDiceKeptHotAndBanked() throws {
        let a = try hot(#"{"phase":"playing",\#(players),"turn":{"id":"p2","n":5,"state":"choose","seq":1,"pts":0,"hot":0}}"#)
        let b = try hot(#"{"phase":"playing",\#(players),"turn":{"id":"p2","n":5,"state":"rolling","seq":2,"pts":400,"hot":0,"lastSet":{"name":"Three 4s","pts":400,"seq":1}}}"#)
        XCTAssertEqual(HotDice.moments(from: a, to: b), [.kept(who: "p2", name: "Three 4s", points: 400)])
        XCTAssertEqual(HotDice.moments(from: b, to: b), [], "the same view twice: nothing happened")
        let c = try hot(#"{"phase":"playing",\#(players),"turn":{"id":"p2","n":5,"state":"hot","seq":2,"pts":1000,"hot":1,"lastSet":{"name":"","pts":600,"seq":2}}}"#)
        XCTAssertEqual(HotDice.moments(from: b, to: c), [.kept(who: "p2", name: "", points: 600), .hot(who: "p2")])
        let d = try hot(#"{"phase":"playing",\#(players),"turn":{"id":"p1","n":6,"state":"start","seq":0,"pts":0},"last":{"n":3,"kind":"bank","id":"p2","pts":1000,"score":2200}}"#)
        let moments = HotDice.moments(from: c, to: d)
        XCTAssertEqual(moments, [.banked(who: "p2", points: 1000, total: 2200)], "a new turn: the bank, not the next player's dice")
        XCTAssertTrue(moments[0].isBig)
    }

    func testHotDiceFarklesAndTheLastRound() throws {
        let a = try hot(#"{"phase":"playing",\#(players),"turn":{"id":"p1","n":7,"state":"rolling","seq":3,"pts":350},"last":{"n":3,"kind":"bank","id":"p2","pts":1000,"score":2200}}"#)
        let b = try hot(#"{"phase":"playing",\#(players),"turn":{"id":"p1","n":7,"state":"farkle","seq":3,"pts":350,"lost":350},"last":{"n":4,"kind":"farkle","id":"p1","pts":350,"three":false,"penalty":0,"score":0}}"#)
        XCTAssertEqual(HotDice.moments(from: a, to: b), [.farkled(who: "p1", lost: 350)])
        let c = try hot(#"{"phase":"playing",\#(players),"turn":{"id":"p1","n":9,"state":"farkle","seq":1,"pts":0},"last":{"n":5,"kind":"farkle","id":"p1","pts":0,"three":true,"penalty":1000,"score":0}}"#)
        XCTAssertEqual(HotDice.moments(from: b, to: c), [.threeFarkles(who: "p1", penalty: 1000)])
        let d = try hot(#"{"phase":"playing",\#(players),"final":{"by":"p2","left":["p1"]},"turn":{"id":"p1","n":10,"state":"start"},"last":{"n":6,"kind":"bank","id":"p2","pts":800,"score":10100}}"#)
        XCTAssertEqual(HotDice.moments(from: c, to: d), [.banked(who: "p2", points: 800, total: 10100), .lastRound(by: "p2")])
        let lobby = try hot(#"{"phase":"lobby",\#(players)}"#)
        XCTAssertEqual(HotDice.moments(from: lobby, to: d), [], "a game just dealt has nothing to tell")
        XCTAssertEqual(HotDice.moments(from: nil, to: d), [])
    }

    func testHotDiceSaysWhenATapCanEndAFarkle() throws {
        XCTAssertTrue(try hot(#"{"phase":"playing","farkleSkip":true,"players":[]}"#).farkleSkip)
        XCTAssertFalse(try hot(#"{"phase":"playing","players":[]}"#).farkleSkip, "a room from before it: the hold plays out")
    }

    func testRollCallScoredBonusAndRound() throws {
        let p = { (s: String) in #""players":[{"id":"p1","name":"Ada","scores":{"ones":3,"twos":6,"threes":9,"fours":12,"fives":15},"extra":0,"total":45},\#(s)]"# }
        let pip = #"{"id":"p2","name":"Pip","bot":"easy","scores":{"ones":2},"extra":0,"total":2}"#
        let a = try rc(#"{"phase":"playing","rounds":13,\#(p(pip)),"turn":{"id":"p1","dice":[6,6,6,6,2],"held":[],"rolls":2}}"#)
        let b = try rc(#"{"phase":"playing","rounds":13,"players":[{"id":"p1","name":"Ada","scores":{"ones":3,"twos":6,"threes":9,"fours":12,"fives":15,"sixes":24},"extra":0,"total":104},\#(pip)],"turn":{"id":"p2","dice":[6,6,6,6,2],"held":[],"rolls":0},"last":{"n":9,"id":"p1","key":"sixes","points":24,"extra":0,"dice":[6,6,6,6,2]}}"#)
        XCTAssertEqual(RollCall.moments(from: a, to: b), [.scored(who: "p1", box: "sixes", points: 24, extra: 0, dice: [6, 6, 6, 6, 2]),
                                                          .upperBonus(who: "p1", points: 35)])
        XCTAssertEqual(b.bonus(b.players[0]), 35)
        XCTAssertEqual(RollCall.boxName("full"), "Full House")
        // Pip scores; it's Ada's turn again, a round on
        let c = try rc(#"{"phase":"playing","rounds":13,"players":[{"id":"p1","name":"Ada","scores":{"ones":3,"twos":6,"threes":9,"fours":12,"fives":15,"sixes":24},"extra":0,"total":104},{"id":"p2","name":"Pip","bot":"easy","scores":{"ones":2,"chance":20},"extra":0,"total":22}],"turn":{"id":"p1","dice":[1,2,3,4,5],"held":[],"rolls":0},"last":{"n":10,"id":"p2","key":"chance","points":20,"extra":0,"dice":[6,5,4,3,2]}}"#)
        XCTAssertEqual(RollCall.moments(from: b, to: c), [.scored(who: "p2", box: "chance", points: 20, extra: 0, dice: [6, 5, 4, 3, 2]), .round(7)])
    }

    /// #487: cards the feed marks as named after a real TV game show stay out of the app's Library, and its search.
    func testLibraryLeavesOutShowNames() {
        let j: JSON = ["v": 1, "categories": [["id": "live", "name": "Live games", "line": ""]],
                       "items": [["key": "millionaire", "title": "Who Wants to Be a Millionaire", "category": "Live games", "showName": true],
                                 ["key": "live-buzzer", "title": "Live Buzzer", "category": "Live games"],
                                 ["key": "live-jeopardy", "title": "Jeopardy Live", "category": "Live games", "showName": true],
                                 ["key": "overdraft", "title": "Overdraft", "category": "Live games", "app": "overdraft", "showName": false]]]
        let lib = Library(j)!
        XCTAssertEqual(lib.items.map(\.key), ["live-buzzer", "overdraft"])
        XCTAssertEqual(lib.search("live").map(\.key), ["live-buzzer", "overdraft"], "search finds none of them either")
        XCTAssertEqual(lib.search("millionaire"), [])
    }
}
