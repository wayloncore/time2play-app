import Foundation

/// #708: the cinematic arenas. Three options are built side by side on one branch so Tyler can compare them; a run
/// picks one with the launch argument `-t2p-cinema <style>`. Without it (and in every shipped build until Tyler picks)
/// the arenas are exactly as they were.
public enum CinemaStyle: String, CaseIterable, Sendable {
    /// The arenas as they are today.
    case off
    /// Option A (#716): the camera does the work. Anticipation, a slow push-in, a hit stop, trauma shake.
    case director
    /// Option B (#717): the world does the work (HDR, bloom, a staged strike, thunder).
    case storm
    /// Option C (#718): calm play, then a short directed sequence for the moments that matter.
    case moments

    public static func from(_ args: [String]) -> CinemaStyle {
        guard let i = args.firstIndex(of: "-t2p-cinema"), i + 1 < args.count else { return .off }
        return CinemaStyle(rawValue: args[i + 1]) ?? .off
    }
}

/// Squirrel Eiserloh's trauma (GDC 2016, "Juicing your cameras with math"): one number from 0 to 1 that events add to
/// and that falls away on its own. The shake is trauma squared, so a small knock is barely felt and a big one is,
/// and two knocks at once can't stack past the cap.
public struct Trauma: Sendable, Equatable {
    public private(set) var value = 0.0
    /// How much trauma falls away each second (linear: a full knock is gone in about three quarters of a second).
    public var decayPerSecond: Double

    public init(decayPerSecond: Double = 1.35) { self.decayPerSecond = decayPerSecond }

    public mutating func add(_ amount: Double) { value = min(1, max(0, value + amount)) }
    public mutating func step(_ dt: Double) { value = max(0, value - decayPerSecond * max(0, dt)) }
    /// How hard the camera shakes now (0 to 1).
    public var shake: Double { value * value }
}

/// Smooth noise in one dimension (Perlin's gradient noise): a wobble that moves like weight, not the jitter of a
/// random number each frame, which reads as a glitch. The same seed always gives the same wobble.
public enum SmoothNoise {
    /// The noise at `t` (one lattice step per unit of t), from -1 to 1.
    public static func at(_ t: Double, seed: UInt32) -> Double {
        let i = t.rounded(.down), f = t - i
        let n = Int(i)
        let g0 = gradient(n, seed), g1 = gradient(n + 1, seed)
        let u = f * f * f * (f * (f * 6 - 15) + 10)   // Perlin's quintic fade: no kink at the lattice points
        let v0 = g0 * f, v1 = g1 * (f - 1)
        // 1D gradient noise peaks at 0.5 for unit gradients: scale to the full range
        return max(-1, min(1, 2 * (v0 + (v1 - v0) * u)))
    }

    /// A gradient from -1 to 1 for each lattice point (a small integer hash).
    static func gradient(_ i: Int, _ seed: UInt32) -> Double {
        var h = UInt32(truncatingIfNeeded: i) &* 0x9E37_79B1 ^ seed &* 0x85EB_CA77
        h ^= h >> 15; h = h &* 0x2C1B_3C6D; h ^= h >> 12; h = h &* 0x297A_2D39; h ^= h >> 15
        return Double(h) / Double(UInt32.max) * 2 - 1
    }
}

/// What the director asks of the camera and the scene this frame.
public struct DirectorShot: Equatable, Sendable {
    /// How far the slow push-in has gone (0 is the fitted view, 1 is all the way in).
    public var push = 0.0
    /// How far the light has dropped for the held beat before a payoff (0 is normal light, 1 is the deepest drop).
    public var dim = 0.0
    /// The scene's speed: 1 normally, 0 during a hit stop (the frame holds on the strike).
    public var timeScale = 1.0
    /// The shake, as small turns of the camera (radians) and a smaller slide (a fraction of the push distance).
    public var yaw = 0.0, pitch = 0.0, roll = 0.0
    public var shiftX = 0.0, shiftY = 0.0

    public init() {}
    public static let calm = DirectorShot()
}

/// Option A, the director (#716): the camera tells the big moment.
///
/// Every beat follows the research in docs/app/cinematic.md:
/// - anticipation (Thomas and Johnston): a held beat before the payoff, the light dropping and a slow push-in starting;
/// - the payoff with a hit stop (Nijman, "The art of screenshake"): the scene holds 50 to 120 ms on the strike frame;
/// - trauma shake (Eiserloh): one trauma value, shake = trauma squared times smooth noise, mostly rotation, capped and
///   falling away;
/// - a long settle: the push holds a moment, then eases back out (slow in and slow out).
/// Reduce Motion: nothing at all. No push, no shake, no hit stop and no drop in the light (the HIG; WCAG 2.3.1).
///
/// Strength (0 to 1) says how much the moment matters: a Bolt aimed at you is 1, someone else's is about 0.6, the
/// storm's own strikes 0.4 (a little rumble, no held beat, no hit stop: cinema answers the player, Swink).
/// The director runs on real time; the scene runs on `timeScale` of it, so the hit stop can hold the scene.
public struct CameraDirector: Sendable {
    public struct Tuning: Sendable, Equatable {
        /// The held beat before a payoff, for a full-strength moment (seconds).
        public var anticipation = 0.34
        /// The push-in holds this long after the payoff, then eases out over `release`.
        public var hold = 0.5
        public var release = 1.2
        /// How long the scene holds on the payoff at full strength (seconds; 50 to 120 ms).
        public var hitStop = 0.1
        /// Below this strength a moment gets no held beat and no hit stop, only a little trauma and push.
        public var quiet = 0.5
        /// How much trauma a full-strength payoff adds.
        public var traumaAt1 = 0.8
        /// The shake at full trauma (radians): roll most, then yaw, then pitch, so the picture turns rather than slides.
        public var maxYaw = 0.022, maxPitch = 0.016, maxRoll = 0.036
        /// The slide at full trauma, as a fraction of the push-in distance.
        public var maxShift = 0.12
        /// Noise speed: lattice steps per second (a rumble, not a buzz).
        public var noiseSpeed = 11.0
        /// How fast the light comes back after the payoff (seconds), never a snap.
        public var lightBack = 0.22
        public var traumaDecay = 1.35

