import Foundation
import XCTest
@testable import T2PCore

final class MessagesTests: XCTestCase {
    func testCodes() {
        XCTAssertEqual(RoomCode.normalize(" ab-c d "), "ABCD")
        XCTAssertNil(RoomCode.normalize("AB0D"), "0 is a lookalike and isn't used")
        XCTAssertNil(RoomCode.normalize("ABCDE"))
        XCTAssertEqual(RoomCode.partial("k7-q0p9"), "K7QP")
        XCTAssertEqual(RoomCode.fromLink(URL(string: "https://time2play.live/k7qp")!), "K7QP")
        XCTAssertEqual(RoomCode.fromLink(URL(string: "https://time2play.live/?room=K7QP")!), "K7QP")
        XCTAssertEqual(RoomCode.fromLink(URL(string: "https://tyleralocke.com/live/farkle-join.html?room=k7qp")!), "K7QP")
        XCTAssertNil(RoomCode.fromLink(URL(string: "https://example.com/K7QP")!))
        XCTAssertEqual(RoomCode.fromScan("time2play.live/K7QP"), "K7QP")
        XCTAssertEqual(RoomCode.fromScan(" k7qp "), "K7QP")
        XCTAssertNil(RoomCode.fromScan("hello there"))
    }

    func testMessagesCarryT() throws {
        XCTAssertEqual(Out.join(name: "Sam", face: 9).text, #"{"face":9,"name":"Sam","t":"join"}"#)
        XCTAssertEqual(Out.hello(app: "ios 1.0").text, #"{"app":"ios 1.0","t":"hello","v":1}"#)
        XCTAssertEqual(Out.hello(app: "ios 1.0", session: "abc").text, #"{"app":"ios 1.0","session":"abc","t":"hello","v":1}"#)
        let seat = Seat(id: "p1", token: "tok", name: "Sam")
        XCTAssertEqual(Out.move("play", ["card": "c1", "suit": "wave"], seat: seat).text,
                       #"{"card":"c1","id":"p1","suit":"wave","t":"play","token":"tok"}"#)
        XCTAssertEqual(Out.addBot(level: "easy").text, #"{"level":"easy","t":"addbot"}"#)
        XCTAssertEqual(Out.react(.gg).text, #"{"r":"gg","t":"react"}"#)
    }

    func testOldAppSurvivesNewServer() {
        XCTAssertEqual(ServerMessage.decode(#"{"t":"hello","v":1,"min":1,"game":"overdraft","update":false,"account":null}"#),
                       .hello(v: 1, min: 1, game: "overdraft", update: false, account: nil))
        if case let .hello(_, _, _, update, _)? = ServerMessage.decode(#"{"t":"hello","v":9,"min":9,"game":"overdraft"}"#) {
            XCTAssertTrue(update, "a server past this app's protocol says Please update")
        } else { XCTFail() }
        XCTAssertEqual(ServerMessage.decode(#"{"t":"tournament","x":1}"#), .unknown("tournament"))
        XCTAssertEqual(ServerMessage.decode(#"{"t":"joined","id":"p1","token":"x","name":"Sam","extra":[1]}"#),
                       .joined(Seat(id: "p1", token: "x", name: "Sam")))
        XCTAssertEqual(ServerMessage.decode(#"{"t":"removed","why":"expired"}"#), .removed(why: "expired"))
        XCTAssertNil(ServerMessage.decode("not json"))
    }

    func testEndpoints() {
        let e = Endpoints.live
        XCTAssertEqual(e.socket(.hotDice, code: "K7QP").absoluteString, "wss://tyleralocke.com/live/farkle/K7QP")
        XCTAssertEqual(e.newRoom(.rollCall).absoluteString, "https://tyleralocke.com/live/rollcall/new?hostless=1")
        XCTAssertEqual(e.screen(.overdraft, code: "K7QP").absoluteString, "wss://tyleralocke.com/live/overdraft/K7QP?as=screen")
        XCTAssertEqual(e.invite(code: "K7QP").absoluteString, "https://time2play.live/K7QP")
    }

    func testCardWords() {
        XCTAssertEqual(Overdraft.Card(kind: "number", suit: "wave", n: 7).label, "Wave 7")
        XCTAssertEqual(Overdraft.Card(kind: "draw2", suit: "ember").label, "Ember +2")
        XCTAssertEqual(Overdraft.Card(kind: "draw2", suit: "ember").spoken, "Ember Draw Two")
        XCTAssertEqual(Overdraft.Card(kind: "wild", suit: nil).label, "Change Suit")
        XCTAssertEqual(Overdraft.Card(kind: "wild4", suit: nil).artName, "draw_four")
        XCTAssertEqual(Overdraft.Card(kind: "skip", suit: "bolt").artName, "bolt_skip")
        XCTAssertEqual(Overdraft.Card(kind: "number", suit: "leaf", n: 0).artName, "leaf_0")
    }

    func testFaces() {
        XCTAssertEqual(Faces.count, 47)
        XCTAssertEqual(Faces.name(9), "otter")
        XCTAssertEqual(Faces.firstFree(preferring: 9, taken: [9, 10]), 11)
    }
}
