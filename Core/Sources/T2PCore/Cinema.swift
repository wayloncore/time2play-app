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

/// Option B, the storm (#717): one strike staged the way a real one lights a scene (docs/app/cinematic.md, sources 6
/// and 10): the scene darkens, a dim stepped leader works down the channel, then one big return stroke (the flash,
/// the bolt at full HDR brightness so it blooms), and a long violet afterglow on the cards and the table. Now and
/// then a restrike follows down the same channel. Thunder (thunder.ahap) starts at the return stroke.
///
/// Photosensitivity: the return stroke is one flash and a restrike at most one more, so a strike is never more than
/// two; strikes start at least `minGap` apart, so no second holds more than two (WCAG 2.3.1 allows three).
public enum StormStrike {
    /// When the scene starts to darken, when the leader starts, when the return stroke lands (seconds from the strike).
    public static let leaderAt = 0.10, strokeAt = 0.27
    /// How long the whole strike lasts (the afterglow's tail).
    public static let duration = 1.9
    /// Strikes never start closer than this.
    public static let minGap = 1.9

    public struct Frame: Equatable, Sendable {
        /// The flash and afterglow on the scene and the table (0 to 1).
        public var flash = 0.0
        /// The bolt's brightness: over 1 is HDR (it blooms).
        public var bolt = 0.0
        /// How much of the channel is drawn, from the cloud down (the stepped leader; 1 is all of it).
        public var reveal = 1.0
        /// How far the scene's own light has dropped before the stroke (0 to 1).
        public var dark = 0.0
        public init() {}
    }

    /// The strike `t` seconds after it began; `restrike` is the delay of a restrike after the return stroke (0 for none).
    public static func at(_ t: Double, restrike: Double = 0) -> Frame {
        var f = Frame()
        guard t >= 0, t < duration else { return f }
        if t < strokeAt {
            // the darkening, then the leader stepping down (5 steps), dim, no flash
            f.dark = min(1, t / leaderAt)
            if t >= leaderAt {
                let p = (t - leaderAt) / (strokeAt - leaderAt)
                f.reveal = min(1, (floor(p * 5) + 1) / 5)
                f.bolt = 0.3
            } else {
                f.reveal = 0
            }
            return f
        }
        let s = t - strokeAt
        // the return stroke: the whole channel at once, the brightest it gets, falling fast; a faint channel lingers
        f.bolt = 2.4 * exp(-s * 9) + 0.12 * exp(-s * 2.2)
        // the afterglow: at its brightest at once, then one long smooth fall (no flicker inside it)
        f.flash = exp(-s * 2.4)
        f.dark = max(0, 1 - s / 0.08)
        if restrike > 0 && s >= restrike {
            let r = s - restrike
            f.bolt += 1.5 * exp(-r * 12)
            f.flash += 0.35 * exp(-r * 8)
        }
        // the tail ends at zero, never a cut
        let tail = max(0, min(1, (duration - t) / 0.3))
        f.flash *= tail; f.bolt *= tail
        return f
    }
}

/// WCAG 2.3.1's count, for a series of luminance values (0 to 1) sampled `fps` times a second: the most general
/// flashes (pairs of opposing changes of 0.1 or more, the darker state under 0.8) in any one second. The same rule as
/// scripts/flashcheck.py, which counts a recording; this one checks a modelled curve in the unit tests.
public enum FlashCount {
    public static func mostInASecond(_ series: [Double], fps: Double) -> Int {
        var trans: [Int] = []
        guard var lo = series.first else { return 0 }
        var hi = lo
        var dir = 0
        for (i, v) in series.enumerated().dropFirst() {
            switch dir {
            case 0:
                lo = min(lo, v); hi = max(hi, v)
                if v - lo >= 0.1 && lo < 0.8 { trans.append(i); dir = 1; hi = v } else if hi - v >= 0.1 && v < 0.8 { trans.append(i); dir = -1; lo = v }
            case 1:
                if v > hi { hi = v } else if hi - v >= 0.1 && v < 0.8 { trans.append(i); dir = -1; lo = v }
            default:
                if v < lo { lo = v } else if v - lo >= 0.1 && lo < 0.8 { trans.append(i); dir = 1; hi = v }
            }
        }
        var best = 0, j = 0
        for i in trans.indices {
            while Double(trans[i] - trans[j]) >= fps { j += 1 }
            best = max(best, (i - j + 1) / 2)
        }
        return best
    }
}

