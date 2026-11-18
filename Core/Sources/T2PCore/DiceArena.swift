import Foundation

/// The 3D dice arena for Hot Dice and Roll Call (#521), as plain math with no UI, so it runs in the package tests: the
/// tray's shape, the keep row, the cup, the camera, the dice's faces, and a small physics simulation of a throw.
/// World units: a die is 1 across. Y is up, you sit at +Z (the keep row is at the front, nearest you).
///
/// The room's roll is the truth. A throw is simulated without knowing the faces (it doesn't need them), and once the
/// room says what came up, each die is turned by one of the cube's own symmetries so the face that lands up is the
/// room's. A symmetry leaves the cube's shape exactly where it was, so the whole tumble stays the same and still lands
/// on the right face.
public enum DiceArena {
    // MARK: the tray

    /// Half a die, and its corners pulled in a little for the rounded edges.
    public static let half = 0.5
    static let corner = 0.47
    /// The rolling floor's inner walls: left/right at ±trayX, the back wall, and the front wall (the keep shelf's edge).
    /// Build 45 (Tyler, Nov 18: "Dice are too big"): a die is about a ninth of the felt's width (it was a seventh),
    /// with a deeper floor, so the dice look like real dice in a real tray and have room to tumble and spread out.
    /// The website's Hot Dice table is 7 dice wide on a phone and 15 to 19 on a wide screen (src/games/farkle/table-dims.js).
    public static let trayX = 5.6, zBack = -4.2, zFront = 2.4
    /// The wooden rim's width and height above the felt.
    public static let rimW = 0.6, rimH = 1.0
    /// The keep shelf in front of the floor: its top, where the keep row sits, and its front edge.
    public static let shelfY = 0.62, keepZ = zFront + 0.92, shelfZ1 = zFront + 2.05

    /// Where a kept die sits: slot `i` of `slots` along the keep row (its center).
    public static func keepSpot(_ i: Int, of slots: Int) -> T3Vec {
        let spacing = slots >= 6 ? 1.3 : 1.45
        return T3Vec((Double(i) - Double(slots - 1) / 2) * spacing, shelfY + half, keepZ)
    }

    /// The cup: its mouth while it shakes and pours (above the back of the tray), and where it rests on the felt
    /// holding the dice between turns (the center of its base).
    public static let cupMouth = T3Vec(0, 2.75, zBack + 0.55)
    public static let cupRest = T3Vec(-(trayX - 1.0), 0, zBack + 1.0)
    public static let cupHeight = 1.7, cupRadius = 0.92

    // MARK: faces

    /// The six local axes, and the face each one carries (1 opposite 6, 2 opposite 5, 3 opposite 4).
    public static let axes: [T3Vec] = [T3Vec(1, 0, 0), T3Vec(-1, 0, 0), T3Vec(0, 1, 0), T3Vec(0, -1, 0), T3Vec(0, 0, 1), T3Vec(0, 0, -1)]
    public static let axisFace = [3, 4, 1, 6, 2, 5]

    /// The local axis a face sits on.
    public static func axis(of face: Int) -> T3Vec { axes[axisFace.firstIndex(of: min(6, max(1, face))) ?? 2] }

    /// The local axis pointing most nearly up for an orientation.
    public static func upAxis(_ q: DQuat) -> Int {
        var best = 0, top = -9.0
        for (i, a) in axes.enumerated() { let y = q.rotate(a).y; if y > top { top = y; best = i } }
        return best
    }

    /// The face showing on top for an orientation.
    public static func upFace(_ q: DQuat) -> Int { axisFace[upAxis(q)] }

    /// The cube's 24 turning symmetries (each takes the cube onto itself).
    public static let symmetries: [DQuat] = {
        var found: [DQuat] = [DQuat.identity]
        let gens = [DQuat.axisAngle(T3Vec(1, 0, 0), .pi / 2), DQuat.axisAngle(T3Vec(0, 1, 0), .pi / 2), DQuat.axisAngle(T3Vec(0, 0, 1), .pi / 2)]
        var i = 0
        while i < found.count {
            for g in gens {
                let q = (found[i] * g).normalized
                if !found.contains(where: { abs($0.dot(q)) > 0.999 }) { found.append(q) }
            }
            i += 1
        }
        return found
    }()

    /// The symmetry that makes a die which landed with `landed` up show `want` instead: shown = landed orientation * fix.
    /// `pick` chooses among the four that do it (they differ by a quarter turn about the up axis).
    public static func fix(landedUp landed: Int, want: Int, pick: Int = 0) -> DQuat {
        let from = axis(of: want), to = axis(of: landed)
        let ok = symmetries.filter { ($0.rotate(from) - to).length < 1e-6 }
        return ok.isEmpty ? .identity : ok[abs(pick) % ok.count]
    }

    /// A neat orientation with `face` up and its edges square to the keep row.
    public static func neat(_ face: Int) -> DQuat {
        let a = axis(of: face)
        return symmetries.first { ($0.rotate(a) - T3Vec(0, 1, 0)).length < 1e-6 } ?? .identity
    }