        public init() {}
    }

    struct Beat: Sendable, Equatable {
        var strength: Double
        var cueAt: Double
        var hitAt: Double
        var fired = false
    }

    public var tuning: Tuning
    /// Reduce Motion: every shot is calm, and new beats are dropped.
    public var reduced = false {
        didSet { if reduced { beats = []; trauma = Trauma(decayPerSecond: tuning.traumaDecay) } }
    }
    public private(set) var trauma: Trauma
    public private(set) var now = 0.0
    private(set) var beats: [Beat] = []
    private let seed: UInt32

    public init(tuning: Tuning = Tuning(), seed: UInt32 = 708) {
        self.tuning = tuning
        self.seed = seed
        trauma = Trauma(decayPerSecond: tuning.traumaDecay)
    }

    /// The held beat a moment of this strength gets before its payoff (seconds; 0 for a quiet one or Reduce Motion).
    public func lead(strength: Double) -> Double {
        reduced || strength < tuning.quiet ? 0 : tuning.anticipation * (0.7 + 0.3 * min(1, strength))
    }

    /// A moment is coming. Returns how long until its payoff, so the scene can time the strike to it. With `lead`, the
    /// scene already knows when its payoff lands (the dice reaching the felt), and the held beat is that long.
    @discardableResult
    public mutating func cue(strength: Double, lead: Double? = nil) -> Double {
        guard !reduced else { return 0 }
        let s = min(1, max(0, strength))
        let l = max(0, lead ?? self.lead(strength: s))
        beats.append(Beat(strength: s, cueAt: now, hitAt: now + l))
        return l
    }

    /// The hit stop for a moment of this strength (seconds).
    public func hitStop(strength: Double) -> Double {
        strength < tuning.quiet ? 0 : min(0.12, max(0.05, tuning.hitStop * strength))
    }

    /// The next frame, `dt` real seconds on.
    public mutating func step(_ dt: Double) -> DirectorShot {
        now += max(0, dt)
        for i in beats.indices where !beats[i].fired && now >= beats[i].hitAt {
            beats[i].fired = true
            trauma.add(tuning.traumaAt1 * beats[i].strength)
        }
        trauma.step(dt)
        let span = tuning.hold + tuning.release + tuning.lightBack
        beats.removeAll { $0.fired && now > $0.hitAt + span + 0.05 }
        return shot()
    }

    /// The shot for the director's time now.
    public func shot() -> DirectorShot {
        guard !reduced else { return .calm }
        var s = DirectorShot()
        for b in beats {
            s.push = max(s.push, pushEnvelope(b) * pushScale(b.strength))
            s.dim = max(s.dim, dimEnvelope(b) * b.strength)
            let stop = hitStop(strength: b.strength)
            if stop > 0 && now >= b.hitAt && now < b.hitAt + stop { s.timeScale = 0 }
        }
        let k = trauma.shake
        if k > 0 {
            let t = now * tuning.noiseSpeed
            s.yaw = k * tuning.maxYaw * SmoothNoise.at(t, seed: seed)
            s.pitch = k * tuning.maxPitch * SmoothNoise.at(t + 31.7, seed: seed &+ 1)
            s.roll = k * tuning.maxRoll * SmoothNoise.at(t + 63.1, seed: seed &+ 2)
            s.shiftX = k * tuning.maxShift * SmoothNoise.at(t * 0.8 + 97.3, seed: seed &+ 3)
            s.shiftY = k * tuning.maxShift * SmoothNoise.at(t * 0.8 + 129.9, seed: seed &+ 4)
        }
        return s
    }

    /// A quiet moment pushes in a little; a full one all the way.
    func pushScale(_ strength: Double) -> Double { max(0, min(1, (strength - 0.25) / 0.75)) }

    /// The push: eases in through the held beat to 70%, creeps on to 100% while it holds, then eases out.
    func pushEnvelope(_ b: Beat) -> Double {
        let lead = b.hitAt - b.cueAt
        if now < b.hitAt {
            return 0.7 * Self.smooth(lead <= 0 ? 1 : (now - b.cueAt) / lead)
        }
        let after = now - b.hitAt
        let from = lead <= 0 ? 0.0 : 0.7
        if after < tuning.hold {
            // a quick rise for an impact with no held beat, a slow creep after one
            let rise = lead <= 0 ? min(1, after / 0.16) : after / tuning.hold
            return from + (1 - from) * Self.easeOut(rise)
        }
        return 1 - Self.smooth((after - tuning.hold) / tuning.release)
    }

    /// The light: drops through the held beat (slow in), then comes back over `lightBack` after the payoff.
    func dimEnvelope(_ b: Beat) -> Double {
        let lead = b.hitAt - b.cueAt
        guard lead > 0 else { return 0 }
        if now < b.hitAt { return Self.smooth((now - b.cueAt) / lead) }
        return 1 - Self.smooth((now - b.hitAt) / tuning.lightBack)
    }

    static func smooth(_ x: Double) -> Double { let c = min(1, max(0, x)); return c * c * (3 - 2 * c) }
    static func easeOut(_ x: Double) -> Double { let c = min(1, max(0, x)); return 1 - (1 - c) * (1 - c) }
}
