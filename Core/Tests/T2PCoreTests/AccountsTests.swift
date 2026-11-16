import Foundation
import XCTest
@testable import T2PCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class AccountsTests: XCTestCase {
    final class Recorder: @unchecked Sendable { var requests: [URLRequest] = [] }

    func api(_ answer: @escaping @Sendable (URLRequest) -> (Int, String)) -> (API, Recorder) {
        let rec = Recorder()
        let a = API(fetch: { req in rec.requests.append(req); let (s, b) = answer(req); return (s, Data(b.utf8)) })
        a.appVersion = "ios 1.0"
        return (a, rec)
    }

    func testSignInThenTheSessionTravelsInAHeader() async throws {
        let (a, rec) = api { req in
            if req.url!.path.hasSuffix("/review") { return (200, #"{"ok":true,"account":{"id":"a_1","name":"Reviewer","face":9,"created":1},"token":"t0k3n","expires":2}"#) }
            return (200, #"{"ok":true,"friends":[{"id":"a_2","name":"Maya","face":8}],"incoming":[],"outgoing":[],"recent":[{"id":"a_3","name":"Sam","face":7}]}"#)
        }
        let s = try await a.signInForReview(key: "k", app: "ios 1.0")
        XCTAssertEqual(s.account.name, "Reviewer"); XCTAssertEqual(s.token, "t0k3n")
        XCTAssertEqual(rec.requests[0].url?.absoluteString, "https://tyleralocke.com/live/players/review")
        XCTAssertNil(rec.requests[0].value(forHTTPHeaderField: "authorization"), "no session before signing in")
        a.session = s.token
        let f = try await a.friends()
        XCTAssertEqual(f.friends.first?.name, "Maya"); XCTAssertEqual(f.recent.first?.id, "a_3")
        XCTAssertEqual(rec.requests[1].value(forHTTPHeaderField: "authorization"), "Bearer t0k3n")
        XCTAssertEqual(rec.requests[1].value(forHTTPHeaderField: "x-t2p-app"), "ios 1.0")
        XCTAssertFalse(rec.requests[1].url!.absoluteString.contains("t0k3n"), "the session never goes in an address")
    }

    func testServerWordsComeThrough() async {
        let (a, _) = api { _ in (403, #"{"ok":false,"error":"Accounts are for 13 and up. You can still play as a guest.","code":"age"}"#) }
        do { _ = try await a.signInWithApple(identityToken: "x", name: "Ana", face: 1, over13: false, app: "ios 1.0"); XCTFail() }
        catch let f as API.Failure { XCTAssertEqual(f.code, "age"); XCTAssertTrue(f.message.contains("13 and up")) }
        catch { XCTFail("\(error)") }
    }

    func testChallengesAndLinks() async throws {
        let (a, rec) = api { _ in (200, #"{"ok":true,"challenges":[{"id":"c_1","from":{"id":"a_2","name":"Maya","face":8},"game":"farkle","room":"K7QP","created":5}]}"#) }
        let c = try await a.challenges()
        XCTAssertEqual(c.first?.game, .hotDice); XCTAssertEqual(c.first?.from.name, "Maya")
        try await a.sendChallenge(game: .overdraft, room: "K7QP", to: ["a_2"])
        let body = JSON.parse(rec.requests.last!.httpBody!)!
        XCTAssertEqual(body["game"].string, "overdraft"); XCTAssertEqual(body["to"][0].string, "a_2")
        XCTAssertEqual(FriendLink.code(URL(string: "https://time2play.live/f/ab12cd34")!), "AB12CD34")
        XCTAssertNil(FriendLink.code(URL(string: "https://time2play.live/K7QP")!))
        XCTAssertEqual(RoomCode.fromLink(URL(string: "time2play://join/k7qp")!), "K7QP")
        XCTAssertTrue(Game.hotDice.challengeable); XCTAssertFalse(Game.rollCall.challengeable)
    }
}
