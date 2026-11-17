import XCTest
@testable import T2PCore

/// The 3D dice arena (#521): throws settle flat, apart and inside the tray, quickly; every throw can land on whatever
/// the room rolled; the camera keeps the tray in view; and each moment of a game puts every die in the right place.
final class DiceArenaTests: XCTestCase {
    func testTheCubeHasTwentyFourTurns() {
        XCTAssertEqual(DiceArena.symmetries.count, 24)
        for s in DiceArena.symmetries {
            for a in DiceArena.axes {   // each takes an axis onto an axis
                let b = s.rotate(a)
                XCTAssertTrue(DiceArena.axes.contains { ($0 - b).length < 1e-9 }, "\(a) -> \(b)")
            }
        }
    }

    func testOppositeFacesAddToSeven() {
        for f in 1...6 {
            let a = DiceArena.axis(of: f), b = DiceArena.axis(of: 7 - f)
            XCTAssertLessThan((a + b).length, 1e-9, "\(f) is opposite \(7 - f)")
            XCTAssertEqual(DiceArena.upFace(DiceArena.neat(f)), f)
        }
    }

    func testAFixShowsAnyFace() {
        for landed in 1...6 {
            for want in 1...6 {
                for pick in 0..<4 {
                    let q = DiceArena.neat(landed) * DQuat.axisAngle(T3Vec(0, 1, 0), 0.7)
                    XCTAssertEqual(DiceArena.upFace(DiceArena.neat(landed)), landed)
                    let fix = DiceArena.fix(landedUp: DiceArena.upFace(q), want: want, pick: pick)
                    XCTAssertEqual(DiceArena.upFace(q * fix), want, "landed \(landed), want \(want)")
                }
            }
        }
    }

    func testThrowsSettleFlatApartAndInside() {
        var longest = 0.0, total = 0.0, runs = 0
        for seed in 1...36 {
            let n = 1 + seed % 6
            let th = DiceSim.run(count: n, seed: UInt32(seed) &* 7919)
            XCTAssertEqual(th.count, n)
            longest = max(longest, th.duration); total += th.duration; runs += 1
            XCTAssertLessThan(th.duration, 3.4, "seed \(seed): the dice come to rest")
            for f in th.frames {
                for d in f where d.out {
                    XCTAssertLessThanOrEqual(abs(d.p.x), DiceArena.trayX, "seed \(seed): inside the side walls")
                    XCTAssertGreaterThanOrEqual(d.p.z, DiceArena.zBack, "seed \(seed): inside the back wall")
                    XCTAssertLessThanOrEqual(d.p.z, DiceArena.zFront, "seed \(seed): behind the keep shelf")
                    XCTAssertGreaterThan(d.p.y, 0.2, "seed \(seed): above the felt")
                }
            }
            let rest = th.rest
            for (i, d) in rest.enumerated() {
                XCTAssertEqual(d.p.y, DiceArena.half, accuracy: 1e-6, "seed \(seed) die \(i) rests on the felt")
                XCTAssertGreaterThan(d.q.rotate(DiceArena.axes[DiceArena.upAxis(d.q)]).y, 0.9999, "seed \(seed) die \(i) lies flat")
                XCTAssertLessThanOrEqual(th.firstHit[i], th.settledAt[i] + 1e-9)
                for j in rest.indices where j > i {
                    let o = DiceSim.overlap(d.p, d.q, rest[j].p, rest[j].q)
                    XCTAssertLessThan(o?.pen ?? 0, 0.045, "seed \(seed): dice \(i) and \(j) rest apart")
                }
            }
            // whatever the room rolled, the fixed throw lands on it
            let faces = (0..<n).map { 1 + (seed * 5 + $0 * 3) % 6 }
            let fixes = th.fixes(for: faces)
            for i in 0..<n { XCTAssertEqual(DiceArena.upFace(rest[i].q * fixes[i]), faces[i], "seed \(seed) die \(i)") }
        }
        XCTAssertLessThan(total / Double(runs), 1.8, "a throw takes about a second and a half on average")
        print("dice throws: average \(total / Double(runs)) s, longest \(longest) s")
    }

    func testTheSameSeedThrowsTheSame() {
        XCTAssertEqual(DiceSim.run(count: 6, seed: 42), DiceSim.run(count: 6, seed: 42))
    }

