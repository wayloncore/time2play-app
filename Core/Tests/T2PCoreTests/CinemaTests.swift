import XCTest
@testable import T2PCore

/// #716: option A's director (docs/app/cinematic.md).
final class CinemaTests: XCTestCase {
    func testStyleFromArgs() {
        XCTAssertEqual(CinemaStyle.from([]), .off)
        XCTAssertEqual(CinemaStyle.from(["app", "-t2p-cinema", "director"]), .director)
        XCTAssertEqual(CinemaStyle.from(["app", "-t2p-cinema", "nonsense"]), .off)
        XCTAssertEqual(CinemaStyle.from(["app", "-t2p-cinema"]), .off)
    }

    func testTraumaIsCappedAndFalls() {
        var t = Trauma(decayPerSecond: 1)
        t.add(0.8); t.add(0.8)
        XCTAssertEqual(t.value, 1, "two knocks never stack past the cap")
        XCTAssertEqual(t.shake, 1)
        t.step(0.5)
        XCTAssertEqual(t.value, 0.5, accuracy: 1e-9)
        XCTAssertEqual(t.shake, 0.25, accuracy: 1e-9, "the shake is trauma squared")
        t.step(5)
        XCTAssertEqual(t.value, 0)
    }

    func testNoiseIsSmoothBoundedAndRepeatable() {
        var prev = SmoothNoise.at(0, seed: 3)
        var big = 0.0
        for i in 1...4000 {
            let t = Double(i) * 0.005
            let v = SmoothNoise.at(t, seed: 3)
            XCTAssertLessThanOrEqual(abs(v), 1)
            // smooth: a step of 0.005 lattice units never jumps far (random jitter would)
            XCTAssertLessThan(abs(v - prev), 0.05, "at t=\(t)")
            prev = v
            big = max(big, abs(v))
        }
        XCTAssertGreaterThan(big, 0.4, "the noise actually moves")
        XCTAssertEqual(SmoothNoise.at(7.25, seed: 9), SmoothNoise.at(7.25, seed: 9))
        XCTAssertNotEqual(SmoothNoise.at(7.25, seed: 9), SmoothNoise.at(7.25, seed: 10))
        XCTAssertEqual(SmoothNoise.at(4, seed: 1), 0, accuracy: 1e-12, "zero on the lattice: a shake starts from rest")
    }

    /// A full beat: held beat with the light dropping and the push starting, a hit stop on the payoff, a shake that
    /// stays small and dies away, and the camera back where it was.
    func testFullBeat() {
        var d = CameraDirector()
        let lead = d.cue(strength: 1)
        XCTAssertEqual(lead, d.tuning.anticipation, accuracy: 1e-9)
        let dt = 1.0 / 120
        var shots: [(t: Double, s: DirectorShot)] = []
        for i in 1...Int(4 / dt) { shots.append((Double(i) * dt, d.step(dt))) }
        func at(_ t: Double) -> DirectorShot { shots.min { abs($0.t - t) < abs($1.t - t) }!.s }

        // the held beat: light dropping, push starting, no shake yet, the scene still moving
        let mid = at(lead / 2)
        XCTAssertGreaterThan(mid.dim, 0.3); XCTAssertLessThan(mid.dim, 0.7)
        XCTAssertGreaterThan(mid.push, 0.1); XCTAssertLessThan(mid.push, 0.7)
        XCTAssertEqual(mid.roll, 0); XCTAssertEqual(mid.timeScale, 1)
        XCTAssertEqual(at(lead - 0.01).dim, 1, accuracy: 0.02)

        // the hit stop: 50 to 120 ms of held frames right at the payoff
        let held = shots.filter { $0.s.timeScale == 0 }
        XCTAssertFalse(held.isEmpty)
        let span = (held.last!.t - held.first!.t) + dt
        XCTAssertGreaterThanOrEqual(span, 0.05 - 1e-6); XCTAssertLessThanOrEqual(span, 0.12 + 1e-6)
        XCTAssertEqual(held.first!.t, lead, accuracy: dt * 1.5)

        // the shake: mostly turning, small enough to read the table (under 2.1 degrees of roll), dead in a second
        let shaking = shots.filter { $0.t > lead && $0.t < lead + 1 }
        let maxRoll = shaking.map { abs($0.s.roll) }.max()!, maxYaw = shaking.map { abs($0.s.yaw) }.max()!
        XCTAssertGreaterThan(maxRoll, 0.002, "it shakes")
        XCTAssertLessThan(maxRoll, 2.1 * .pi / 180)
        XCTAssertLessThan(maxYaw, 1.4 * .pi / 180)
        XCTAssertLessThan(d.tuning.maxYaw, d.tuning.maxRoll, "mostly roll: the picture turns rather than swings")
        XCTAssertLessThan(d.tuning.maxPitch, d.tuning.maxYaw)
        XCTAssertEqual(at(lead + 0.9).roll, 0, "the trauma is gone")

        // the push holds after the payoff, then eases all the way out; the light is back
        XCTAssertEqual(at(lead + d.tuning.hold - 0.01).push, 1, accuracy: 0.03)
        XCTAssertEqual(at(3.5), .calm)
        XCTAssertTrue(d.beats.isEmpty, "finished beats are dropped")
    }

