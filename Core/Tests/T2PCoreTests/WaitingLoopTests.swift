import XCTest
@testable import T2PCore

/// The waiting screen's logo (wayloncore/tyleralocke#543): the intro in place of one pass in six, and when it shows.
final class WaitingLoopTests: XCTestCase {
    func testTheIntroTakesOnePassInSix() {
        let first = (0..<12).map { WaitingLoopPlan.clip(forPass: $0) }
        XCTAssertEqual(first.filter { $0 == .intro }.count, 2, "twice in two cycles")
        XCTAssertEqual(WaitingLoopPlan.clip(forPass: 0), .loop, "the screen opens on the loop")
        XCTAssertEqual(WaitingLoopPlan.clip(forPass: 5), .intro)
        XCTAssertEqual(WaitingLoopPlan.clip(forPass: 6), .loop, "back to the loop after the intro")
        XCTAssertEqual(WaitingLoopPlan.clip(forPass: 11), .intro)
        XCTAssertEqual(WaitingLoopPlan.clip(forPass: -1), .loop)
    }

    func testWhenItShows() {
        XCTAssertEqual(WaitingLoopPlan.mode(phase: "lobby", on: true, reduceMotion: false, lowPower: false), .moving)
        XCTAssertEqual(WaitingLoopPlan.mode(phase: nil, on: true, reduceMotion: false, lowPower: false), .moving, "no view yet reads as the lobby")
        XCTAssertEqual(WaitingLoopPlan.mode(phase: "playing", on: true, reduceMotion: false, lowPower: false), .hidden, "stops when the game starts")
        XCTAssertEqual(WaitingLoopPlan.mode(phase: "done", on: true, reduceMotion: false, lowPower: false), .hidden)
        XCTAssertEqual(WaitingLoopPlan.mode(phase: "lobby", on: false, reduceMotion: false, lowPower: false), .hidden, "the setting off")
        XCTAssertEqual(WaitingLoopPlan.mode(phase: "lobby", on: true, reduceMotion: true, lowPower: false), .still, "Reduce Motion: the still mark")
        XCTAssertEqual(WaitingLoopPlan.mode(phase: "lobby", on: true, reduceMotion: false, lowPower: true), .still, "Low Power Mode: the still mark")
    }
}
