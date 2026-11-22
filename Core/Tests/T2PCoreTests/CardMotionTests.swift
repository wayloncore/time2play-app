import XCTest
@testable import T2PCore

/// Build 45 (Tyler, Nov 18: "the card acts very stiff when moving"): a card's flight at the 3D table picks up, leaves
/// gently, touches down still moving, and settles like a spring with a tiny overshoot.
final class CardMotionTests: XCTestCase {
    func testThePickupLiftsAndStops() {
        XCTAssertEqual(CardMotion.pickup(0), 0)
        XCTAssertEqual(CardMotion.pickup(1), 1)
        XCTAssertGreaterThan(CardMotion.pickup(0.3), 0.5, "most of the lift comes early")
        XCTAssertLessThan(CardMotion.pickup(1) - CardMotion.pickup(0.97), 0.001, "it slows to a stop")
    }

    func testTheFlightLeavesGentlyAndNeverGoesBack() {
        for b in [0.0, 0.1, 0.3, 1.0, 1.5] {
            var last = -1.0
            for i in 0...200 {
                let s = CardMotion.travel(Double(i) / 200, arrive: b)
                XCTAssertGreaterThanOrEqual(s, last - 1e-12, "arrive \(b): only forward")
                XCTAssertLessThanOrEqual(s, 1 + 1e-9, "arrive \(b): never past the touchdown before it")
                last = s
            }
            XCTAssertEqual(CardMotion.travel(0, arrive: b), 0)
            XCTAssertEqual(CardMotion.travel(1, arrive: b), 1, accuracy: 1e-12)
        }
        // a gentle start: slower than a straight line in time at first
        XCTAssertLessThan(CardMotion.travel(0.05, arrive: 0.15), 0.05)
        XCTAssertEqual(CardMotion.arc(0.5, 0.9), 0.9, accuracy: 1e-12, "the curve peaks halfway")
        XCTAssertEqual(CardMotion.arc(1, 0.9), 0, "and comes down onto the pile")
    }

    func testTheSettleOvershootsALittleAndStops() {
        for slide in [0.16, 0.2] {
            let speed = CardMotion.landingSpeed(slide: slide)
            XCTAssertEqual(CardMotion.settle(0, slide: slide, speed: speed), -slide, accuracy: 1e-12, "touches down short of its spot")
            // the flight's speed carries straight into the slide: no stop at touchdown
            let dt = 1e-5
            let v = (CardMotion.settle(dt, slide: slide, speed: speed) - CardMotion.settle(0, slide: slide, speed: speed)) / dt
            XCTAssertEqual(v, speed, accuracy: speed * 0.01)
            var past = 0.0
            for i in 0...420 { past = max(past, CardMotion.settle(Double(i) / 1000, slide: slide, speed: speed)) }
            XCTAssertGreaterThan(past, 0.005, "slide \(slide): it goes just past its spot")
            XCTAssertLessThan(past, 0.04, "slide \(slide): only a little (a card is 1.26 wide)")
            XCTAssertLessThan(abs(CardMotion.settle(CardMotion.settleSeconds, slide: slide, speed: speed)), 0.002, "and has settled")
        }
        XCTAssertEqual(CardMotion.settleShare(0.2, slide: 0, speed: 0), 0, "no slide, no settle")
    }

    func testTheTouchdownSpeedMatches() {
        // a seat's throw: about 5 units in 0.62 s, sliding 0.16 on the pile
        let speed = CardMotion.landingSpeed(slide: 0.16)
        let b = CardMotion.arrive(speed: speed, distance: 5, seconds: 0.62)
        let du = 1e-5
        let v = (CardMotion.travel(1, arrive: b) - CardMotion.travel(1 - du, arrive: b)) / du * 5 / 0.62
        XCTAssertEqual(v, speed, accuracy: speed * 0.01, "the flight touches down at the speed the slide starts with")
        XCTAssertEqual(CardMotion.arrive(speed: 1, distance: 0, seconds: 1), 0)
    }
    /// #722: a card rocking as it lands is held above the pile by its lowest corner, so it never cuts into the card
    /// under it. Flat, it sits half its thickness above its center; tipped, its edge drops by the tip.
    func testATippedCardIsHeldAboveThePile() {
        let w = Table3D.cardW, h = Table3D.cardH, t = Table3D.cardT
        XCTAssertEqual(CardMotion.dip(upX: 0, upY: 1, upZ: 0, width: w, length: h, thickness: t), t / 2, accuracy: 1e-9)
        // rocked 0.05 rad about the card's width: its far ends drop by sin(0.05) × half its length
        let a = 0.05
        let d = CardMotion.dip(upX: 0, upY: cos(a), upZ: sin(a), width: w, length: h, thickness: t)
        XCTAssertEqual(d, sin(a) * h / 2 + cos(a) * t / 2, accuracy: 1e-9)
        XCTAssertGreaterThan(d - t / 2, t * 3, "the old way (center on the pile) dipped several card thicknesses into it")
        // either way it tips, the same
        XCTAssertEqual(CardMotion.dip(upX: 0, upY: cos(a), upZ: -sin(a), width: w, length: h, thickness: t), d, accuracy: 1e-12)
        XCTAssertGreaterThan(CardMotion.pileClearance, 0)
        XCTAssertLessThan(CardMotion.pileClearance, t, "the gap is less than a card's thickness, so it can't be seen")
    }
}