/// Option C, big moments only (#718): calm play, then a short directed sequence (1 to 2 s, in slow motion) for the
/// moments that matter, and nothing in between. The sequence borrows from both other options, but only for the moment:
/// the director's anticipation and push-in (Thomas and Johnston), the storm's staged strike and bloom, plus a slow-motion
/// hold and a color grade (the world loses color and gains contrast, so the one thing that happened carries the
/// color). Swink: cinema answers the player, so only your moments count, and one sequence never follows another
/// straight away (a cool-down), so the effect stays rare enough to mean something.
public enum MomentKind: String, CaseIterable, Sendable {
    /// Overdraft: a +2 or +4 lands on you, or you take the train (your hand overdrawn).
    case overdraft
    /// Overdraft: a Change Suit or +4 is played and the weather turns.
    case suitChange
    /// 10000: every die you threw can score (hot dice).
    case hotDice
    /// 10000: your roll scores nothing.
    case farkle

    /// How a sequence of this kind plays.
    public struct Tuning: Sendable, Equatable {
        /// The scene's speed through the hold (1 is real time).
        public var slow: Double
        /// How long the slow-motion hold lasts after the payoff (real seconds).
        public var hold: Double
        /// The longest wind-up before the payoff comes by itself (real seconds); the scene usually calls it sooner.
        public var maxLead: Double
        /// How far the camera pushes in at most (0 to 1 of the arena's push).
        public var push: Double
        /// The shake the payoff adds (trauma, 0 to 1).
        public var trauma: Double
        /// How much the light drops in the wind-up (0 to 1).
        public var dim: Double
    }

    public var tuning: Tuning {
        switch self {
        case .overdraft: return Tuning(slow: 0.3, hold: 0.75, maxLead: 0.7, push: 1, trauma: 0.6, dim: 1)
        case .suitChange: return Tuning(slow: 0.5, hold: 0.55, maxLead: 0.3, push: 0.55, trauma: 0, dim: 0.5)
        case .hotDice: return Tuning(slow: 0.3, hold: 0.8, maxLead: 0.6, push: 0.9, trauma: 0, dim: 0.6)
        case .farkle: return Tuning(slow: 0.3, hold: 0.8, maxLead: 0.6, push: 0.9, trauma: 0, dim: 0.8)
        }
    }
}

/// What a big moment asks of the camera and the scene this frame: the director's shot (push, light, time scale, shake)
/// and the grade (0 is the scene as it is; 1 is the sequence's look: less color, more contrast, more bloom).
public struct MomentShot: Equatable, Sendable {
    public var camera = DirectorShot()
    public var grade = 0.0
    public init() {}
    public static let calm = MomentShot()
}

/// Option C's director: one sequence at a time, on real time.
///
/// A sequence: `cue` starts the wind-up (the scene slows towards `slow`, the light drops, the push and the grade come
/// in, about 0.3 s); the scene calls `payoff` when the moment lands (the return stroke, the dice reaching the felt),
/// or it comes by itself after `maxLead`; the hold plays in slow motion; then the release brings the speed back
/// (0.45 s) while the push and the grade ease out. From cue to full speed is 1 to 2 s. `knock` adds a little shake
/// on its own (the Farkle's dice coming to rest).
/// Reduce Motion: no slow motion, no push, no shake and no grade; the moment is a gentle dip of the light and back.
public struct MomentDirector: Sendable {
    public enum Phase: Equatable, Sendable { case idle, windUp, hold, release }

    /// The wind-up's ease into slow motion, the release's ease out of it, and the cool-down before another sequence
    /// can start (real seconds).
    public var windUp = 0.3, release = 0.45, coolDown = 1.2
    /// The push and the grade ease out this much longer than the speed does (slow out).
    public var settle = 0.45
    /// The shake at full trauma: smaller than the director's (#716), since the slow motion carries the weight.
    public var maxYaw = 0.014, maxPitch = 0.01, maxRoll = 0.024, maxShift = 0.08, noiseSpeed = 9.0

    public var reduced = false {
        didSet { if reduced && phase != .idle { phase = .idle; kind = nil; trauma = Trauma(decayPerSecond: 1.6) } }
    }
    public private(set) var phase = Phase.idle
    public private(set) var kind: MomentKind?
    public private(set) var now = 0.0
    public private(set) var trauma = Trauma(decayPerSecond: 1.6)
    /// When the current phase began, and the last sequence ended (real seconds).
    private var phaseAt = 0.0, endedAt = -99.0
    /// Where the wind-up had got to when the payoff came early (so the hold starts from there, never a jump).
    private var windUpReached = 0.0
    /// Reduce Motion's dip of the light: when it began.
    private var dipAt: Double?
    private let seed: UInt32

    public init(seed: UInt32 = 718) { self.seed = seed }

