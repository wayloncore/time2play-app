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
                // the horizon shows a band of sky under the header
                XCTAssertGreaterThan(l.horizonY, top + 20, "\(name) n=\(n)")
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

    func testPileLieIsStable() {
        XCTAssertEqual(Table3D.pileLie(7).yaw, Table3D.pileLie(7).yaw)
        XCTAssertLessThanOrEqual(abs(Table3D.pileLie(3).yaw), 0.2)
    }
}