    /// The flat orientation nearest `q`: its most-up axis turned exactly up, its turn about the up axis kept.
    public static func flatten(_ q: DQuat) -> DQuat {
        let w = q.rotate(axes[upAxis(q)]), up = T3Vec(0, 1, 0)
        let c = w.cross(up), s = c.length, d = w.dot(up)
        if s < 1e-9 { return q }
        return (DQuat.axisAngle(c, atan2(s, d)) * q).normalized
    }

    // MARK: the camera

    /// The camera for an arena drawn `width` × `height` points: it looks down at the tray from your side, steeper on
    /// a tall screen, and is as close as it can be with the tray, the shelf and the cup's mouth all in view.
    /// `top` keeps the tray below a band at the top of the view (words drawn over the scene); the cup may use it.
    public static func camera(width: Double, height: Double, tray: DiceTray = .classic, top: Double = 0) -> Table3DCamera {
        let w = max(60, width), h = max(60, height)
        let pitch = (tray.shelf ? min(66, max(44, 44 + (h / w - 0.7) * 34)) : min(74, max(56, 56 + (h / w - 0.4) * 30))) * Double.pi / 180
        let target = tray.target
        let fov = 32.0
        let ox = tray.x + tray.rimW, zb = tray.zBack - tray.rimW, z1 = tray.outerZ1
        let pts = [T3Vec(-ox, tray.rimH, zb), T3Vec(ox, tray.rimH, zb), T3Vec(-ox, tray.rimH, z1), T3Vec(ox, tray.rimH, z1),
                   T3Vec(-ox, -0.15, z1), T3Vec(ox, -0.15, z1)]
        let cupPoint = tray.shelf ? [T3Vec(0, cupMouth.y - 0.4, cupMouth.z)] : []
        let mx = tray.shelf ? 6.0 : 4.0, my = 4.0
        func fits(_ d: Double) -> Table3DCamera? {
            let eye = target + T3Vec(0, sin(pitch), cos(pitch)) * d
            let cam = Table3DCamera.lookAt(eye: eye, target: target, fovY: fov, width: w, height: h)
            for p in pts + cupPoint {
                if cam.depth(p) < 0.5 { return nil }
                let s = cam.project(p)
                let y0 = cupPoint.contains(p) ? my : max(my, top + my)
                if s.x < mx || s.x > w - mx || s.y < y0 || s.y > h - my { return nil }
            }
            return cam
        }
        var lo = 4.0, hi = 120.0
        for _ in 0..<40 { let mid = (lo + hi) / 2; if fits(mid) != nil { hi = mid } else { lo = mid } }
        return fits(hi) ?? Table3DCamera.lookAt(eye: target + T3Vec(0, sin(pitch), cos(pitch)) * hi, target: target, fovY: fov, width: w, height: h)
    }

    /// Where the camera looks for a camera made by `camera(...)` (its eye minus the target is how far back it sits).
    public static func target(_ tray: DiceTray) -> T3Vec { tray.target }

    /// How big a die's button is over the 3D dice (points), for a die drawn `pointsPerUnit` points across: never
    /// under 44, so a die drawn small is still easy to tap.
    public static func tapSide(pointsPerUnit: Double) -> Double { min(130, max(44, (pointsPerUnit * 1.15).rounded())) }

    // MARK: the ease-in after your roll (build 45, Tyler Nov 18: "the zoom needs to be like the Farkle games on my website")

    /// The website's Hot Dice (src/games/farkle/table.js easeIn and phoneEase; main.js roll): once your own roll comes
    /// to rest, the camera eases in toward the dice (same angle, about half a second) and holds there while you pick;
    /// it eases back to the whole table only when you roll again, bank, Farkle or the turn ends. Bots' and other
    /// players' rolls never move it, and Reduce Motion never does.
    public static let easeInSeconds = 0.52, easeHomeSeconds = 0.42

    /// The ease's curve (the website's easeInOutQuad).
    public static func easeInOut(_ x: Double) -> Double {
        let p = min(1, max(0, x))
        return p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2
    }

