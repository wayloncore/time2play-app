import Foundation

/// How a card moves at the 3D Overdraft table (build 45, Tyler Nov 18: "the card acts very stiff when moving"), as
/// plain math so it's tested without the scene. A card in flight has three parts:
/// 1. **Pickup**: it lifts a little and tips back, slowing to a stop (a hand picking it up).
/// 2. **Flight**: it leaves gently, speeds up and comes down onto the pile along a curve, its height a parabola in
///    time (like anything thrown), turning flat and spinning less as it goes. It touches down still moving.
/// 3. **Settle**: it slides the last bit on the pile like a spring: just past its spot and back, with a tiny rock
///    and turn that die away. A card going into a hand has no slide: it eases to a stop.
/// The website's flight (src/games/overdraft3d/table.js, fly and stepFlights) is the same length but eases out from
/// full speed, lands on a straight line and bounces; this keeps its timing and makes it physical.
public enum CardMotion {
    /// The pickup's length (seconds) and how far up it lifts a card (world units; a card is 1.26 wide).
    public static let pickupSeconds = 0.09
    public static let pickupLift = 0.22
    /// How far it tips back as it's picked up (radians, about 12°), and turns (about 4°).
    public static let pickupTilt = 0.21, pickupTurn = 0.07
    /// The settle's spring: damping (under 1 overshoots a little) and stiffness, and how long it runs (seconds).
    public static let settleDamping = 0.6, settleStiffness = 14.0, settleSeconds = 0.42
    /// How fast a card is still sliding when it touches the pile, as a share of slide × stiffness.
    static let landingPace = 0.55
    /// The flight's start: gentler than full speed (1 would be a straight line in time).
    public static let leave = 0.7

    /// The pickup's curve: 0 to 1, slowing to a stop (ease-out cubic).
    public static func pickup(_ u: Double) -> Double {
        let c = min(1, max(0, u))
        return 1 - pow(1 - c, 3)
    }

    /// The flight's progress (0 to 1) at `u` (0 to 1 of the flight's time): leaves at speed `a`, arrives at speed `b`
    /// (both in progress per flight). A cubic Hermite curve.
    public static func travel(_ u: Double, leave a: Double = leave, arrive b: Double) -> Double {
        let t = min(1, max(0, u)), t2 = t * t, t3 = t2 * t
        return (t3 - 2 * t2 + t) * a + (-2 * t3 + 3 * t2) + (t3 - t2) * b
    }

    /// How fast a card touches the pile (world units a second) for a slide of `slide` units.
    public static func landingSpeed(slide: Double) -> Double { slide * settleStiffness * landingPace }

    /// The arrival speed for `travel` (progress per flight) for a flight `distance` long that lasts `seconds` and
    /// touches down at `speed`.
    public static func arrive(speed: Double, distance: Double, seconds: Double) -> Double {
        distance > 1e-6 ? min(1.5, speed * seconds / distance) : 0
    }

    /// The settle: how far the card is from its spot `t` seconds after it touches down, having touched down `slide`
    /// units short of it moving toward it at `speed` (negative: short of the spot, positive: just past it).
    public static func settle(_ t: Double, slide: Double, speed: Double) -> Double {
        guard slide > 0 else { return 0 }
        let z = settleDamping, w = settleStiffness, wd = w * (1 - z * z).squareRoot()
        let c1 = -slide, c2 = (speed + z * w * c1) / wd
        let tt = max(0, t)
        return exp(-z * w * tt) * (c1 * cos(wd * tt) + c2 * sin(wd * tt))
    }

    /// The settle as a share of the slide still to go: 1 as it touches down, about 0 once settled, a little below 0
    /// while it's just past its spot. The card's rock and turn on landing die away with it.
    public static func settleShare(_ t: Double, slide: Double, speed: Double) -> Double {
        slide > 0 ? settle(t, slide: slide, speed: speed) / -slide : 0
    }

    /// A curve's height over the straight line between start and end, `u` of the way through the flight's time: a
    /// parabola that peaks at `arc` halfway.
    public static func arc(_ u: Double, _ arc: Double) -> Double {
        let t = min(1, max(0, u))
        return arc * 4 * t * (1 - t)
    }
}
