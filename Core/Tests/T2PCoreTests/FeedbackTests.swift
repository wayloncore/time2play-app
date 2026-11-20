import XCTest
@testable import T2PCore

/// #594 (the report, the frame numbers, the rating request), #596 (when the join logo plays), #598 (the tips) and
/// #595 (the dice games' new names, and no trademarked names anywhere a player reads).
final class FeedbackTests: XCTestCase {
    func testFrameMeter() {
        var m = FrameMeter()
        for _ in 0..<600 { m.add(1.0 / 60, expected: 1.0 / 60) }     // 10 s at 60 fps
        m.add(0.14, expected: 1.0 / 60)                               // one stutter
        m.add(30, expected: 1.0 / 60)                                 // the phone locked: a pause, not a frame
        XCTAssertEqual(m.frames, 601)
        XCTAssertEqual(m.hitches, 1)
        XCTAssertEqual(m.worst, 0.14, accuracy: 0.0001)
        XCTAssertEqual(m.averageFPS, 59.2, accuracy: 0.2)
        let s = m.summary(game: "farkle", at: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(s?.fps, 59); XCTAssertEqual(s?.worstMs, 140); XCTAssertEqual(s?.hitches, 1)
        XCTAssertEqual(s?.line, "10,000: 59 fps on average, worst frame 140 ms, 1 stutter in 1 min")
        XCTAssertNil(FrameMeter().summary(game: "farkle"), "nothing measured, nothing kept")
        // saved data: it reads back
        let data = try! JSONEncoder().encode(s)
        XCTAssertEqual(try! JSONDecoder().decode(FrameSummary.self, from: data), s)
    }

    func testReportText() {
        let frames = FrameSummary(game: "rollcall", fps: 58, worstMs: 120, hitches: 3, seconds: 240, at: Date())
        let r = AppReport(choices: [.slow, .froze], words: "  The dice stuck after the third roll.  ",
                          device: "iPhone16,1", system: "18.1", version: "1.1", build: "52", frames: frames)
        XCTAssertTrue(r.ready)
        XCTAssertEqual(r.text, """
            From the Time2Play app (You, Send a report).
            What happened: Slow or laggy, Froze or closed
            In their words: The dice stuck after the third roll.
            Device: iPhone16,1
            iOS: 18.1
            App: 1.1 (build 52)
            Last game: Yacht Dice: 58 fps on average, worst frame 120 ms, 3 stutters in 4 min
            """)
        XCTAssertEqual(r.page, "/app/ios/1.1/52")
        let b = r.body(elapsedMs: 4200)
        XCTAssertEqual(b["elapsed"].int, 4200); XCTAssertEqual(b["website"].string, ""); XCTAssertEqual(b["text"].string, r.text)
        // the website's form needs 10 to 1,000 characters
        let empty = AppReport(choices: [], words: String(repeating: "x", count: 5000), device: "d", system: "s", version: "v", build: "b", frames: nil)
        XCTAssertLessThanOrEqual(empty.text.count, 1000)
        XCTAssertGreaterThanOrEqual(AppReport(choices: [.other], words: "", device: "d", system: "s", version: "v", build: "b", frames: nil).text.count, 10)
        XCTAssertFalse(AppReport(choices: [], words: "  ", device: "d", system: "s", version: "v", build: "b", frames: nil).ready)
    }

    /// The digest takes anything that looks like a phone number out of a report before filing it (problems.js
    /// forGitHub). The facts mustn't look like one.
    func testReportSurvivesThePhoneFilter() throws {
        let r = AppReport(choices: [.slow], words: "", device: "iPhone17,2", system: "26.0.1", version: "1.1", build: "1234",
                          frames: FrameSummary(game: "farkle", fps: 60, worstMs: 1450, hitches: 12, seconds: 3600, at: Date()))
        let phone = try NSRegularExpression(pattern: #"(?<![\w])\+?\d[\d\s().-]{6,}\d(?![\w])"#)
        let t = r.text
        XCTAssertEqual(phone.numberOfMatches(in: t, range: NSRange(t.startIndex..., in: t)), 0, t)
    }

    func testReviewAsk() {
        XCTAssertTrue(ReviewAsk.shouldAsk(finishedGame: true, lastAskedVersion: nil, version: "1.1"))
        XCTAssertFalse(ReviewAsk.shouldAsk(finishedGame: true, lastAskedVersion: "1.1", version: "1.1"), "once per version")
        XCTAssertTrue(ReviewAsk.shouldAsk(finishedGame: true, lastAskedVersion: "1.1", version: "1.2"))
        XCTAssertFalse(ReviewAsk.shouldAsk(finishedGame: false, lastAskedVersion: nil, version: "1.1"), "only after a finished game")
    }

    func testJoinIntroPlan() {
        XCTAssertTrue(JoinIntroPlan.plays(on: true, starting: false, offline: false, returning: false), "joining someone's room")
        XCTAssertFalse(JoinIntroPlan.plays(on: true, starting: true, offline: false, returning: false), "your own new room")
        XCTAssertFalse(JoinIntroPlan.plays(on: true, starting: false, offline: true, returning: false), "practice")
        XCTAssertFalse(JoinIntroPlan.plays(on: true, starting: false, offline: false, returning: true), "back to your seat")
        XCTAssertFalse(JoinIntroPlan.plays(on: false, starting: false, offline: false, returning: false), "turned off in You")
    }

    func testTips() {
        XCTAssertEqual(Tips.ids, ["live.time2play.app.tip.small", "live.time2play.app.tip.big", "live.time2play.app.tip.huge"])
        XCTAssertEqual(Tips.all.map(\.price), ["1.99", "4.99", "9.99"])
        XCTAssertEqual(Set(Tips.ids).count, 3)
    }

    /// #595: the new names, and no "Yahtzee" or "Farkle" in anything the app shows from its core (the ids stay).
    func testDiceGameNames() {
        XCTAssertEqual(Game.hotDice.title, "10,000"); XCTAssertEqual(Game.rollCall.title, "Yacht Dice")
        XCTAssertEqual(Game.hotDice.rawValue, "farkle"); XCTAssertEqual(Game.rollCall.rawValue, "rollcall")
        XCTAssertEqual(RollCall.boxName("five"), "Yacht")
        var shown = Game.allCases.flatMap { [$0.title, $0.blurb] } + RollCall.boxes.map(\.name)
        shown += Achievement.all.flatMap { [$0.title, $0.detail] }
        shown += [HotDice.farkleWhy(dice: 6), HotDice.farkleWhy(dice: 3)]
        for s in shown {
            XCTAssertFalse(s.lowercased().contains("farkle"), s)
            XCTAssertFalse(s.lowercased().contains("yahtzee"), s)
            XCTAssertFalse(s.contains("Roll Call") || s.contains("Hot Dice"), s)
        }
    }
}
