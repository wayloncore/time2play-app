import Foundation
import XCTest
@testable import T2PCore

/// Player stats and achievements (#540): the account API's stats read whatever shape it lands in, the phone's ledger
/// adds up, the two merge, and each achievement is earned exactly when it should be.
final class StatsTests: XCTestCase {
    func testReadsTheServersStats() throws {
        let j = JSON.parse(#"{"stats":{"games":12,"wins":4,"byGame":{"farkle":{"played":8,"wins":3,"best":10450},"rollcall":{"played":4,"wins":1,"best":288}},"favorites":["farkle","rollcall"],"newField":1}}"#)!
        let s = try XCTUnwrap(PlayerStats(j))
        XCTAssertEqual(s.games, 12); XCTAssertEqual(s.wins, 4)
        XCTAssertEqual(s.byGame["farkle"]?.best, 10450); XCTAssertEqual(s.favorites, ["farkle", "rollcall"])
        // a flatter shape: totals worked out, favorites ranked by games played
        let flat = try XCTUnwrap(PlayerStats(JSON.parse(#"{"byGame":{"overdraft":{"played":2,"wins":2}},"best":{"closeenough":61}}"#)!))
        XCTAssertEqual(flat.games, 2); XCTAssertEqual(flat.wins, 2); XCTAssertEqual(flat.byGame["closeenough"]?.best, 61)
        XCTAssertEqual(flat.favorites, ["overdraft"])
        XCTAssertNil(PlayerStats(JSON.parse(#"[1,2]"#)!))
    }

    func testLedgerAndMerge() {
        let l = [LedgerEntry(game: .rollCall, won: true, score: 301, flags: ["fullCard"]),
                 LedgerEntry(game: .rollCall, won: false, score: 190),
                 LedgerEntry(game: .hotDice, won: true, score: 10050, flags: ["target10k"])]
        let s = Ledger.stats(l)
        XCTAssertEqual(s.games, 3); XCTAssertEqual(s.wins, 2); XCTAssertEqual(s.byGame["rollcall"]?.best, 301)
        XCTAssertEqual(s.favorites.first, "rollcall")
        var server = PlayerStats(); server.games = 40; server.byGame["farkle"] = .init(played: 30, wins: 9, best: 12000)
        let m = server.merged(with: s)
        XCTAssertEqual(m.games, 40); XCTAssertEqual(m.wins, 2); XCTAssertEqual(m.byGame["farkle"]?.best, 12000)
        XCTAssertEqual(m.byGame["rollcall"]?.played, 2)
        XCTAssertEqual(Ledger.decode(Ledger.encode(l)), l)
        XCTAssertEqual(Ledger.adding(l[0], to: Array(repeating: l[1], count: Ledger.max)).count, Ledger.max)
    }

    func testAchievements() {
        let none = PlayerStats()
        XCTAssertTrue(Achievement.all.allSatisfy { !$0.earned(none, []) }, "nothing earned before a game")
        XCTAssertEqual(Set(Achievement.all.map(\.id)).count, Achievement.all.count, "ids are unique (Game Center's too)")
        let l = [LedgerEntry(game: .rollCall, won: true, score: 301, flags: ["fullCard"]),
                 LedgerEntry(game: .hotDice, won: true, score: 10050, flags: ["target10k"]),
                 LedgerEntry(game: .closeEnough, won: false, score: 80, flags: ["bullseye"]),
                 LedgerEntry(game: .overdraft, won: false, score: nil)]
        let s = Ledger.stats(l)
        let got = Set(Achievement.all.filter { $0.earned(s, l) }.map(\.id))
        XCTAssertEqual(got, ["t2p.first_win", "t2p.all_four", "t2p.hotdice_10k", "t2p.rollcall_full", "t2p.rollcall_300", "t2p.closeenough_bullseye"])
        let ten = Achievement.all.first { $0.id == "t2p.games_10" }!
        XCTAssertEqual(ten.progress(s, l), 0.4, accuracy: 1e-9)
        let near = Ledger.stats([LedgerEntry(game: .rollCall, won: false, score: 299)])
        XCTAssertFalse(Achievement.all.first { $0.id == "t2p.rollcall_300" }!.earned(near, []))
    }
}