    /// Nothing moves jumps: the push and the light change smoothly frame to frame (no cut on a phone).
    func testNoJumps() {
        var d = CameraDirector()
        d.cue(strength: 1)
        var prev = DirectorShot.calm
        for _ in 0..<480 {
            let s = d.step(1.0 / 120)
            XCTAssertLessThan(abs(s.push - prev.push), 0.05)
            XCTAssertLessThan(abs(s.dim - prev.dim), 0.1)
            prev = s
        }
    }

    /// The storm's own strike: a little rumble, no held beat, no hit stop, no drop in the light.
    func testQuietBeat() {
        var d = CameraDirector()
        XCTAssertEqual(d.cue(strength: 0.4), 0)
        var stopped = false, dim = 0.0, push = 0.0, roll = 0.0
        for _ in 0..<240 {
            let s = d.step(1.0 / 120)
            stopped = stopped || s.timeScale == 0; dim = max(dim, s.dim); push = max(push, s.push); roll = max(roll, abs(s.roll))
        }
        XCTAssertFalse(stopped); XCTAssertEqual(dim, 0)
        XCTAssertLessThan(push, 0.25)
        XCTAssertGreaterThan(roll, 0); XCTAssertLessThan(roll, 0.004)
    }

    /// The dice: the scene says when the payoff lands (the first hit on the felt).
    func testGivenLead() {
        var d = CameraDirector()
        XCTAssertEqual(d.cue(strength: 0.7, lead: 0.55), 0.55)
        var firstStop: Double?
        for i in 1...200 {
            if d.step(0.01).timeScale == 0, firstStop == nil { firstStop = Double(i) * 0.01 }
        }
        XCTAssertEqual(firstStop ?? -1, 0.55, accuracy: 0.011)
    }

    func testReduceMotionIsCalm() {
        var d = CameraDirector()
        d.reduced = true
        XCTAssertEqual(d.cue(strength: 1), 0)
        for _ in 0..<300 { XCTAssertEqual(d.step(1.0 / 60), .calm) }
        // turned on mid-beat: calm at once
        var e = CameraDirector()
        e.cue(strength: 1)
        for _ in 0..<45 { _ = e.step(1.0 / 60) }
        e.reduced = true
        XCTAssertEqual(e.step(1.0 / 60), .calm)
    }

    /// Two moments at once: the push and trauma never go past their caps.
    func testOverlapIsCapped() {
        var d = CameraDirector()
        d.cue(strength: 1); d.cue(strength: 1, lead: 0.34)
        var maxPush = 0.0
        for _ in 0..<400 { let s = d.step(1.0 / 120); maxPush = max(maxPush, s.push); XCTAssertLessThanOrEqual(d.trauma.value, 1) }
        XCTAssertLessThanOrEqual(maxPush, 1 + 1e-9)
    }
}

