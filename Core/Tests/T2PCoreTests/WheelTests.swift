import XCTest
@testable import T2PCore

/// The Wheel of Names (#535): a spin always stops inside the slice it planned, on every list size, from any start,
/// so the 3D wheel and the flat one name the same winner the pointer is on.
final class WheelTests: XCTestCase {
    func testParseKeepsOneNameALine() {
        XCTAssertEqual(Wheel.parse("  Ana \n\nBo\r\n  \nCy"), ["Ana", "Bo", "Cy"])
        XCTAssertEqual(Wheel.parse(String(repeating: "x", count: 40)).first?.count, Wheel.nameMax)
        XCTAssertEqual(Wheel.parse((1...90).map { "N\($0)" }.joined(separator: "\n")).count, Wheel.maxNames)
    }

    func testSpinLandsOnItsPick() {
        for n in [1, 2, 3, 7, 12, 60] {
            let w = Wheel(names: (0..<n).map { "N\($0)" })
            for start in [0.0, 1.3, -4.0, 100.5] {
                for pick in [0, n / 2, n - 1] {
                    for within in [0.0, 0.5, 1.0] {
                        let s = try! XCTUnwrap(w.spin(from: start, pick: pick, turns: 5, within: within))
                        XCTAssertEqual(w.index(at: s.to), pick, "n \(n) start \(start) pick \(pick)")
                        XCTAssertGreaterThan(s.to, start + 5 * 2 * .pi - 1e-9, "it turns at least five times")
                        XCTAssertEqual(s.rotation(at: 0), start, accuracy: 1e-9)
                        XCTAssertEqual(s.rotation(at: s.duration), s.to, accuracy: 1e-9)
                        XCTAssertEqual(s.speed(at: s.duration), 0, accuracy: 1e-9)
                    }
                }
            }
        }
    }

    func testReducedMotionIsShortAndStillRight() {
        let w = Wheel(names: Wheel.example)
        let s = try! XCTUnwrap(w.spin(from: 2, pick: 3, turns: 6, within: 0.5, reduced: true))
        XCTAssertLessThan(s.to - s.from, 2 * .pi + 1e-9)
        XCTAssertLessThan(s.duration, 1)
        XCTAssertEqual(w.index(at: s.to), 3)
    }

    func testIndexAtRotation() {
        let w = Wheel(names: ["A", "B", "C", "D"])
        XCTAssertEqual(w.index(at: 0.01), 3, "turned a little clockwise, the last slice comes under the pointer")
        XCTAssertEqual(w.index(at: -0.01), 0)
        XCTAssertNil(Wheel(names: []).index(at: 0))
    }

    func testNeighborsNeverShareAColor() {
        for n in 2...40 {
            let w = Wheel(names: (0..<n).map { "N\($0)" })
            for i in 0..<n { XCTAssertNotEqual(w.color(i), w.color((i + 1) % n), "n \(n) slice \(i)") }
        }
    }
}
