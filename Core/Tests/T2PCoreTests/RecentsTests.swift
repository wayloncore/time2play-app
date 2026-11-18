import Foundation
import XCTest
@testable import T2PCore

/// Recent rooms on Play, the widget's game of the day, and the website's join paths.
final class RecentsTests: XCTestCase {
    func testRecentRoomsNewestFirstOnceEach() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var list: [RecentRoom] = []
        list = RecentRoom.adding(RecentRoom(code: "K7QP", game: .overdraft, at: now.addingTimeInterval(-60)), to: list, now: now)
        list = RecentRoom.adding(RecentRoom(code: "ABCD", game: .hotDice, at: now), to: list, now: now)
        list = RecentRoom.adding(RecentRoom(code: "K7QP", game: .overdraft, at: now), to: list, now: now)
        XCTAssertEqual(list.map(\.code), ["K7QP", "ABCD"])
        let old = RecentRoom(code: "ZZZZ", game: .rollCall, at: now.addingTimeInterval(-2 * 86_400))
        XCTAssertEqual(RecentRoom.fresh(list + [old], now: now).map(\.code), ["K7QP", "ABCD"], "a room from days ago is gone")
        let many = (0..<12).reduce([RecentRoom]()) { l, i in RecentRoom.adding(RecentRoom(code: "AB\(i % 8 + 2)\(i / 8 + 2)", game: .overdraft, at: now), to: l, now: now) }
        XCTAssertEqual(many.count, 8)
        // saved as plain text fields, so the previous version (and a new game) still reads them
        let data = try! JSONEncoder().encode(list)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(#""game":"farkle""#))
        XCTAssertEqual(try JSONDecoder().decode([RecentRoom].self, from: data), list)
        XCTAssertEqual(list[1].playable, .hotDice)
    }

    /// Nov 18: who was in a room, saved with it. The list saved before (no such fields) still reads, and the previous
    /// version reads the new one (it ignores fields it doesn't know).
    func testWhoWasInItReadsBothWays() throws {
        let before = #"[{"code":"K7QP","game":"farkle","at":800000000}]"#
        let old = try JSONDecoder().decode([RecentRoom].self, from: Data(before.utf8))
        XCTAssertEqual(old.first?.code, "K7QP"); XCTAssertNil(old.first?.players); XCTAssertNil(old.first?.whoLine)
        var r = RecentRoom(code: "ABCD", game: .rollCall)
        r.players = 3; r.bots = 2; r.others = []; r.solo = true
        XCTAssertEqual(r.whoLine, "You and 2 bots")
        r.others = ["Sam", "Jo"]; r.bots = 1
        XCTAssertEqual(r.whoLine, "With Sam and Jo, and 1 bot")
        r.others = ["Sam", "Jo", "Priya", "Lena"]; r.bots = 0
        XCTAssertEqual(r.whoLine, "With Sam, Jo and 2 more")
        r.others = nil; r.bots = nil; r.players = 4
        XCTAssertEqual(r.whoLine, "4 players")
        let data = try JSONEncoder().encode([r])
        struct Previous: Decodable { var code: String; var game: String; var at: Date }   // the version before's fields
        XCTAssertEqual(try JSONDecoder().decode([Previous].self, from: data).first?.code, "ABCD")
        XCTAssertEqual(try JSONDecoder().decode([RecentRoom].self, from: data), [r])
    }

    func testGameOfTheDayStepsThroughTheLibrary() throws {
        let lib = Library.appOnly
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "America/New_York")!
        let day = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 9)))
        let a = try XCTUnwrap(lib.gameOfTheDay(day, calendar: cal))
        let late = try XCTUnwrap(lib.gameOfTheDay(day.addingTimeInterval(13 * 3600), calendar: cal))
        XCTAssertEqual(a.key, late.key, "the same card all day")
        var seen = Set<String>()
        for d in 0..<4 { seen.insert(try XCTUnwrap(lib.gameOfTheDay(day.addingTimeInterval(Double(d) * 86_400), calendar: cal)).key) }
        XCTAssertEqual(seen.count, 4, "four days, the four games")
        XCTAssertNil(Library().gameOfTheDay(day))
    }

    func testWebsiteJoinPaths() {
        XCTAssertEqual(RoomCode.fromLink(URL(string: "https://tyleralocke.com/j/k7qp")!), "K7QP")
        XCTAssertEqual(RoomCode.fromLink(URL(string: "https://tyleralocke.com/join/K7QP")!), "K7QP")
        XCTAssertEqual(RoomCode.fromLink(URL(string: "https://time2play.live/join/K7QP")!), "K7QP")
        XCTAssertNil(RoomCode.fromLink(URL(string: "https://tyleralocke.com/library/K7QP")!))
        XCTAssertEqual(RoomCode.fromScan("https://time2play.live/K7QP"), "K7QP")
    }
}