    /// Where the camera eases in to after your roll lands: the point it looks at and how far back it sits (a share
    /// of the fitted distance, 1 being the fitted view). `base` is the fitted camera, `dice` the dice that just
    /// landed (their centers), `top` the band of words over the top of the view.
    /// A phone (a view taller than wide) gets the nearest view where the dice read at least 44 points (50 when they
    /// lie close together) that still shows the side rails where the dice are, keeps every die clear of the words at
    /// the top and the bottom edge, and keeps the whole keep row in view (a tapped die goes there). A wider view gets
    /// the website's slight move: in to 82 to 90% of the distance, looking a little toward the dice.
    public static func easeIn(camera base: Table3DCamera, tray: DiceTray, dice: [T3Vec], slots: Int, top: Double) -> (look: T3Vec, k: Double) {
        let home = tray.target
        guard !dice.isEmpty else { return (home, 1) }
        let w = base.width, h = base.height
        let off = base.eye - home, dist = off.length
        guard dist > 0 else { return (home, 1) }
        let dir = off * (1 / dist)
        var c = T3Vec(0, 0, 0)
        for d in dice { c = c + d }
        c = c * (1 / Double(dice.count))
        let spread = max(1, dice.map { T3Vec($0.x - c.x, 0, $0.z - c.z).length }.max() ?? 1)
        let keep = tray.shelf ? (0..<slots).map { keepSpot($0, of: slots) } : []
        func cam(_ look: T3Vec, _ k: Double) -> Table3DCamera {
            Table3DCamera.lookAt(eye: look + dir * (dist * k), target: look, fovY: base.fovY, width: w, height: h)
        }
        // every die clear of the words and the bottom edge, and the keep row in view
        func clear(_ cm: Table3DCamera) -> Bool {
            for p in dice {
                let a = cm.project(p)
                if a.y < top + 20 || a.y > h - 20 || a.x < 10 || a.x > w - 10 { return false }
            }
            for p in keep {
                let a = cm.project(p)
                if a.y > h - 14 || a.y < top || a.x < 6 || a.x > w - 6 { return false }
            }
            return true
        }
        if w / h >= 0.8 {
            // a slight move: close together, in to about 82% of the distance; spread wide, only to about 90%
            let look = T3Vec(home.x + (c.x - home.x) * 0.55, home.y, home.z + (c.z - home.z) * 0.55)
            var k = min(0.9, max(0.82, 0.74 + spread / min(2 * tray.x, tray.zFront - tray.zBack) * 0.4))
            while k < 1 && !clear(cam(look, k)) { k += 0.01 }
            return k >= 1 ? (home, 1) : (look, k)
        }
        let wide = min(1, max(0, (spread - 2) / 3))
        let want = 50 + (44 - 50) * wide
        let look = T3Vec(home.x, home.y, min(tray.zFront - 1, max(tray.zBack + 2, c.z)))
        let nearZ = min(tray.zFront, (dice.map(\.z).max() ?? 0) + 1.5)
        func size(_ k: Double) -> Double? {
            let cm = cam(look, k)
            // the rails at the dice's near end, where the tray is widest on screen
            let l = cm.project(T3Vec(-tray.x - 0.2, tray.rimH * 0.6, nearZ)), r = cm.project(T3Vec(tray.x + 0.2, tray.rimH * 0.6, nearZ))
            if l.x < 0 || r.x > w || !clear(cm) { return nil }
            var s = 0.0
            for p in dice {
                let e = cm.project(p + T3Vec(0.5, 0, 0)), f = cm.project(p - T3Vec(0.5, 0, 0))
                s += ((e.x - f.x) * (e.x - f.x) + (e.y - f.y) * (e.y - f.y)).squareRoot() / Double(dice.count)
            }
            return s
        }
        var best = 1.0
        var k = 1.0
        while k >= 0.5 {
            guard let s = size(k) else { break }
            best = k
            if s >= want { break }
            k -= 0.01
        }
        return best >= 1 ? (home, 1) : (look, best)
    }
}

/// A tray's shape (#521, #523): Hot Dice's deep tray with the keep shelf in front and the cup behind, or Roll Call's
/// shallow one, where five dice roll and then settle into a fixed row of slots.
public struct DiceTray: Equatable, Sendable {
    /// The rolling floor's inner walls (left/right at ±x), the rim, and whether there's a keep shelf in front.
    public var x, zBack, zFront, rimW, rimH: Double
    public var shelf: Bool
    public init(x: Double, zBack: Double, zFront: Double, rimW: Double, rimH: Double, shelf: Bool) {
        self.x = x; self.zBack = zBack; self.zFront = zFront; self.rimW = rimW; self.rimH = rimH; self.shelf = shelf
    }
    public static let classic = DiceTray(x: DiceArena.trayX, zBack: DiceArena.zBack, zFront: DiceArena.zFront,
                                         rimW: DiceArena.rimW, rimH: DiceArena.rimH, shelf: true)
    /// Build 45: Roll Call's tray is wider and deeper for the same five dice (a die was a seventh of its width, now
    /// about a ninth), so a roll has room to tumble before the dice settle into their places.
    public static let row = DiceTray(x: 4.4, zBack: -2.2, zFront: 2.2, rimW: 0.45, rimH: 0.75, shelf: false)
    /// The front edge of the whole tray (the shelf's, or the front rim's).
    public var outerZ1: Double { shelf ? DiceArena.shelfZ1 : zFront + rimW }
    public var target: T3Vec { shelf ? T3Vec(0, 0.2, 0.1) : T3Vec(0, 0, 0.15) }
    /// Roll Call's fixed slots: die `i` of `n`, left to right across the middle of the tray.
    public func slot(_ i: Int, of n: Int) -> T3Vec {
        T3Vec((Double(i) - Double(n - 1) / 2) * 1.5, DiceArena.half, 0.1)
    }
    /// Where a kept or held die sits.
    public func keep(_ i: Int, of n: Int) -> T3Vec { shelf ? DiceArena.keepSpot(i, of: n) : slot(i, of: n) }
}