    /// A sequence is playing (or its cool-down hasn't run out): a new cue now is dropped.
    public var busy: Bool { phase != .idle || now - endedAt < coolDown }

    /// A big moment is coming. Returns whether a sequence starts (false while another plays or cools down). With
    /// Reduce Motion it starts only the dip of the light.
    @discardableResult
    public mutating func cue(_ k: MomentKind) -> Bool {
        guard !busy else { return false }
        if reduced {
            if let d = dipAt, now - d < 1.2 { return false }
            dipAt = now
            return true
        }
        kind = k; phase = .windUp; phaseAt = now; windUpReached = 0
        return true
    }

    /// The moment landed: the hold starts now (from wherever the wind-up had got to).
    public mutating func payoff() {
        guard phase == .windUp, let k = kind else { return }
        windUpReached = Self.smooth((now - phaseAt) / windUp)
        phase = .hold; phaseAt = now
        trauma.add(k.tuning.trauma)
    }

    /// A little shake on its own (0 to 1 of trauma). Nothing with Reduce Motion.
    public mutating func knock(_ amount: Double) {
        guard !reduced else { return }
        trauma.add(amount)
    }

    /// The next frame, `dt` real seconds on.
    public mutating func step(_ dt: Double) -> MomentShot {
        now += max(0, dt)
        trauma.step(dt)
        if let k = kind {
            let t = k.tuning, inPhase = now - phaseAt
            switch phase {
            case .windUp where inPhase >= t.maxLead: payoff()
            case .hold where inPhase >= t.hold: phase = .release; phaseAt = now
            case .release where inPhase >= release + settle: phase = .idle; kind = nil; endedAt = now
            default: break
            }
        }
        return shot()
    }

    /// The shot for the director's time now.
    public func shot() -> MomentShot {
        var s = MomentShot()
        if reduced {
            if let d = dipAt {
                // a gentle dip and back over a second (no flash: one slow change, far under WCAG's 10% a frame pair)
                let x = now - d
                s.camera.dim = x < 0.3 ? 0.5 * Self.smooth(x / 0.3) : 0.5 * (1 - Self.smooth((x - 0.3) / 0.7))
            }
            return s
        }
        if let k = kind {
            let t = k.tuning, x = now - phaseAt
            // how far into the sequence's look: up through the wind-up, held, and eased out after the speed is back
            let look: Double
            let speed: Double   // 0 is real time, 1 is the slow motion
            switch phase {
            case .windUp: look = Self.smooth(x / windUp); speed = look
            case .hold:
                // a payoff that came before the wind-up was done eases the rest of the way (never a jump in speed)
                let rest = Self.smooth(x / 0.15)
                look = windUpReached + (1 - windUpReached) * rest; speed = look
            case .release: look = 1 - Self.smooth(x / (release + settle)); speed = 1 - Self.smooth(x / release)
            case .idle: look = 0; speed = 0
            }
            s.camera.timeScale = 1 - (1 - t.slow) * speed
            // the push: to 60% through the wind-up, creeping to all the way through the hold, easing out at the end
            let push: Double
            switch phase {
            case .windUp: push = 0.6 * look
            case .hold: push = windUpReached * 0.6 + (1 - windUpReached * 0.6) * Self.easeOut(x / max(t.hold, 0.01))
            case .release: push = 1 - Self.smooth(x / (release + settle))
            case .idle: push = 0
            }
            s.camera.push = push * t.push
            // the light drops through the wind-up and comes back with the payoff, over a quarter second
            switch phase {
            case .windUp: s.camera.dim = t.dim * look
            case .hold: s.camera.dim = t.dim * windUpReached * (1 - Self.smooth(x / 0.25))
            default: s.camera.dim = 0
            }
            s.grade = look
        }
        let k = trauma.shake
        if k > 0 {
            let n = now * noiseSpeed
            s.camera.yaw = k * maxYaw * SmoothNoise.at(n, seed: seed)
            s.camera.pitch = k * maxPitch * SmoothNoise.at(n + 31.7, seed: seed &+ 1)
            s.camera.roll = k * maxRoll * SmoothNoise.at(n + 63.1, seed: seed &+ 2)
            s.camera.shiftX = k * maxShift * SmoothNoise.at(n * 0.8 + 97.3, seed: seed &+ 3)
            s.camera.shiftY = k * maxShift * SmoothNoise.at(n * 0.8 + 129.9, seed: seed &+ 4)
        }
        return s
    }

    static func smooth(_ x: Double) -> Double { let c = min(1, max(0, x)); return c * c * (3 - 2 * c) }
    static func easeOut(_ x: Double) -> Double { let c = min(1, max(0, x)); return 1 - (1 - c) * (1 - c) }
}
