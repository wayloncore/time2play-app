import XCTest
@testable import T2PCore

/// The 3D table's seats and camera (#496): every player count on every screen keeps seats apart, inside the screen,
/// under the header, and the discard pile clear of your hand.
final class Table3DLayoutTests: XCTestCase {
    /// Screens (points) and the free band the 3D view leaves the table (header ~ 96 high, the hand panel ~ 300).
    let screens: [(String, Double, Double, Double, Double)] = [
        ("SE", 375, 667, 92, 667 - 268), ("12", 390, 844, 110, 844 - 318), ("Pro Max", 430, 932, 110, 932 - 330),
        ("iPad", 820, 1180, 96, 1180 - 380), ("iPad Pro", 1024, 1366, 96, 1366 - 400),
    ]

    func testRimIsClosedAndStartsAtYourEnd() {
        let a = Table3D.rimPoint(0), b = Table3D.rimPoint(Table3D.perim)
        XCTAssertEqual(a.x, b.x, accuracy: 1e-9); XCTAssertEqual(a.z, b.z, accuracy: 1e-9)
        XCTAssertEqual(a.z, Table3D.rz, accuracy: 1e-9)
        XCTAssertEqual(Table3D.rimPoint(Table3D.perim / 2).z, -Table3D.rz, accuracy: 1e-9)
    }

    func testEveryCountFitsEveryScreen() {
        for (name, w, h, top, bottom) in screens {
            for n in 2...10 {
                let free = T3Rect(x0: 6, y0: top, x1: w - 6, y1: bottom)
                let l = Table3DLayout.make(players: n, width: w, height: h, free: free)
                XCTAssertEqual(l.seats.count, n - 1)
                let cam = l.camera
                // seats in true turn order round the rim, and their faces never overlap
                for i in l.seats.indices.dropFirst() { XCTAssertGreaterThan(l.seats[i].s, l.seats[i - 1].s) }
                let faces = l.seats.map { Table3DLayout.faceRect($0, cam) }
                if n > 2 { XCTAssertGreaterThan(l.faceGap, 1, "\(name) n=\(n): two faces overlap") }
                // inside the screen, under the header
                for f in faces {
                    XCTAssertGreaterThan(f.x0, -2, "\(name) n=\(n)"); XCTAssertLessThan(f.x1, w + 2, "\(name) n=\(n)")
                    XCTAssertGreaterThan(f.y0, top - 2, "\(name) n=\(n)")
                }
                // the discard pile's near edge clear of your hand
                let near = cam.project(T3Vec(0, 0, Table3D.pileAt.z + Table3D.cardH / 2))
                XCTAssertLessThan(near.y, bottom, "\(name) n=\(n): the pile reaches your hand")
                // aerial (#496, Nov 17): a strip of scene between the header and the far seats, no more than a strip,
                // and the camera looks down on the pile, so its card reads (not a sliver seen edge-on)
                let tops = l.seats.flatMap { Table3DLayout.corners($0, cam) }.map { $0.y }.min() ?? top
                XCTAssertGreaterThanOrEqual(tops, l.stripBottom - 0.5, "\(name) n=\(n): a seat reaches into the strip")
                XCTAssertGreaterThanOrEqual(l.stripBottom - top, 50, "\(name) n=\(n)")
                XCTAssertGreaterThanOrEqual(l.pitch, 30, "\(name) n=\(n)")
                let pile = [-1.0, 1.0].map { cam.project(T3Vec(0, 0, Table3D.pileAt.z + $0 * Table3D.cardH / 2)).y }
                let pw = cam.project(T3Vec(Table3D.cardW / 2, 0, Table3D.pileAt.z)).x - cam.project(T3Vec(-Table3D.cardW / 2, 0, Table3D.pileAt.z)).x
                XCTAssertGreaterThan((pile[1] - pile[0]) / pw, 0.6, "\(name) n=\(n): the pile is seen too edge-on")
                XCTAssertGreaterThan(pw, 55, "\(name) n=\(n): the pile's card is too small to read")
            }
        }
    }

    func testFromScreenLandsWhereItProjects() {
        let l = Table3DLayout.make(players: 5, width: 390, height: 844, free: T3Rect(x0: 6, y0: 110, x1: 384, y1: 526))
        let p = l.camera.fromScreen(x: 120, y: 700, cardPoints: 90)
        let s = l.camera.project(p)
        XCTAssertEqual(s.x, 120, accuracy: 0.01); XCTAssertEqual(s.y, 700, accuracy: 0.01)
        XCTAssertEqual(l.camera.pointsPerUnit(at: p) * Table3D.cardW, 90, accuracy: 0.01)
    }

    func testGroundIsUnderTheScreenPoint() {
        let l = Table3DLayout.make(players: 5, width: 390, height: 844, free: T3Rect(x0: 6, y0: 110, x1: 384, y1: 526))
        guard let g = l.camera.ground(x: 60, y: 150, level: -2.6) else { return XCTFail("the top of the table's screen shows ground") }
        XCTAssertEqual(g.y, -2.6, accuracy: 1e-9)
        let s = l.camera.project(g)
        XCTAssertEqual(s.x, 60, accuracy: 0.01); XCTAssertEqual(s.y, 150, accuracy: 0.01)
        XCTAssertLessThan(g.z, -Table3D.rz, "the strip at the top shows the scene past the far end")
    }

    func testPileLieIsStable() {
        XCTAssertEqual(Table3D.pileLie(7).yaw, Table3D.pileLie(7).yaw)
        XCTAssertLessThanOrEqual(abs(Table3D.pileLie(3).yaw), 0.2)
    }
}