/// A rotation (a unit quaternion).
public struct DQuat: Equatable, Sendable {
    public var x, y, z, w: Double
    public init(_ x: Double, _ y: Double, _ z: Double, _ w: Double) { self.x = x; self.y = y; self.z = z; self.w = w }
    public static let identity = DQuat(0, 0, 0, 1)

    public static func axisAngle(_ a: T3Vec, _ angle: Double) -> DQuat {
        let n = a.normalized, s = sin(angle / 2)
        return DQuat(n.x * s, n.y * s, n.z * s, cos(angle / 2))
    }
    public static func * (a: DQuat, b: DQuat) -> DQuat {
        DQuat(a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
              a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
              a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
              a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z)
    }
    public var conjugate: DQuat { DQuat(-x, -y, -z, w) }
    public func dot(_ o: DQuat) -> Double { x * o.x + y * o.y + z * o.z + w * o.w }
    public var normalized: DQuat {
        let l = (x * x + y * y + z * z + w * w).squareRoot()
        return l > 0 ? DQuat(x / l, y / l, z / l, w / l) : .identity
    }
    public func rotate(_ v: T3Vec) -> T3Vec {
        let u = T3Vec(x, y, z), t = u.cross(v) * 2
        return v + t * w + u.cross(t)
    }
    public static func slerp(_ a: DQuat, _ b0: DQuat, _ t: Double) -> DQuat {
        var b = b0, d = a.dot(b0)
        if d < 0 { b = DQuat(-b.x, -b.y, -b.z, -b.w); d = -d }
        if d > 0.9995 {
            return DQuat(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t, a.w + (b.w - a.w) * t).normalized
        }
        let th = acos(d), s = sin(th), k0 = sin((1 - t) * th) / s, k1 = sin(t * th) / s
        return DQuat(a.x * k0 + b.x * k1, a.y * k0 + b.y * k1, a.z * k0 + b.z * k1, a.w * k0 + b.w * k1)
    }
}

/// Where a die is at one moment of a throw.
public struct DicePose: Equatable, Sendable {
    public var p: T3Vec
    public var q: DQuat
    /// Out of the cup yet (before that it's inside it, hidden).
    public var out: Bool
}

/// A simulated throw: every die's pose at 60 frames a second, from the moment the cup pours to the last die at rest.
public struct DiceThrow: Equatable, Sendable {
    public static let fps = 60.0
    public var frames: [[DicePose]]
    /// When each die first touched the felt (seconds after the pour), and when each came to rest.
    public var firstHit: [Double]
    public var settledAt: [Double]
    public var count: Int { frames.first?.count ?? 0 }
    public var duration: Double { Double(max(0, frames.count - 1)) / Self.fps }
    /// Where each die came to rest.
    public var rest: [DicePose] { frames.last ?? [] }
    /// The face each die landed on, before any fix.
    public var landed: [Int] { rest.map { DiceArena.upFace($0.q) } }

    /// The pose of die `i` at `t` seconds, between frames.
    public func pose(_ i: Int, at t: Double) -> DicePose {
        guard !frames.isEmpty else { return DicePose(p: DiceArena.cupMouth, q: .identity, out: false) }
        let f = max(0, t * Self.fps)
        let k = min(frames.count - 1, Int(f))
        let n = min(frames.count - 1, k + 1)
        let a = frames[k][i], b = frames[n][i], u = min(1, f - Double(k))
        return DicePose(p: a.p + (b.p - a.p) * u, q: DQuat.slerp(a.q, b.q, u), out: a.out || (u > 0.5 && b.out))
    }

    /// For each die, the symmetry that makes it land on the room's face (shown orientation = simulated * fix).
    public func fixes(for faces: [Int]) -> [DQuat] {
        landed.enumerated().map { i, up in DiceArena.fix(landedUp: up, want: i < faces.count ? faces[i] : up, pick: i) }
    }
}

/// The throw's physics: the dice pour from the cup's mouth toward you, fall, bounce off the felt, the rim and each
/// other, tumble and come to rest flat, never on top of or inside another die. Corners against the walls and each
/// other, with sequential impulses (restitution and friction); a die that has nearly stopped eases flat.
/// The same seed gives the same throw.
public enum DiceSim {
    static let g = -42.0, dt = 1.0 / 240, keepEvery = 4

    struct Body {
        var p: T3Vec, q: DQuat, v: T3Vec, w: T3Vec
        var launch: Double, out = false, calm = 0.0, asleep = false
        var hit: Double? = nil, settledAt: Double? = nil
        var settle: (t0: Double, dur: Double, p0: T3Vec, q0: DQuat, p1: T3Vec, q1: DQuat)?
        var free: Bool { out && !asleep && settle == nil }
    }
    struct Plane { var n: T3Vec; var d: Double; var e: Double; var mu: Double }
    struct Contact {
        var a: Int, b: Int, ra: T3Vec, rb: T3Vec, n: T3Vec, depth: Double, e: Double, mu: Double
        var target = 0.0, kn = 0.0, ln = 0.0, lt = T3Vec(0, 0, 0)
    }

