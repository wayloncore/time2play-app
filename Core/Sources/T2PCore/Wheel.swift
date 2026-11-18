import Foundation

/// The Wheel of Names (#535): the website's Library tool, played in the app. Pure math, no UI: which names are on the
/// wheel, how a spin turns it, and which name the pointer lands on. The 3D wheel and the flat one both draw from it,
/// so they always agree on the winner.
///
/// Angles are in radians, measured clockwise from the top (where the pointer is). At rotation 0, slice i runs from
/// i × slice to (i + 1) × slice. The wheel turns clockwise as rotation grows.
public struct Wheel: Equatable, Sendable {
    public static let maxNames = 60
    public static let nameMax = 24
    public static let example = ["Avery", "Blake", "Casey", "Devon", "Emery", "Finley", "Harper", "Jordan"]

    public var names: [String]
    public init(names: [String]) { self.names = names }

    /// One name a line, trimmed, blank lines dropped, each at most 24 characters, at most 60 names.
    public static func parse(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { String($0.trimmingCharacters(in: .whitespaces).prefix(nameMax)) }
            .filter { !$0.isEmpty }
            .prefix(maxNames).map { $0 }
    }

    public var slice: Double { names.isEmpty ? 2 * .pi : 2 * .pi / Double(names.count) }

    /// The name under the pointer at a rotation.
    public func index(at rotation: Double) -> Int? {
        guard !names.isEmpty else { return nil }
        let a = Wheel.wrap(-rotation)
        return min(names.count - 1, Int(a / slice))
    }

    /// The middle of slice i, clockwise from the top at rotation 0.
    public func center(of i: Int) -> Double { (Double(i) + 0.5) * slice }

    public static func wrap(_ a: Double) -> Double {
        let t = a.truncatingRemainder(dividingBy: 2 * .pi)
        return t < 0 ? t + 2 * .pi : t
    }

    /// A spin, worked out before it plays: from a rotation, turning a whole number of times and a bit more, easing
    /// out to a stop. `pick` lands it inside slice `pick` (never on a line between two), chosen by the caller's random.
    public struct Spin: Equatable, Sendable {
        public var from: Double
        public var to: Double
        public var duration: Double
        public var winner: Int

        /// The rotation t seconds in: a cubic ease-out, fast at first and settling slowly onto the pointer.
        public func rotation(at t: Double) -> Double {
            guard duration > 0 else { return to }
            let x = min(1, max(0, t / duration))
            let e = 1 - pow(1 - x, 3)
            return from + (to - from) * e
        }
        /// How fast it turns at t (radians a second), for the pointer's flick and the clicks.
        public func speed(at t: Double) -> Double {
            guard duration > 0 else { return 0 }
            let x = min(1, max(0, t / duration))
            return (to - from) * 3 * pow(1 - x, 2) / duration
        }
    }

    /// Plans a spin. turns: whole turns before it settles (4 to 7 looks like a good spin); within: where in the slice it
    /// stops, 0 to 1 (kept 0.15 to 0.85 so it never sits on a line); reduced: Reduce Motion, a short turn.
    public func spin(from rotation: Double, pick: Int, turns: Int, within: Double, reduced: Bool = false) -> Spin? {
        guard !names.isEmpty else { return nil }
        let i = max(0, min(names.count - 1, pick))
        let w = 0.15 + 0.7 * min(1, max(0, within))
        // the slice's spot that has to come round to the top: rotation ≡ -(i + w) × slice
        let target = Wheel.wrap(-(Double(i) + w) * slice)
        let now = Wheel.wrap(rotation)
        var extra = target - now
        if extra < 0 { extra += 2 * .pi }
        let whole = reduced ? 0 : max(1, turns)
        let to = rotation + extra + Double(whole) * 2 * .pi
        let duration = reduced ? 0.6 : 4.2 + 0.25 * Double(whole)
        return Spin(from: rotation, to: to, duration: duration, winner: i)
    }

    /// The pegs on the rim: one at every slice line, at least 12 so a short list still clicks.
    public var pegs: Int { max(12, names.count) }

    /// The slice colors (the site's palette, gold first), repeating; the last never matches the first.
    public static let palette: [UInt32] = [0xE9B45A, 0x2E7FD4, 0xE2662A, 0x4A9E4E, 0x8B5FD6, 0xD9476B, 0x2BA6A4, 0xC98A2E]
    public func color(_ i: Int) -> UInt32 {
        let n = names.count, p = Wheel.palette.count
        var c = i % p
        if n > 1, i == n - 1, c == 0 { c = (n - 2) % p == 1 ? 2 : 1 }
        return Wheel.palette[c]
    }
}
