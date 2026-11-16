import XCTest
@testable import T2PCore

/// Working out what happened at an Overdraft table from two of its views (#489), as the website's phone page does.
final class OverdraftMovesTests: XCTestCase {
    private func table(turn: String, cards: [Int], pile: [JSON], direction: Int = 1, stack: Int = 0,
                       jump: JSON = nil, over: Bool = false) -> Overdraft.Table {
        let ids = ["p1", "p2", "p3"]
        var seats: [JSON] = []
        for (i, id) in ids.enumerated() {
            let seat: JSON = ["id": .string(id), "seat": .number(Double(i)), "name": .string(id), "face": 0, "cards": .number(Double(cards[i]))]
            seats.append(seat)
        }
        let j: JSON = ["n": 1, "turn": .string(turn), "pile": .array(pile), "direction": .number(Double(direction)),
                       "stack": .number(Double(stack)), "jump": jump, "over": .bool(over), "seats": .array(seats), "seq": 1]
        return Overdraft.Table(j)
    }
    private func card(_ kind: String, _ suit: String?, _ n: Int? = nil, k: Int) -> JSON {
        ["kind": .string(kind), "suit": suit.map { JSON.string($0) } ?? .null, "n": n.map { JSON.number(Double($0)) } ?? .null, "k": .number(Double(k))]
    }

    func testAPlayAndADraw() {
        let a = table(turn: "p1", cards: [7, 7, 7], pile: [card("number", "wave", 3, k: 0)])
        let b = table(turn: "p2", cards: [6, 7, 7], pile: [card("number", "wave", 3, k: 0), card("number", "wave", 7, k: 1)])
        XCTAssertEqual(Overdraft.moves(from: a, to: b), [.played(by: "p1", card: Overdraft.Card(kind: "number", suit: "wave", n: 7, k: 1), jump: false)])
        let c = table(turn: "p3", cards: [6, 8, 7], pile: [card("number", "wave", 3, k: 0), card("number", "wave", 7, k: 1)])
        XCTAssertEqual(Overdraft.moves(from: b, to: c), [.drew(who: "p2", n: 1)])
    }

    func testSkipAndReverse() {
        let a = table(turn: "p1", cards: [7, 7, 7], pile: [card("number", "wave", 3, k: 0)])
        let skip = table(turn: "p3", cards: [6, 7, 7], pile: [card("number", "wave", 3, k: 0), card("skip", "wave", k: 1)])
        XCTAssertEqual(Overdraft.moves(from: a, to: skip).last, .skipped(who: "p2", by: "p1"))
        let rev = table(turn: "p3", cards: [6, 7, 7], pile: [card("number", "wave", 3, k: 0), card("reverse", "wave", k: 1)], direction: -1)
        XCTAssertEqual(Overdraft.moves(from: a, to: rev).last, .reversed(by: "p1"))
        XCTAssertTrue(Overdraft.moves(from: a, to: rev).last!.isBig)
    }

    func testAPlusTwoLandsWithNoStacking() {
        let a = table(turn: "p1", cards: [7, 7, 7], pile: [card("number", "wave", 3, k: 0)])
        let b = table(turn: "p2", cards: [6, 9, 7], pile: [card("number", "wave", 3, k: 0), card("draw2", "wave", k: 1)])
        let m = Overdraft.moves(from: a, to: b)
        XCTAssertEqual(m.count, 2)
        XCTAssertEqual(m.last, .hit(who: "p2", n: 2, by: "p1", card: Overdraft.Card(kind: "draw2", suit: "wave", k: 1)))
    }

    func testATrainTaken() {
        let a = table(turn: "p2", cards: [6, 7, 7], pile: [card("draw2", "wave", k: 1)], stack: 4)
        let b = table(turn: "p3", cards: [6, 11, 7], pile: [card("draw2", "wave", k: 1)])
        XCTAssertEqual(Overdraft.moves(from: a, to: b), [.tookTrain(who: "p2", n: 4)])
    }

    func testAJumpIn() {
        let a = table(turn: "p2", cards: [6, 7, 7], pile: [card("number", "leaf", 5, k: 1)])
        let b = table(turn: "p1", cards: [6, 7, 6], pile: [card("number", "leaf", 5, k: 1), card("number", "leaf", 5, k: 2)], jump: ["id": "p3", "seq": 2])
        XCTAssertEqual(Overdraft.moves(from: a, to: b), [.played(by: "p3", card: Overdraft.Card(kind: "number", suit: "leaf", n: 5, k: 2), jump: true)])
    }

    func testANewHandSaysNothing() {
        let a = table(turn: "p2", cards: [1, 7, 7], pile: [card("number", "leaf", 5, k: 30)])
        let b = table(turn: "p1", cards: [7, 7, 7], pile: [card("number", "wave", 2, k: 0)])
        XCTAssertEqual(Overdraft.moves(from: a, to: b), [])
        XCTAssertEqual(Overdraft.moves(from: nil, to: b), [])
    }
}
