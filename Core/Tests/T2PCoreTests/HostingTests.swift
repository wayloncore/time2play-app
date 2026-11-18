import XCTest
@testable import T2PCore

/// Hosting from an iPad (#537): the website host pages' own paths and messages, and the floor read for every game.
final class HostingTests: XCTestCase {
    func testPathsAndMessages() async throws {
        let e = Endpoints.live
        XCTAssertEqual(e.newHostedRoom(.hotDice).absoluteString, "https://tyleralocke.com/live/farkle/new", "no ?hostless: a hosted room")
        let r = HostedRoom(game: .closeEnough, code: "K7QP", hostToken: "tok")
        XCTAssertEqual(e.hostScreen(r).absoluteString, "wss://tyleralocke.com/live/closeenough/K7QP?as=screen&host=tok")
        XCTAssertEqual(Out.host(Out.deal, token: "tok").text, #"{"hostToken":"tok","t":"deal"}"#)
        XCTAssertEqual(Out.host(Out.addBot(level: "easy"), token: "tok").text, #"{"hostToken":"tok","level":"easy","t":"addbot"}"#)
        XCTAssertEqual(Out.landed(seq: 3).text, #"{"seq":3,"t":"landed"}"#)

        let api = API(fetch: { req in
            XCTAssertEqual(req.url?.absoluteString, "https://tyleralocke.com/live/overdraft/new")
            return (200, Data(#"{"code":"k7qp","hostToken":"abc"}"#.utf8))
        })
        let room = try await api.startHostedRoom(.overdraft)
        XCTAssertEqual(room, HostedRoom(game: .overdraft, code: "K7QP", hostToken: "abc"))
        let hostless = API(fetch: { _ in (200, Data(#"{"code":"K7QP","hostless":true}"#.utf8)) })
        do { _ = try await hostless.startHostedRoom(.overdraft); XCTFail("no token, no hosting") } catch {}
    }

    func testFloorPlayers() {
        let od = JSON.parse(#"{"phase":"playing","roster":null,"tables":[{"turn":"p2","seats":[{"id":"p1","name":"Sam","face":9,"cards":7,"connected":true},{"id":"p2","name":"Ada (bot)","face":0,"cards":6,"connected":true}]}]}"#)!
        let a = Floor.players(od, game: .overdraft)
        XCTAssertEqual(a.map(\.name), ["Sam", "Ada"])
        XCTAssertEqual(a[1].bot, "bot"); XCTAssertTrue(a[1].turn); XCTAssertEqual(a[0].cards, 7)
        let lobby = JSON.parse(#"{"phase":"lobby","roster":[{"id":"p1","name":"Sam","face":9,"bot":null}],"tables":[]}"#)!
        XCTAssertEqual(Floor.players(lobby, game: .overdraft).count, 1)
        let hd = JSON.parse(#"{"players":[{"id":"p1","name":"Sam","face":9,"score":350},{"id":"p2","name":"June","bot":"steady","score":0,"left":true}],"turn":{"id":"p1","state":"rolling","seq":4}}"#)!
        XCTAssertEqual(Floor.players(hd, game: .hotDice).map(\.score), [350], "a player who left isn't listed")
        XCTAssertEqual(Floor.rolling(hd), 4)
        XCTAssertEqual(Floor.watching(hd), 0, "no spectators until the server says")
    }
}