    static func planes(_ t: DiceTray) -> [Plane] {
        [Plane(n: T3Vec(0, 1, 0), d: 0, e: 0.32, mu: 0.5),
         Plane(n: T3Vec(1, 0, 0), d: -t.x, e: 0.45, mu: 0.25),
         Plane(n: T3Vec(-1, 0, 0), d: -t.x, e: 0.45, mu: 0.25),
         Plane(n: T3Vec(0, 0, 1), d: t.zBack, e: 0.45, mu: 0.25),
         Plane(n: T3Vec(0, 0, -1), d: -t.zFront, e: 0.45, mu: 0.25)]
    }
    static let corners: [T3Vec] = {
        let r = DiceArena.corner
        var c: [T3Vec] = []
        for sx in [-1.0, 1.0] { for sy in [-1.0, 1.0] { for sz in [-1.0, 1.0] { c.append(T3Vec(sx * r, sy * r, sz * r)) } } }
        return c
    }()

    /// A small, fast, seeded random source (xorshift32).
    struct Rand {
        var s: UInt32
        init(_ seed: UInt32) { s = seed == 0 ? 1 : seed }
        mutating func next() -> Double {
            s ^= s << 13; s ^= s >> 17; s ^= s << 5
            return Double(s) / 4_294_967_296
        }
    }

    /// A throw of `count` dice (1 to 6) into `tray`. `still` are dice already lying flat in the tray (Roll Call's held
    /// dice in their slots): the throw bounces off them and never comes to rest on them.
    public static func run(count: Int, seed: UInt32, maxT: Double = 2.4, tray: DiceTray = .classic, still: [T3Vec] = []) -> DiceThrow {
        let n = max(1, min(6, count))
        var r = Rand(seed)
        var dice: [Body] = []
        // the throw scales with the tray's depth (build 45's trays are deeper), so the dice reach as far across it
        let k = (tray.zFront - tray.zBack) / (tray.shelf ? 4.8 : 3.4)
        for i in 0..<n {
            let lane = n == 1 ? 0 : Double(i) / Double(n - 1) - 0.5
            let p: T3Vec, v: T3Vec
            if tray.shelf {
                let spread = min(3.4, tray.x * 0.6)
                p = T3Vec(lane * spread + (r.next() - 0.5) * 0.4, 2.3 + r.next() * 0.6, tray.zBack + 0.7 + (r.next() - 0.5) * 0.4)
                v = T3Vec((lane * 2.6 + (r.next() - 0.5) * 1.6) * k, -1 - r.next() * 1.5, (3.8 + r.next() * 1.8) * k)
            } else {
                // a toss from just behind the back rim, across the shallow tray
                let spread = min(3.0, tray.x * 0.62)
                p = T3Vec(lane * spread + (r.next() - 0.5) * 0.3, 1.9 + r.next() * 0.5, tray.zBack + 0.75 + (r.next() - 0.5) * 0.2)
                v = T3Vec((lane * 1.8 + (r.next() - 0.5) * 1.4) * k, -0.6 - r.next() * 1.0, (1.8 + r.next() * 1.4) * k)
            }
            let q = DQuat(r.next() - 0.5, r.next() - 0.5, r.next() - 0.5, r.next() - 0.5).normalized
            let w = T3Vec((r.next() - 0.5) * 30, (r.next() - 0.5) * 16, (r.next() - 0.5) * 30)
            dice.append(Body(p: p, q: q, v: v, w: w, launch: Double(i) * 0.05))
        }
        for s in still {   // fixed, as if asleep from the start
            var b = Body(p: T3Vec(s.x, DiceArena.half, s.z), q: .identity, v: T3Vec(0, 0, 0), w: T3Vec(0, 0, 0), launch: 0)
            b.out = true; b.asleep = true
            dice.append(b)
        }
        let walls = planes(tray)
        var frames: [[DicePose]] = [dice.prefix(n).map { DicePose(p: $0.p, q: $0.q, out: false) }]
        var t = 0.0, step = 0
        while true {
            for i in dice.indices where !dice[i].out && t >= dice[i].launch { dice[i].out = true }
            for i in dice.indices where dice[i].free { dice[i].v.y += g * dt }
            var cs = contacts(dice, walls)
            solve(&dice, &cs, t: t)
            for i in dice.indices { integrate(&dice, i, t: t, maxT: maxT, tray: tray) }
            t += dt; step += 1
            if step % keepEvery == 0 { frames.append(dice.prefix(n).map { DicePose(p: $0.p, q: $0.q, out: $0.out) }) }
            if dice.allSatisfy(\.asleep) { break }
            if t > maxT + 3 { break }   // never: everything settles by maxT + 0.6 at the latest
        }
        // the last frame is exactly at rest
        let thrown = Array(dice.prefix(n))
        frames.append(thrown.map { DicePose(p: $0.settle?.p1 ?? $0.p, q: $0.settle?.q1 ?? $0.q, out: true) })
        return DiceThrow(frames: frames, firstHit: thrown.map { $0.hit ?? $0.settledAt ?? t }, settledAt: thrown.map { $0.settledAt ?? t })
    }

