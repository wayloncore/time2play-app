import Foundation
import XCTest
@testable import T2PCore

/// The views as the website's own room cores make them (scripts/fixtures.mjs), read by the app's view types.
final class ViewsTests: XCTestCase {
    func fixture(_ name: String) throws -> JSON {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try XCTUnwrap(JSON.parse(try Data(contentsOf: url)))
    }

    func testOverdraftLobby() throws {
        let v = Overdraft.View(try fixture("overdraft-lobby"))
        XCTAssertEqual(v.phase, "lobby"); XCTAssertEqual(v.code, "K7QP")
        XCTAssertTrue(v.hostless); XCTAssertTrue(v.isOwner, "the first to join owns a hostless room")
        XCTAssertEqual(v.roster.count, 3)
        XCTAssertEqual(v.roster.filter { $0.bot != nil }.count, 2)
        XCTAssertEqual(v.roster[1].displayName, "Ada")
        XCTAssertNil(v.table)
    }

    func testOverdraftTable() throws {
        let v = Overdraft.View(try fixture("overdraft-table"))
        XCTAssertEqual(v.phase, "playing"); XCTAssertTrue(v.yourTurn)
        XCTAssertEqual(v.hand.count, 7)
        XCTAssertFalse(v.legal.isEmpty)
        XCTAssertTrue(v.legal.isSubset(of: Set(v.hand.map(\.id))))
        let t = try XCTUnwrap(v.table)
        XCTAssertEqual(t.seats.count, 3); XCTAssertEqual(t.turn, v.me.id)
        XCTAssertNotNil(t.top); XCTAssertNotNil(v.matchLine)
        XCTAssertTrue(v.hand.contains { $0.isWild })
    }

    func testHotDice() throws {
        let l = HotDice.View(try fixture("hotdice-lobby"))
        XCTAssertTrue(l.common.isOwner); XCTAssertEqual(l.players.count, 2); XCTAssertEqual(l.players[1].bot, "steady")
        XCTAssertEqual(l.target, 10000)
        let v = HotDice.View(try fixture("hotdice-playing"))
        let t = try XCTUnwrap(v.turn)
        XCTAssertEqual(t.dice.count, 6); XCTAssertEqual(t.state, "choose")
        XCTAssertTrue(t.dice.allSatisfy { $0.v != nil }, "dice are shown once the roll is revealed")
    }

    func testRollCall() throws {
        let v = RollCall.View(try fixture("rollcall-playing"))
        XCTAssertTrue(v.common.yourTurn)
        let t = try XCTUnwrap(v.turn)
        XCTAssertEqual(t.dice.count, 5); XCTAssertEqual(t.rolls, 1); XCTAssertTrue(v.diceShown)
        let o = try XCTUnwrap(v.options)
        XCTAssertEqual(o.scores.count, 13); XCTAssertFalse(o.allowed.isEmpty)
        XCTAssertEqual(RollCall.boxes.count, 13)
        XCTAssertNotNil(v.rollKey, "a roll that has happened has a name")
    }

    /// #488: a Farkle says why, and Roll Call keeps the dice the last box was scored with.
    func testRollsShown() throws {
        XCTAssertEqual(HotDice.farkleWhy(dice: 3), "No 1s, no 5s, no three of a kind")
        XCTAssertEqual(HotDice.farkleWhy(dice: 6), "No 1s, no 5s, no three of a kind, no three pairs")
        let text = #"{"phase":"playing","turn":{"id":"p2","dice":[2,2,3,3,6],"held":[false,false,false,false,false],"rolls":0},"#
            + #""last":{"n":4,"id":"p1","key":"chance","points":19,"extra":0,"dice":[6,4,4,3,2]},"players":[{"id":"p1","name":"Rosa"}]}"#
        let v = RollCall.View(try XCTUnwrap(JSON.parse(text)))
        XCTAssertEqual(v.lastDice, [6, 4, 4, 3, 2]); XCTAssertEqual(v.lastN, 4)
        XCTAssertEqual(v.lastLine, "Rosa scored 19 in Chance")
        XCTAssertNil(v.rollKey, "no roll yet this turn")
        let older = RollCall.View(try XCTUnwrap(JSON.parse(#"{"phase":"playing","players":[]}"#)))
        XCTAssertEqual(older.lastDice, [], "a view with no last box reads as no dice")
    }

    func testCloseEnough() throws {
        let v = CloseEnough.View(try fixture("closeenough-playing"))
        let q = try XCTUnwrap(v.question)
        XCTAssertEqual(q.stage, "ask"); XCTAssertFalse(q.q.isEmpty); XCTAssertLessThan(q.floor, q.ceiling)
        XCTAssertEqual(q.worth(lo: q.floor, hi: q.ceiling), 0)
        XCTAssertEqual(q.worth(lo: q.floor, hi: q.floor), 20)
        XCTAssertEqual(q.snap(q.ceiling + 1000), q.ceiling)
        XCTAssertFalse(v.lockedIn)
        if !q.unit.isEmpty && !q.unit.hasPrefix("%") { XCTAssertEqual(q.formatRange(q.floor, q.ceiling).components(separatedBy: q.unit).count, 2, "the unit once") }
    }

    func testLibraryFeed() {
        let j: JSON = ["v": 1, "categories": [["id": "games", "name": "Games", "line": "Together"]],
                       "items": [["key": "farkle-live", "title": "Farkle Live", "category": "Games", "app": "farkle", "appTitle": "Hot Dice",
                                  "facts": ["players": [2, 8], "phones": "needed"], "page": "/library/farkle-live"],
                                 ["key": "wheel", "title": "Wheel", "category": "Games", "future": true]]]
        let lib = Library(j)!
        XCTAssertEqual(lib.items.count, 2)
        XCTAssertEqual(lib.items[0].title, "Hot Dice"); XCTAssertEqual(lib.items[0].game, .hotDice)
        XCTAssertEqual(lib.items[0].playersLine, "2–8 players")
        XCTAssertNil(lib.items[1].game)
        XCTAssertEqual(lib.search("hot").map(\.key), ["farkle-live"])
        XCTAssertNil(Library(["items": [:]]))
    }

    /// A website blurb with HTML in it reads as plain words in the app (the Library screenshot showed "<strong>").
    func testLibraryBlurbIsPlainText() {
        XCTAssertEqual(Library.plain("<strong>This one needs wifi.</strong>  Put the host screen on &amp; play"),
                       "This one needs wifi. Put the host screen on & play")
        XCTAssertEqual(Library.plain("No tags here"), "No tags here")
        let j: JSON = ["v": 1, "items": [["key": "buzzer", "title": "Live Buzzer", "category": "Live", "blurb": "<em>Fast</em> &ldquo;Buzzer&rdquo;"]]]
        XCTAssertEqual(Library(j)!.items[0].blurb, "Fast “Buzzer”")
    }
}
