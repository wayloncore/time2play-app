import Foundation
import XCTest
@testable import T2PCore

final class FakeTransport: RoomTransport {
    var sent: [JSON] = []
    var opened: [URL] = []
    var closed = 0
    var onEvent: ((TransportEvent) -> Void)?
    func open(_ url: URL, onEvent: @escaping (TransportEvent) -> Void) { opened.append(url); self.onEvent = onEvent }
    func send(_ text: String) { sent.append(JSON.parse(text)!) }
    func close() { closed += 1 }
    func server(_ text: String) { onEvent?(.text(text)) }
    var lastT: String? { sent.last?["t"].string }
}

final class RoomSessionTests: XCTestCase {
    func make(store: SeatStore = MemorySeatStore()) -> (RoomSession, FakeTransport) {
        let t = FakeTransport()
        let s = RoomSession(game: .overdraft, code: "K7QP", appVersion: "1.0", transport: t, store: store)
        return (s, t)
    }

    func testHelloThenJoinThenView() {
        let (s, t) = make()
        s.start()
        XCTAssertEqual(t.opened.first?.absoluteString, "wss://tyleralocke.com/live/overdraft/K7QP")
        t.onEvent?(.opened)
        XCTAssertEqual(t.lastT, "hello")
        t.server(#"{"t":"hello","v":1,"min":1,"game":"overdraft","update":false,"account":null}"#)
        XCTAssertEqual(s.status, .choosing(problem: nil))
        s.join(name: "Sam", face: 9)
        XCTAssertEqual(t.lastT, "join"); XCTAssertEqual(t.sent.last?["face"].int, 9)
        t.server(#"{"t":"joined","id":"p1","token":"tok","name":"Sam"}"#)
        XCTAssertEqual(s.status, .inRoom); XCTAssertEqual(s.seat?.id, "p1")
        t.server(#"{"t":"you","ok":true,"phase":"lobby","code":"K7QP","you":{"id":"p1","name":"Sam","face":9},"hostless":true,"owner":"p1","roster":[]}"#)
        XCTAssertEqual(s.view?["owner"].string, "p1")
    }

    func testPleaseUpdate() {
        let (s, t) = make()
        s.start(); t.onEvent?(.opened)
        t.server(#"{"t":"hello","v":3,"min":2,"game":"overdraft","update":true}"#)
        XCTAssertEqual(s.status, .needsUpdate)
        XCTAssertEqual(t.closed, 1)
        s.reconnect()
        XCTAssertEqual(t.opened.count, 1, "an app too old for the server stops at Please update")
    }

    func testDropThenResumeSaysWhatTheBotDid() {
        let store = MemorySeatStore()
        let (s, t) = make(store: store)
        var notices: [RoomSession.Notice] = []
        s.onNotice = { notices.append($0) }
        s.join(name: "Sam", face: 9)
        s.start(); t.onEvent?(.opened)
        t.server(#"{"t":"hello","v":1,"min":1,"update":false}"#)
        XCTAssertEqual(t.lastT, "join", "a name given before the socket opened joins once it has")
        t.server(#"{"t":"joined","id":"p1","token":"tok","name":"Sam"}"#)
        t.server(#"{"t":"you","phase":"playing","hand":[{"id":"c1"},{"id":"c2"},{"id":"c3"}]}"#)
        // the phone locks: the socket drops
        t.onEvent?(.closed(code: 1006))
        XCTAssertEqual(s.status, .reconnecting(attempt: 1))
        XCTAssertEqual(s.reconnectDelay, 0.5)
        s.reconnect(); t.onEvent?(.opened)
        t.server(#"{"t":"hello","v":1,"min":1,"update":false}"#)
        XCTAssertEqual(t.lastT, "resume"); XCTAssertEqual(t.sent.last?["token"].string, "tok")
        t.server(#"{"t":"resumed","id":"p1"}"#)
        t.server(#"{"t":"you","phase":"playing","hand":[{"id":"c3"},{"id":"c9"}]}"#)
        XCTAssertEqual(notices.last, .back("You’re back. The bot played 2 cards for you."))
        XCTAssertEqual(s.status, .inRoom)
    }

    func testSavedSeatResumesAcrossLaunches() {
        let store = MemorySeatStore()
        store.save(SavedSeat(code: "K7QP", game: .overdraft, seat: Seat(id: "p4", token: "t4", name: "Sam")))
        let (s, t) = make(store: store)
        s.start(); t.onEvent?(.opened)
        t.server(#"{"t":"hello","v":1,"min":1,"update":false}"#)
        XCTAssertEqual(t.lastT, "resume"); XCTAssertEqual(t.sent.last?["id"].string, "p4")
        // the seat is gone (the room forgot it): join afresh only once a name is given
        t.server(#"{"t":"error","error":"No such player.","code":"gone"}"#)
        XCTAssertNil(store.seat(for: "K7QP"))
        XCTAssertEqual(s.status, .choosing(problem: nil))
    }

    func testEndingsAreFinal() {
        let (s, t) = make()
        s.start(); t.onEvent?(.opened)
        t.server(#"{"t":"hello","v":1,"min":1,"update":false}"#)
        s.join(name: "Sam", face: 1)
        t.server(#"{"t":"joined","id":"p1","token":"tok","name":"Sam"}"#)
        t.server(#"{"t":"ended"}"#)
        XCTAssertEqual(s.status, .ended(.closedByOwner))
        t.onEvent?(.closed(code: 4005))
        XCTAssertEqual(s.status, .ended(.closedByOwner))
        s.reconnect()
        XCTAssertEqual(t.opened.count, 1)
    }

    func testJoinProblems() {
        let (s, t) = make()
        s.start(); t.onEvent?(.opened)
        t.server(#"{"t":"hello","v":1,"min":1,"update":false}"#)
        s.join(name: "Sam", face: 3)
        t.server(#"{"t":"error","error":"Someone just took that one, pick another.","code":"face_taken"}"#)
        XCTAssertEqual(s.status, .choosing(problem: "Someone just took that one, pick another."))
        s.join(name: "Sam", face: 4)
        t.server(#"{"t":"error","error":"The table is full at 10 players.","code":"table_full"}"#)
        XCTAssertEqual(s.status, .ended(.refused("The table is full at 10 players.")))
    }

    func testReactionsAndProblems() {
        let (s, t) = make()
        var notices: [RoomSession.Notice] = []
        s.onNotice = { notices.append($0) }
        s.start(); t.onEvent?(.opened)
        t.server(#"{"t":"hello","v":1,"min":1,"update":false}"#)
        s.join(name: "Sam", face: 3)
        t.server(#"{"t":"joined","id":"p1","token":"tok","name":"Sam"}"#)
        t.server(#"{"t":"react","id":"p2","r":"gg"}"#)
        t.server(#"{"t":"react","id":"p2","r":"free text"}"#)
        t.server(#"{"t":"error","error":"It isn't your turn."}"#)
        XCTAssertEqual(notices, [.reaction(playerId: "p2", .gg), .problem("It isn't your turn.")])
        s.move("draw")
        XCTAssertEqual(t.sent.last?.text, #"{"id":"p1","t":"draw","token":"tok"}"#)
    }

    func testBackoff() {
        let (s, t) = make()
        s.start()
        for _ in 0..<8 { t.onEvent?(.closed(code: nil)); s.reconnect() }
        XCTAssertEqual(s.reconnectDelay, 15)
    }
}