    static func contacts(_ dice: [Body], _ planes: [Plane]) -> [Contact] {
        var cs: [Contact] = []
        let h = DiceArena.half
        for (i, d) in dice.enumerated() where d.free {
            for c in corners {
                let rc = d.q.rotate(c), wc = d.p + rc
                for pl in planes {
                    let dist = pl.n.dot(wc) - pl.d
                    if dist < 0 { cs.append(Contact(a: i, b: -1, ra: rc, rb: T3Vec(0, 0, 0), n: pl.n, depth: -dist, e: pl.e, mu: pl.mu)) }
                }
            }
        }
        for i in dice.indices {
            for j in dice.indices where j > i {
                let A = dice[i], B = dice[j]
                guard A.out, B.out, A.free || B.free else { continue }
                let dp = A.p - B.p, dist = dp.length
                if dist > 1.8 { continue }
                for (X, Y, xi, yi) in [(A, B, i, j), (B, A, j, i)] {
                    for c in corners {
                        let wc = X.p + X.q.rotate(c)
                        let l = Y.q.conjugate.rotate(wc - Y.p)
                        let ls = [l.x, l.y, l.z]
                        if abs(ls[0]) >= h || abs(ls[1]) >= h || abs(ls[2]) >= h { continue }
                        var k = 0, best = 9.0
                        for m in 0..<3 { let pen = h - abs(ls[m]); if pen < best { best = pen; k = m } }
                        var ax = [0.0, 0.0, 0.0]; ax[k] = ls[k] < 0 ? -1 : 1
                        let n = Y.q.rotate(T3Vec(ax[0], ax[1], ax[2]))   // out of Y, toward X's corner
                        cs.append(Contact(a: xi, b: yi, ra: wc - X.p, rb: wc - Y.p, n: n, depth: best, e: 0.3, mu: 0.06))
                    }
                }
                if dist < 0.96 && dist > 1e-6 {   // the rounded edges: centers never closer than this
                    let n = dp * (1 / dist), mid = B.p + n * (dist / 2)
                    cs.append(Contact(a: i, b: j, ra: mid - A.p, rb: mid - B.p, n: n, depth: 0.96 - dist, e: 0.3, mu: 0))
                }
            }
        }
        return cs
    }

    static func velocity(_ dice: [Body], _ k: Int, _ r: T3Vec) -> T3Vec {
        guard k >= 0, dice[k].free else { return T3Vec(0, 0, 0) }
        return dice[k].v + dice[k].w.cross(r)
    }

    static func push(_ dice: inout [Body], _ k: Int, _ r: T3Vec, _ imp: T3Vec) {
        guard k >= 0, dice[k].free else { return }
        dice[k].v = dice[k].v + imp
        dice[k].w = dice[k].w + r.cross(imp) * 6   // a cube's inertia is the same about every axis: 1/6 for mass 1, side 1
    }

    static func solve(_ dice: inout [Body], _ cs: inout [Contact], t: Double) {
        func rel(_ c: Contact) -> T3Vec { velocity(dice, c.a, c.ra) - velocity(dice, c.b, c.rb) }
        func k(_ c: Contact, _ dir: T3Vec) -> Double {
            var s = 0.0
            if c.a >= 0 && dice[c.a].free { let x = c.ra.cross(dir); s += 1 + 6 * x.dot(x) }
            if c.b >= 0 && dice[c.b].free { let x = c.rb.cross(dir); s += 1 + 6 * x.dot(x) }
            return s
        }
        for i in cs.indices {
            let vn = rel(cs[i]).dot(cs[i].n)
            var target = vn < -1.2 ? -cs[i].e * vn : 0
            target = max(target, min(3, 0.25 / dt * max(0, cs[i].depth - 0.004)) * 0.25)
            cs[i].target = target
            cs[i].kn = k(cs[i], cs[i].n)
            if cs[i].b < 0 && cs[i].n.y > 0.5 && dice[cs[i].a].hit == nil { dice[cs[i].a].hit = t }
        }
        for _ in 0..<10 {
            for i in cs.indices where cs[i].kn > 0 {
                let c = cs[i]
                let vn = rel(c).dot(c.n)
                let ln = max(0, c.ln + (c.target - vn) / c.kn)
                let imp = c.n * (ln - c.ln)
                cs[i].ln = ln
                push(&dice, c.a, c.ra, imp); push(&dice, c.b, c.rb, imp * -1)
                // friction, against the slip
                let rv = rel(c)
                let vt = rv - c.n * rv.dot(c.n), s = vt.length
                if s < 1e-7 { continue }
                let tdir = vt * (1 / s), kt = k(c, tdir)
                if kt <= 0 { continue }
                var want = cs[i].lt - tdir * (s / kt)
                let wl = want.length, cap = c.mu * ln
                if wl > cap { want = want * (cap / wl) }
                let timp = want - cs[i].lt
                cs[i].lt = want
                push(&dice, c.a, c.ra, timp); push(&dice, c.b, c.rb, timp * -1)
            }
        }
    }