/// #717: option B's staged strike.
final class StormStrikeTests: XCTestCase {
    func testStaging() {
        // darkening first: no leader, no flash
        let early = StormStrike.at(0.05)
        XCTAssertEqual(early.flash, 0); XCTAssertEqual(early.reveal, 0); XCTAssertGreaterThan(early.dark, 0.3)
        // the leader steps down the channel, dim, still no flash
        let reveals = stride(from: StormStrike.leaderAt, to: StormStrike.strokeAt, by: 0.005).map { StormStrike.at($0).reveal }
        XCTAssertEqual(Set(reveals).count, 5, "five steps")
        XCTAssertEqual(reveals, reveals.sorted(), "it only goes down")
        XCTAssertTrue(stride(from: 0, to: StormStrike.strokeAt, by: 0.01).allSatisfy { StormStrike.at($0).flash == 0 && StormStrike.at($0).bolt < 0.5 })
        // the return stroke: the whole channel, HDR bright, the flash at its height
        let stroke = StormStrike.at(StormStrike.strokeAt)
        XCTAssertEqual(stroke.reveal, 1); XCTAssertGreaterThan(stroke.bolt, 2); XCTAssertEqual(stroke.flash, 1, accuracy: 1e-9)
        // the afterglow is long: still a third bright half a second on, gone at the end, and it never jumps back up
        XCTAssertGreaterThan(StormStrike.at(StormStrike.strokeAt + 0.45).flash, 0.3)
        XCTAssertEqual(StormStrike.at(StormStrike.duration), StormStrike.Frame())
        var prev = 2.0
        for t in stride(from: StormStrike.strokeAt, to: StormStrike.duration, by: 0.01) {
            let f = StormStrike.at(t).flash
            XCTAssertLessThanOrEqual(f, prev + 1e-9, "at \(t)"); prev = f
        }
    }

    func testRestrikeFollowsTheSameChannel() {
        let r = 0.24
        let before = StormStrike.at(StormStrike.strokeAt + r - 0.01), after = StormStrike.at(StormStrike.strokeAt + r + 0.005)
        XCTAssertGreaterThan(after.bolt, before.bolt + 1)
        XCTAssertGreaterThan(after.flash, before.flash)
        XCTAssertEqual(after.reveal, 1)
    }

    func testFlashCountKnowsThree() {
        // three 80 ms full-screen flashes in a second is three; one long swell is one
        let fps = 60.0
        let three = (0..<120).map { i -> Double in let t = Double(i) / fps; return [0.2, 0.5, 0.8].contains { t >= $0 && t < $0 + 0.08 } ? 0.9 : 0.05 }
        XCTAssertEqual(FlashCount.mostInASecond(three, fps: fps), 3)
        let one = (0..<120).map { i -> Double in let t = Double(i) / fps; return 0.05 + 0.8 * exp(-t * 3) }
        XCTAssertLessThanOrEqual(FlashCount.mostInASecond(one, fps: fps), 1)
    }

    /// The worst case, modelled: the flash drives the whole screen from black to white (far brighter than the table
    /// really gets), every strike has a restrike, and strikes come as close as they're allowed. Never over two.
    func testNeverMoreThanTwoFlashesASecond() {
        let fps = 120.0
        for restrike in [0.12, 0.2, 0.3, 0.5, 0.8] {
            var series: [Double] = []
            for i in 0..<Int(fps * 10) {
                let t = Double(i) / fps
                let s = t.truncatingRemainder(dividingBy: StormStrike.minGap)
                let f = StormStrike.at(s, restrike: restrike)
                series.append(min(1, 0.02 + 0.9 * f.flash))
            }
            XCTAssertLessThanOrEqual(FlashCount.mostInASecond(series, fps: fps), 2, "restrike \(restrike)")
        }
    }
}
