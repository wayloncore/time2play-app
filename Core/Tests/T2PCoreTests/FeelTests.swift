import Foundation
import XCTest
@testable import T2PCore

/// The game's feel (sounds and haptics): what a new view means, from the view before it (#536's round of the app).
final class FeelTests: XCTestCase {
    func fixture(_ name: String) throws -> JSON {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try XCTUnwrap(JSON.parse(try Data(contentsOf: url)))
    }

    /// A copy of a view with some fields set (a path of keys, then the value).
    func with(_ j: JSON, _ changes: [([String], JSON)]) -> JSON {
        func set(_ v: JSON, _ path: ArraySlice<String>, _ value: JSON) -> JSON {
            guard let k = path.first else { return value }
            var o = v.object ?? [:]
            o[k] = set(o[k] ?? .null, path.dropFirst(), value)
            return .object(o)
        }
        return changes.reduce(j) { set($0, $1.0[...], $1.1) }
    }

    func testTheFirstViewIsQuiet() throws {
        XCTAssertEqual(FeelEvents.between(nil, try fixture("overdraft-table"), game: .overdraft), [])
    }

    func testYourTurnComesRound() throws {
        let now = try fixture("overdraft-table")
        let before = with(now, [(["yourTurn"], false), (["table", "turn"], "p2")])
        XCTAssertEqual(FeelEvents.between(before, now, game: .overdraft), [.yourTurn])
        XCTAssertEqual(FeelEvents.between(now, now, game: .overdraft), [], "nothing changed, nothing plays")
    }

    func testACardPlayedAndADraw() throws {
        let before = try fixture("overdraft-table")
        let played = with(before, [(["table", "seq"], 1), (["table", "top"], ["kind": "number", "suit": "wave", "n": 5]),
                                   (["yourTurn"], false), (["table", "turn"], "p2")])
        XCTAssertEqual(FeelEvents.between(before, played, game: .overdraft), [.cardPlayed])
        var hand = before["hand"].array; hand.append(["id": "c99", "kind": "number", "suit": "leaf", "n": 2])
        let drew = with(before, [(["hand"], .array(hand))])
        XCTAssertEqual(FeelEvents.between(before, drew, game: .overdraft), [.drew])
        let newHand = with(drew, [(["table", "n"], 2)])
        XCTAssertEqual(FeelEvents.between(before, newHand, game: .overdraft), [], "a new deal isn't a draw")
    }

    func testABoltAimedAtYou() throws {
        let mine = try fixture("overdraft-table")
        let before = with(mine, [(["yourTurn"], false), (["table", "turn"], "p2")])
        var hand = mine["hand"].array
        hand.append(["id": "c98", "kind": "number", "suit": "leaf", "n": 2]); hand.append(["id": "c99", "kind": "skip", "suit": "ember"])
        // no stacking: the next player (you) draws two, then it's your turn
        let hit = with(mine, [(["table", "seq"], 1), (["table", "top"], ["kind": "draw2", "suit": "wave"]), (["hand"], .array(hand))])
        XCTAssertEqual(FeelEvents.between(before, hit, game: .overdraft), [.yourTurn, .cardPlayed, .bolt])
        // stacking: a train you face
        let train = with(mine, [(["table", "seq"], 1), (["table", "top"], ["kind": "wild4"]), (["table", "stack"], 4)])
        XCTAssertEqual(FeelEvents.between(before, train, game: .overdraft), [.yourTurn, .cardPlayed, .bolt])
        // a +2 aimed at someone else is just a card
        let other = with(before, [(["table", "seq"], 1), (["table", "top"], ["kind": "draw2", "suit": "wave"]), (["table", "turn"], "p3")])
        XCTAssertEqual(FeelEvents.between(before, other, game: .overdraft), [.cardPlayed])
    }

    func testWinningOverdraft() throws {
        let before = try fixture("overdraft-table")
        let won = with(before, [(["table", "over"], true), (["table", "winner"], "p1"), (["yourTurn"], false)])
        XCTAssertEqual(FeelEvents.between(before, won, game: .overdraft), [.won])
        let lost = with(before, [(["table", "over"], true), (["table", "winner"], "p2")])
        XCTAssertEqual(FeelEvents.between(before, lost, game: .overdraft), [])
    }

    func testHotDiceRollsAndWins() throws {
        let before = try fixture("hotdice-playing")
        let rolling = with(before, [(["turn", "seq"], 2), (["turn", "state"], "rolling")])
        XCTAssertEqual(FeelEvents.between(before, rolling, game: .hotDice), [.diceRolled])
        XCTAssertEqual(FeelEvents.between(rolling, rolling, game: .hotDice), [], "one roll, one sound")
        let won = with(before, [(["phase"], "done"), (["winners"], ["p1"])])
        XCTAssertEqual(FeelEvents.between(before, won, game: .hotDice), [.won])
        let june = with(before, [(["phase"], "done"), (["winners"], ["p2"])])
        XCTAssertEqual(FeelEvents.between(before, june, game: .hotDice), [])
    }

    func testRollCallRolls() throws {
        let before = try fixture("rollcall-playing")
        let again = with(before, [(["turn", "rolls"], 2)])
        XCTAssertEqual(FeelEvents.between(before, again, game: .rollCall), [.diceRolled])
    }
}