    static func integrate(_ dice: inout [Body], _ i: Int, t: Double, maxT: Double, tray: DiceTray) {
        guard dice[i].out, !dice[i].asleep else { return }
        if let s = dice[i].settle {
            let k = min(1, (t - s.t0) / s.dur), e = k * k * (3 - 2 * k)
            dice[i].p = s.p0 + (s.p1 - s.p0) * e
            dice[i].q = DQuat.slerp(s.q0, s.q1, e)
            if k >= 1 { dice[i].asleep = true; dice[i].settle = nil; dice[i].settledAt = t }
            return
        }
        var d = dice[i]
        d.p = d.p + d.v * dt
        let dq = DQuat(d.w.x, d.w.y, d.w.z, 0) * d.q
        d.q = DQuat(d.q.x + dq.x * dt / 2, d.q.y + dq.y * dt / 2, d.q.z + dq.z * dt / 2, d.q.w + dq.w * dt / 2).normalized
        let low = corners.map { d.p.y + d.q.rotate($0).y }.min() ?? 0
        let grounded = low < 0.03
        if grounded {
            d.w = d.w * (1 - 2.6 * dt)
            d.v = T3Vec(d.v.x * (1 - 1.4 * dt), d.v.y, d.v.z * (1 - 1.4 * dt))
        }
        let calm = d.v.length < 0.45 && d.w.length < 1.3
        d.calm = calm ? d.calm + dt : 0
        dice[i] = d
        if d.calm > (grounded ? 0.06 : 0.2) || (t > maxT && d.hit != nil) || t > maxT + 0.6 { beginSettle(&dice, i, t: t, tray: tray) }
    }

    /// Two flat dice's footprints overlap (or come within a hair): how far, and which way to push the first clear.
    static func overlap(_ ap: T3Vec, _ aq: DQuat, _ bp: T3Vec, _ bq: DQuat) -> (pen: Double, ax: (Double, Double))? {
        func yaw(_ q: DQuat) -> Double {
            let f = q.rotate(T3Vec(1, 0, 0)), g = q.rotate(T3Vec(0, 0, 1))
            let e = abs(f.y) < 0.5 ? f : g
            return atan2(e.z, e.x)
        }
        let ya = yaw(aq), yb = yaw(bq), h = DiceArena.half
        let d = (bp.x - ap.x, bp.z - ap.z)
        var best = 9.0, ax = (1.0, 0.0)
        for y in [ya, ya + .pi / 2, yb, yb + .pi / 2] {
            let u = (cos(y), sin(y))
            let ra = h * (abs(cos(ya) * u.0 + sin(ya) * u.1) + abs(-sin(ya) * u.0 + cos(ya) * u.1))
            let rb = h * (abs(cos(yb) * u.0 + sin(yb) * u.1) + abs(-sin(yb) * u.0 + cos(yb) * u.1))
            let along = d.0 * u.0 + d.1 * u.1
            let pen = ra + rb + 0.04 - abs(along)
            if pen <= 0 { return nil }
            if pen < best { best = pen; ax = along < 0 ? (-u.0, -u.1) : u }
        }
        return (best, ax)
    }

    static func beginSettle(_ dice: inout [Body], _ i: Int, t: Double, tray: DiceTray) {
        let q1 = DiceArena.flatten(dice[i].q), h = DiceArena.half, m = 0.72
        var p1 = T3Vec(dice[i].p.x, h, dice[i].p.z)
        let others: [(T3Vec, DQuat)] = dice.indices.compactMap { j in
            guard j != i else { return nil }
            if let s = dice[j].settle { return (s.p1, s.q1) }
            return dice[j].asleep ? (dice[j].p, dice[j].q) : nil
        }
        func inside(_ p: T3Vec) -> T3Vec {
            T3Vec(min(tray.x - m, max(-tray.x + m, p.x)), h, min(tray.zFront - m, max(tray.zBack + m, p.z)))
        }
        // never settle into another die: slide clear of the ones already down, staying inside the walls
        for _ in 0..<6 {
            var moved = false
            for o in others {
                if let hit = overlap(p1, q1, o.0, o.1) { p1 = T3Vec(p1.x - hit.ax.0 * hit.pen, h, p1.z - hit.ax.1 * hit.pen); moved = true }
            }
            p1 = inside(p1)
            if !moved { break }
        }
        func clear(_ p: T3Vec) -> Bool { others.allSatisfy { overlap(p, q1, $0.0, $0.1) == nil } }
        if !clear(p1) {   // wedged: the nearest free spot, searched outward
            let c0 = p1
            search: for step in 1..<60 {
                let rad = Double(step) * 0.15
                for k in 0..<24 {
                    let a = Double(k) / 24 * 2 * .pi
                    let p = T3Vec(c0.x + cos(a) * rad, h, c0.z + sin(a) * rad)
                    if p.x < -tray.x + m || p.x > tray.x - m || p.z < tray.zBack + m || p.z > tray.zFront - m { continue }
                    if clear(p) { p1 = p; break search }
                }
            }
        }
        let far = (p1 - dice[i].p).length
        dice[i].settle = (t0: t, dur: 0.14 + far * 0.3, p0: dice[i].p, q0: dice[i].q, p1: p1, q1: q1)
    }
}

