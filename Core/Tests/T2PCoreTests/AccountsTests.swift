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
        XCTAssertTrue(Game.allCases.allSatisfy(\.challengeable), "all four games take invites (Nov 18)")
    }

    /// #575: the peek names who a link is from before it's used, and the owner edits a group.
    func testPeekAndEditGroup() async throws {
        let (a, rec) = api { req in
            if req.url!.path.hasSuffix("/links/peek") {
                let code = JSON.parse(req.httpBody!)!["code"].string
                if code == "FRIEND12" { return (200, #"{"ok":true,"kind":"friend","friend":{"id":"a_2","name":"Sam","face":3},"already":false,"expires":9}"#) }
                if code == "GROUP123" { return (200, #"{"ok":true,"kind":"group","group":{"id":"g_1","name":"Thursday crew","size":4},"already":true,"full":false,"expires":9}"#) }
                return (404, #"{"ok":false,"error":"Not found."}"#)
            }
            return (200, #"{"ok":true,"group":{"id":"g_1","name":"Friday crew","mine":true,"members":[{"id":"a_1","name":"Me","face":1},{"id":"a_2","name":"Sam","face":3}]}}"#)
        }
        let f = try await a.peekLink("FRIEND12")
        XCTAssertEqual(f.question, "Add Sam as a friend?"); XCTAssertFalse(f.already)
        let g = try await a.peekLink("GROUP123")
        XCTAssertEqual(g.question, "Join Thursday crew?"); XCTAssertTrue(g.already)
        XCTAssertEqual(g.kind, .group(id: "g_1", name: "Thursday crew", size: 4))
        // an older server has no peek: it throws, and the app opens the link as before
        do { _ = try await a.peekLink("OLDSERVR"); XCTFail() } catch let e as API.Failure { XCTAssertEqual(e.status, 404) }
        let edited = try await a.editGroup("g_1", name: "Friday crew", add: ["a_2"], remove: ["a_9"])
        XCTAssertEqual(edited?.name, "Friday crew"); XCTAssertEqual(edited?.members.count, 2)
        let body = JSON.parse(rec.requests.last!.httpBody!)!
        XCTAssertEqual(rec.requests.last!.url!.path, "/live/players/groups/edit")
        XCTAssertEqual(body["group"].string, "g_1"); XCTAssertEqual(body["name"].string, "Friday crew")
        XCTAssertEqual(body["add"][0].string, "a_2"); XCTAssertEqual(body["remove"][0].string, "a_9")
        // no name: the server keeps it
        try await a.editGroup("g_1", remove: ["a_2"])
        XCTAssertNil(JSON.parse(rec.requests.last!.httpBody!)!["name"].string)
    }
}
