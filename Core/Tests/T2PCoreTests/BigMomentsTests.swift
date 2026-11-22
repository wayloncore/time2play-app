import XCTest
@testable import T2PCore

/// #718: option C, big moments only (docs/app/cinematic.md).
final class BigMomentsTests: XCTestCase {
    private func run(_ d: inout MomentDirector, for secs: Double, dt: Double = 1.0 / 60, _ each: (MomentShot) -> Void = { _ in }) {
        var t = 0.0
        while t < secs - 1e-9 { each(d.step(dt)); t += dt }
    }

    func testStyleFromArgs() {
        XCTAssertEqual(CinemaStyle.from(["app", "-t2p-cinema", "moments"]), .moments)
    }

    func testCalmUntilAMoment() {
        var d = MomentDirector()
        run(&d, for: 3) { XCTAssertEqual($0, .calm) }
    }

    func testOneSequenceIsOneToTwoSeconds() {
        for k in MomentKind.allCases {
            var d = MomentDirector()
            XCTAssertTrue(d.cue(k))
            var slow = 0.0, minScale = 1.0, end = 0.0, t = 0.0
            // the scene calls the payoff about 0.4 s in (the return stroke, the dice reaching the felt); a kind with a
            // shorter wind-up has had it come by itself
            while t < 4 {
                if abs(t - 0.4) < 0.004 { d.payoff() }
                let s = d.step(1.0 / 120); t += 1.0 / 120
                if s.camera.timeScale < 0.999 { slow = t }
                minScale = min(minScale, s.camera.timeScale)
                if s.grade > 0.001 || s.camera.push > 0.001 { end = t }
            }
            XCTAssertEqual(minScale, k.tuning.slow, accuracy: 0.01, "\(k) reaches its slow motion")
            XCTAssertGreaterThanOrEqual(slow, 1.0, "\(k): the slow motion lasts at least a second")
            XCTAssertLessThanOrEqual(slow, 2.0, "\(k): and at most two")
            XCTAssertLessThanOrEqual(end, 2.5, "\(k): the push and the grade have eased out half a second later")
            XCTAssertEqual(d.phase, .idle)
        }
    }

    func testPayoffStartsTheHold() {
        var d = MomentDirector()
        d.cue(.overdraft)
        run(&d, for: 0.15)
        XCTAssertEqual(d.phase, .windUp)
        d.payoff()
        XCTAssertEqual(d.phase, .hold)
        XCTAssertGreaterThan(d.trauma.value, 0.5, "an Overdraft lands with a knock")
        run(&d, for: 0.3)
        XCTAssertEqual(d.shot().camera.timeScale, 0.3, accuracy: 0.01, "an early payoff still eases into the full slow motion")
    }

    func testNoJumps() {
        // every value moves smoothly frame to frame (no cut, no snap), with an early payoff in the middle
        var d = MomentDirector()
        d.cue(.farkle)
        var last = d.step(1.0 / 60)
        for i in 0..<180 {
            if i == 10 { d.payoff() }
            let s = d.step(1.0 / 60)
            XCTAssertLessThan(abs(s.camera.timeScale - last.camera.timeScale), 0.12, "frame \(i)")
            XCTAssertLessThan(abs(s.camera.push - last.camera.push), 0.12, "frame \(i)")
            XCTAssertLessThan(abs(s.camera.dim - last.camera.dim), 0.12, "frame \(i)")
            XCTAssertLessThan(abs(s.grade - last.grade), 0.12, "frame \(i)")
            last = s
        }
    }

    func testOneAtATimeWithACoolDown() {
        var d = MomentDirector()
        XCTAssertTrue(d.cue(.overdraft))
        XCTAssertFalse(d.cue(.suitChange), "a second moment during a sequence is dropped")
        run(&d, for: 2.5)
        XCTAssertEqual(d.phase, .idle)
        XCTAssertFalse(d.cue(.overdraft), "the cool-down keeps sequences apart")
        run(&d, for: 1.3)
        XCTAssertTrue(d.cue(.overdraft))
    }

    func testShakeIsSmallAndFalls() {
        var d = MomentDirector()
        d.cue(.overdraft); d.payoff()
        var most = 0.0
        run(&d, for: 0.3) { most = max(most, abs($0.camera.roll)) }
        XCTAssertGreaterThan(most, 0, "it shakes")
        XCTAssertLessThanOrEqual(most, 0.024 * 0.36 + 1e-9, "at most about half a degree")
        run(&d, for: 1)
        XCTAssertEqual(d.shot().camera.roll, 0, "and it's gone in well under a second and a half")
    }

    func testReduceMotionIsADipOfTheLightOnly() {
        var d = MomentDirector()
        d.reduced = true
        XCTAssertTrue(d.cue(.overdraft))
        d.payoff(); d.knock(1)
        var dimmed = 0.0
        run(&d, for: 1.5) { s in
            XCTAssertEqual(s.camera.timeScale, 1, "no slow motion")
            XCTAssertEqual(s.camera.push, 0, "no push")
            XCTAssertEqual(s.camera.roll, 0, "no shake")
            XCTAssertEqual(s.grade, 0, "no grade")
            dimmed = max(dimmed, s.camera.dim)
        }
        XCTAssertEqual(dimmed, 0.5, accuracy: 0.01, "the moment is still told, by the light")
        XCTAssertEqual(d.shot().camera.dim, 0, "and it comes back")
    }

    func testReduceMotionMidSequenceStopsIt() {
        var d = MomentDirector()
        d.cue(.hotDice)
        run(&d, for: 0.4)
        d.reduced = true
        XCTAssertEqual(d.step(1.0 / 60).camera.timeScale, 1)
        XCTAssertEqual(d.phase, .idle)
    }
}