/// What the arena should show for a moment of a game (#521): each die in the cup, on the felt, or in the keep row.
public struct ArenaDie: Equatable, Sendable {
    public enum Place: Equatable, Sendable {
        case cup
        case tray
        /// In the keep row: `locked` is set aside earlier in the turn (it can't come back); otherwise picked this roll.
        case keep(slot: Int, locked: Bool)
    }
    public var id: Int
    public var face: Int?
    public var place: Place
    public init(id: Int, face: Int?, place: Place) { self.id = id; self.face = face; self.place = place }
}

public struct ArenaState: Equatable, Sendable {
    public var dice: [ArenaDie]
    /// Keep row slots: 6 for Hot Dice, 5 for Roll Call.
    public var slots: Int
    /// The roll the dice on the felt came from ("n.seq"): a new one is a new throw.
    public var roll: String?
    /// The room is rolling and hasn't said the faces yet: the cup shakes.
    public var shaking: Bool
    /// The dice on the felt that could score (a faint light under them once they land).
    public var scoring: Set<Int>
    public var farkle: Bool
    /// Your roll: a tap as the dice land.
    public var mine: Bool
    /// #523: Roll Call's row: every die has its own slot; a thrown die settles back into it, a held one stays in it.
    public var row = false
    public init(dice: [ArenaDie], slots: Int, roll: String? = nil, shaking: Bool = false, scoring: Set<Int> = [], farkle: Bool = false, mine: Bool = false) {
        self.dice = dice; self.slots = slots; self.roll = roll; self.shaking = shaking; self.scoring = scoring; self.farkle = farkle; self.mine = mine
    }

    public func die(_ id: Int) -> ArenaDie? { dice.first { $0.id == id } }

    /// Hot Dice: the turn's six dice. `scoringFaces` are the faces in this roll that can score (the room's own scoring).
    public static func hotDice(_ t: HotDice.Turn?, scoringFaces: Set<Int>?, mine: Bool) -> ArenaState {
        guard let t else { return ArenaState(dice: (0..<6).map { ArenaDie(id: $0, face: nil, place: .cup) }, slots: 6) }
        let ids = t.dice.map(\.id)
        let order = t.kept + t.sel.filter { !t.kept.contains($0) }.sorted()
        func slot(_ id: Int) -> Int { order.firstIndex(of: id) ?? 0 }
        let thrown = t.state != "start" && t.state != "rolling"
        let dice: [ArenaDie] = ids.map { id in
            let face = t.value(id)
            if t.state == "start" { return ArenaDie(id: id, face: face, place: .cup) }
            if t.kept.contains(id) { return ArenaDie(id: id, face: face, place: .keep(slot: slot(id), locked: true)) }
            if t.live.contains(id) {
                if !thrown || face == nil { return ArenaDie(id: id, face: nil, place: .cup) }
                if t.sel.contains(id) { return ArenaDie(id: id, face: face, place: .keep(slot: slot(id), locked: false)) }
                return ArenaDie(id: id, face: face, place: .tray)
            }
            return ArenaDie(id: id, face: face, place: .cup)
        }
        let onFelt = dice.filter { $0.place == .tray }
        let scoring = Set(onFelt.filter { d in d.face.map { scoringFaces?.contains($0) ?? false } ?? false }.map(\.id))
        let live = t.live.compactMap { t.value($0) }
        return ArenaState(dice: dice, slots: 6, roll: thrown && !live.isEmpty ? "\(t.n).\(t.seq)" : nil,
                          shaking: t.state == "rolling", scoring: t.state == "choose" ? scoring : [], farkle: t.state == "farkle", mine: mine)
    }

    /// Roll Call: five dice, held ones in the keep row in their own places.
    public static func rollCall(_ v: RollCall.View) -> ArenaState {
        guard let t = v.turn, v.diceShown else {
            var s = ArenaState(dice: (0..<5).map { ArenaDie(id: $0, face: nil, place: .cup) }, slots: 5)
            s.row = true
            return s
        }
        let dice: [ArenaDie] = (0..<5).map { i in
            let face = i < t.dice.count ? t.dice[i] : nil
            let held = i < t.held.count && t.held[i]
            return ArenaDie(id: i, face: face, place: held ? .keep(slot: i, locked: false) : .tray)
        }
        var s = ArenaState(dice: dice, slots: 5, roll: v.rollKey, mine: v.common.yourTurn)
        s.row = true
        return s
    }
}