    func testTheCameraKeepsTheTrayInView() {
        for (w, h) in [(375.0, 300.0), (390.0, 420.0), (430.0, 520.0), (820.0, 560.0), (1024.0, 700.0), (390.0, 260.0)] {
            let cam = DiceArena.camera(width: w, height: h)
            var spots = (0..<6).map { DiceArena.keepSpot($0, of: 6) }
            spots += [T3Vec(-DiceArena.trayX, 0, DiceArena.zBack), T3Vec(DiceArena.trayX, 0, DiceArena.zBack),
                      T3Vec(-DiceArena.trayX, 0, DiceArena.zFront), T3Vec(DiceArena.trayX, 0, DiceArena.zFront)]
            for p in spots {
                let s = cam.project(p)
                XCTAssertTrue(s.x > 0 && s.x < w && s.y > 0 && s.y < h, "\(w)x\(h): \(p) at \(s)")
            }
            // a die on the felt is big enough to tap
            XCTAssertGreaterThan(cam.pointsPerUnit(at: T3Vec(0, 0.5, 0)), 26, "\(w)x\(h): dice are tappable")
        }
    }

    private func hot(_ turn: String) throws -> HotDice.Turn {
        let v = HotDice.View(try XCTUnwrap(JSON.parse(#"{"phase":"playing","you":{"id":"a"},"players":[],"turn":\#(turn)}"#)))
        return try XCTUnwrap(v.turn)
    }

    func testHotDicePlaces() throws {
        let dice = #"[{"id":0,"v":5},{"id":1,"v":1},{"id":2,"v":3},{"id":3,"v":3},{"id":4,"v":6},{"id":5,"v":2}]"#
        let start = ArenaState.hotDice(try hot(#"{"id":"a","n":1,"state":"start","dice":\#(dice),"kept":[],"live":[],"sel":[]}"#), scoringFaces: nil, mine: true)
        XCTAssertTrue(start.dice.allSatisfy { $0.place == .cup }, "a turn starts with the dice in the cup")
        XCTAssertNil(start.roll)

        let hidden = #"[{"id":0,"v":null},{"id":1,"v":null},{"id":2,"v":4},{"id":3,"v":null},{"id":4,"v":null},{"id":5,"v":null}]"#
        let rolling = ArenaState.hotDice(try hot(#"{"id":"a","n":1,"state":"rolling","seq":2,"dice":\#(hidden),"kept":[2],"live":[0,1,3,4,5],"sel":[]}"#), scoringFaces: nil, mine: true)
        XCTAssertTrue(rolling.shaking)
        XCTAssertEqual(rolling.die(2)?.place, .keep(slot: 0, locked: true), "set aside stays in the keep row")
        XCTAssertEqual(rolling.die(0)?.place, .cup)

        let choose = ArenaState.hotDice(try hot(#"{"id":"a","n":1,"state":"choose","seq":1,"dice":\#(dice),"kept":[],"live":[0,1,2,3,4,5],"sel":[1,0]}"#),
                                        scoringFaces: [1, 5], mine: true)
        XCTAssertEqual(choose.roll, "1.1")
        XCTAssertEqual(choose.die(0)?.place, .keep(slot: 0, locked: false), "picked dice go to the keep row in order")
        XCTAssertEqual(choose.die(1)?.place, .keep(slot: 1, locked: false))
        XCTAssertEqual(choose.die(2)?.place, .tray)
        XCTAssertEqual(choose.scoring, [], "picked dice don't glow; nothing left on the felt here scores")

        let fresh = ArenaState.hotDice(try hot(#"{"id":"a","n":1,"state":"choose","seq":1,"dice":\#(dice),"kept":[],"live":[0,1,2,3,4,5],"sel":[]}"#),
                                       scoringFaces: [1, 5], mine: true)
        XCTAssertEqual(fresh.scoring, [0, 1], "the 5 and the 1 could score")

        let farkle = ArenaState.hotDice(try hot(#"{"id":"a","n":1,"state":"farkle","seq":1,"dice":\#(dice),"kept":[],"live":[2,3,4,5],"sel":[]}"#), scoringFaces: [], mine: false)
        XCTAssertTrue(farkle.farkle)
        XCTAssertEqual(farkle.dice.filter { $0.place == .tray }.count, 4)
    }

    func testRollCallPlaces() throws {
        let v = RollCall.View(try XCTUnwrap(JSON.parse(#"{"phase":"playing","you":{"id":"a"},"yourTurn":true,"players":[],"turn":{"id":"a","dice":[2,2,5,6,1],"held":[true,false,false,true,false],"rolls":2},"last":{"n":3}}"#)))
        let s = ArenaState.rollCall(v)
        XCTAssertEqual(s.die(0)?.place, .keep(slot: 0, locked: false))
        XCTAssertEqual(s.die(3)?.place, .keep(slot: 3, locked: false))
        XCTAssertEqual(s.die(1)?.place, .tray)
        XCTAssertEqual(s.roll, "a#3#2")
        XCTAssertTrue(s.mine)
    }
}
