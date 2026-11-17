import Foundation

/// Overdraft's 3D table (#496): the table's shape, where the seats go and where the camera sits, as plain math with no
/// UI, so it runs in the package tests. A port of the approved prototype (docs/overdraft-3d/overdraft-3d.html on the
/// website's design/overdraft-3d branch): world units, Y up, you at the near end (+Z), the far end at -Z.
public enum Table3D {
    /// The felt's half-axes, and the glass's outer edge as a factor of them.
    public static let rx = 2.2, rz = 5.4, rim = 1.11
    /// A card: width, length, thickness.
    public static let cardW = 1.26, cardH = 1.89, cardT = 0.011
    /// The glass slab's thickness.
    public static let glassT = 0.2
    /// The table is a stadium: straight sides, round ends.
    public static let a0 = rz - rx
    public static let qa = Double.pi * rx / 2
    public static let perim = 4 * a0 + 4 * qa
    /// The draw pile (halfway up the center line) and the discard pile (big, in front of you).
    public static let deckAt = T3Vec(0, 0.008, 0.2)
    public static let pileAt = T3Vec(0, 0.008, 4.0)
    /// A seat's face-down hand is this size of a card on the piles.
    public static let handScale = 0.27
    /// Cards in the draw pile, at most.
    public static let deckCards = 22
    /// Cards kept on the discard pile.
    public static let pileCards = 12

    public struct RimPoint: Equatable, Sendable { public var x, z, nx, nz: Double }

    /// A point on the rim, `s` units round from your end (going up the left side, across the far end, back down the
    /// right); `k` scales out from the center line (1 is the play surface's edge).
    public static func rimPoint(_ s0: Double, _ k: Double = 1) -> RimPoint {
        let s = (s0.truncatingRemainder(dividingBy: perim) + perim).truncatingRemainder(dividingBy: perim)
        var z = 0.0, nx = 0.0, nz = 0.0
        if s < qa { let f = s / rx; nx = -sin(f); nz = cos(f); z = a0 }
        else if s < qa + 2 * a0 { nx = -1; nz = 0; z = a0 - (s - qa) }
        else if s < 3 * qa + 2 * a0 { let f = (s - qa - 2 * a0) / rx; nx = -cos(f); nz = -sin(f); z = -a0 }
        else if s < 3 * qa + 4 * a0 { nx = 1; nz = 0; z = -a0 + (s - 3 * qa - 2 * a0) }
        else { let f = (s - 3 * qa - 4 * a0) / rx; nx = cos(f); nz = sin(f); z = a0 }
        return RimPoint(x: nx * rx * k, z: z + nz * rx * k, nx: nx, nz: nz)
    }

    /// The camera's vertical field of view for a screen, in degrees (a 38° horizontal view, 38° to 72° tall).
    public static func fov(width: Double, height: Double) -> Double {
        let aspect = width / max(1, height), hf = 38 * Double.pi / 180
        return min(72, max(38, 2 * atan(tan(hf / 2) / aspect) * 180 / Double.pi))
    }

    /// Where the seats' hands fan, for a seat's card count (at most 7 shown): local positions and yaws, in hand units.
    public static func handFan(_ cards: Int) -> [(x: Double, y: Double, z: Double, yaw: Double)] {
        let c = min(max(cards, 0), 7)
        return (0..<c).map { i in
            let f = (Double(i) - Double(c - 1) / 2) * 0.17
            return (sin(f) * 1.15, 0.006 + Double(i) * 0.008, (1 - cos(f)) * 1.15, -f)
        }
    }

    /// A stable small number in 0..<1 from an integer (a pile card's place fixes how it lies).
    public static func jitter(_ k: Int, _ salt: Int) -> Double {
        var h = UInt64(bitPattern: Int64(k &* 73_856_093 ^ salt &* 19_349_663))
        h = (h ^ (h >> 33)) &* 0xff51_afd7_ed55_8ccd
        h = (h ^ (h >> 33)) &* 0xc4ce_b9fe_1a85_ec53
        h ^= h >> 33
        return Double(h % 10_000) / 10_000
    }

    /// How a discard pile card lies: a small turn and offset, fixed by its place in the pile.
    public static func pileLie(_ k: Int) -> (yaw: Double, dx: Double, dz: Double) {
        ((jitter(k, 1) - 0.5) * 0.4, (jitter(k, 2) - 0.5) * 0.1, (jitter(k, 3) - 0.5) * 0.08)
    }
}

/// A point or direction in the table's world.
public struct T3Vec: Equatable, Sendable {
    public var x, y, z: Double
    public init(_ x: Double, _ y: Double, _ z: Double) { self.x = x; self.y = y; self.z = z }
    public static func + (a: T3Vec, b: T3Vec) -> T3Vec { T3Vec(a.x + b.x, a.y + b.y, a.z + b.z) }
    public static func - (a: T3Vec, b: T3Vec) -> T3Vec { T3Vec(a.x - b.x, a.y - b.y, a.z - b.z) }
    public static func * (a: T3Vec, k: Double) -> T3Vec { T3Vec(a.x * k, a.y * k, a.z * k) }
    public func dot(_ b: T3Vec) -> Double { x * b.x + y * b.y + z * b.z }
    public func cross(_ b: T3Vec) -> T3Vec { T3Vec(y * b.z - z * b.y, z * b.x - x * b.z, x * b.y - y * b.x) }
    public var length: Double { sqrt(dot(self)) }
    public var normalized: T3Vec { let l = length; return l > 0 ? self * (1 / l) : self }
}

/// A rectangle of the screen, in points from the top left.
public struct T3Rect: Equatable, Sendable {
    public var x0, y0, x1, y1: Double
    public init(x0: Double, y0: Double, x1: Double, y1: Double) { self.x0 = x0; self.y0 = y0; self.x1 = x1; self.y1 = y1 }
    public var width: Double { x1 - x0 }
    public var height: Double { y1 - y0 }
    public func intersects(_ o: T3Rect) -> Bool { x0 < o.x1 && o.x0 < x1 && y0 < o.y1 && o.y0 < y1 }
}

/// A camera: where it is, which way it looks, and the screen it draws to (points).
public struct Table3DCamera: Equatable, Sendable {
    public var eye: T3Vec
    public var right: T3Vec, up: T3Vec, back: T3Vec
    public var fovY: Double
    public var width: Double, height: Double

    public static func lookAt(eye: T3Vec, target: T3Vec, fovY: Double, width: Double, height: Double) -> Table3DCamera {
        let f = (target - eye).normalized
        let r = f.cross(T3Vec(0, 1, 0)).normalized
        let u = r.cross(f)
        return Table3DCamera(eye: eye, right: r, up: u, back: f * -1, fovY: fovY, width: width, height: height)
    }

    /// Points per world unit at depth 1.
    public var focal: Double { (height / 2) / tan(fovY * Double.pi / 360) }
    /// How far in front of the camera a point is.
    public func depth(_ p: T3Vec) -> Double { -(p - eye).dot(back) }
    /// Where a point lands on the screen, in points.
    public func project(_ p: T3Vec) -> (x: Double, y: Double) {
        let d = p - eye, z = max(1e-4, -d.dot(back))
        return (width / 2 + focal * d.dot(right) / z, height / 2 - focal * d.dot(up) / z)
    }
    /// How many points one world unit spans at a point (facing the camera).
    public func pointsPerUnit(at p: T3Vec) -> Double { focal / max(1e-4, depth(p)) }
    /// The point under a screen point, at the depth where a card is `cardPoints` wide.
    public func fromScreen(x: Double, y: Double, cardPoints: Double) -> T3Vec {
        let depth = Table3D.cardW * focal / max(1, cardPoints)
        let dir = right * ((x - width / 2) / focal) + up * (-(y - height / 2) / focal) - back
        return eye + dir * depth
    }
}

/// Another player's seat round the rim: a billboard (face, count, name) on the rim, its hand on the table in front.
public struct Table3DSeat: Equatable, Sendable {
    /// Turns after yours: 1 plays next (when play goes forward).
    public var order: Int
    /// How far round the rim, from your end.
    public var s: Double
    /// Six or more at the table: faces and counts, names on tap.
    public var compact: Bool
    /// The billboard's size, and the face's radius and height over the billboard's center (world units).
    public var w, h, faceR, faceY: Double
    /// Half the billboard's width that's drawn (the name pill, or the face and count).
    public var halfW: Double
    /// The name sits above the face (a nearer seat would cover it below).
    public var nameTop: Bool
    /// Far seats are drawn a little bigger than perspective alone makes them, so faces stay readable.
    public var scale: Double
    /// The billboard's center, and the seat's hand on the table and which way it faces.
    public var pos: T3Vec
    public var handPos: T3Vec
    public var handYaw: Double
    public var nx, nz: Double

    /// The scaled sizes.
    public var sw: Double { w * scale }
    public var sh: Double { h * scale }
    public var sHalfW: Double { halfW * scale }
}

/// The seats and the camera for one screen: the seated view down the table from your end.
public struct Table3DLayout: Equatable, Sendable {
    public var width: Double, height: Double
    public var free: T3Rect
    public var seats: [Table3DSeat]
    public var camera: Table3DCamera
    /// Where the horizon sits on the screen.
    public var horizonY: Double

    /// - Parameters:
    ///   - players: everyone at the table, you included (2 to 10).
    ///   - free: the part of the screen the table may use (under the header, over your hand).
    ///   - labels: each other seat's name width in world units at the name's size (0.35), in turn order; nil guesses.
    public static func make(players: Int, width: Double, height: Double, free: T3Rect, labels: [Double]? = nil) -> Table3DLayout {
        let n = min(10, max(2, players)), m = n - 1, compact = n >= 6
        let path = 4 * Table3D.a0 + 2 * Table3D.qa
        var seats: [Table3DSeat] = (0..<m).map { i in
            let s = Table3D.qa + (m == 2 ? [0.16, 0.84][i] : (Double(i) + 0.5) / Double(m)) * path
            let w = compact ? 1.4 : 2.5, h = compact ? 1.3 : 2.2
            let faceR = compact ? (n >= 8 ? 0.37 : 0.48) : 0.6
            var halfW = compact ? 0.56 : 0
            if !compact {
                let tw = labels.flatMap { $0.indices.contains(i) ? $0[i] : nil } ?? 1.0
                let pw = min(w - 8.0 / 256, tw + 0.3)
                halfW = max(faceR + 0.3, pw / 2) + 0.03
            }
            return Table3DSeat(order: i + 1, s: s, compact: compact, w: w, h: h, faceR: faceR, faceY: compact ? -0.14 : 0.28,
                               halfW: halfW, nameTop: false, scale: 1, pos: T3Vec(0, 0, 0), handPos: T3Vec(0, 0, 0), handYaw: 0, nx: 0, nz: 0)
        }
        place(&seats)
        let fovY = Table3D.fov(width: width, height: height)
        var horizon = free.y0 + min(60, max(28, free.height * 0.09))   // a band of sky under the header: the storm shows
        var cam = Table3DCamera.lookAt(eye: T3Vec(0, 3, Table3D.rz + 6), target: T3Vec(0, 3, 0), fovY: fovY, width: width, height: height)
        for _ in 0..<5 {
            (cam, horizon) = solve(seats: seats, width: width, height: height, free: free, fovY: fovY, horizon: horizon)
            // far seats a little bigger, so faces stay readable (players come second, after the table)
            let near = seats.map { cam.pointsPerUnit(at: $0.pos) }.max() ?? 1
            var changed = false
            for i in seats.indices {
                let k = cam.pointsPerUnit(at: seats[i].pos)
                let sc = min(1.35, max(1, (near / max(1e-6, k)).squareRoot()))
                if abs(sc - seats[i].scale) > 0.01 { seats[i].scale = sc; changed = true }
            }
            // a name goes over its face only where a nearer seat would cover it underneath
            for i in seats.indices where !seats[i].compact {
                let top = nameCovered(i, seats: seats, cam: cam)
                if top != seats[i].nameTop { seats[i].nameTop = top; seats[i].faceY = top ? -0.26 : 0.28; changed = true }
            }
            if changed { place(&seats); continue }
            // the empty band between the horizon and the far seats: bring the horizon down into it
            let topY = seats.flatMap { corners($0, cam) }.map { $0.y }.min() ?? horizon
            let target = max(18, free.height * 0.05)
            let room = topY - horizon - target
            if room > 4 && horizon < free.y0 + free.height * 0.34 { horizon += min(room * 0.8, free.y0 + free.height * 0.34 - horizon) } else { break }
        }
        (cam, horizon) = solve(seats: seats, width: width, height: height, free: free, fovY: fovY, horizon: horizon)
        return Table3DLayout(width: width, height: height, free: free, seats: seats, camera: cam, horizonY: horizon)
    }

    static func place(_ seats: inout [Table3DSeat]) {
        for i in seats.indices {
            let p = Table3D.rimPoint(seats[i].s, Table3D.rim + 0.02), q = Table3D.rimPoint(seats[i].s, 0.66)
            seats[i].pos = T3Vec(p.x, seats[i].sh / 2 - 0.02, p.z)
            seats[i].handPos = T3Vec(q.x, 0, q.z)
            seats[i].handYaw = atan2(p.nx, p.nz)
            seats[i].nx = p.nx; seats[i].nz = p.nz
        }
    }

    /// A billboard's four corners on the screen (it always faces the camera).
    static func corners(_ s: Table3DSeat, _ cam: Table3DCamera) -> [(x: Double, y: Double)] {
        var out: [(x: Double, y: Double)] = []
        let hw = s.sHalfW > 0 ? s.sHalfW : s.sw / 2
        for sx in [-1.0, 1.0] { for sy in [-1.0, 1.0] { out.append(cam.project(s.pos + cam.right * (sx * hw) + cam.up * (sy * s.sh / 2))) } }
        return out
    }

    /// A seat's face, as a screen rectangle.
    public static func faceRect(_ s: Table3DSeat, _ cam: Table3DCamera) -> T3Rect {
        let k = cam.pointsPerUnit(at: s.pos), c = cam.project(s.pos)
        let fx = c.x + (s.compact ? -0.06 * s.scale * k : 0), fy = c.y - s.faceY * s.scale * k, r = s.faceR * s.scale * k
        return T3Rect(x0: fx - r, y0: fy - r, x1: fx + r, y1: fy + r)
    }

    /// Would a seat's name, under its face, sit over a nearer seat's face or name?
    static func nameCovered(_ i: Int, seats: [Table3DSeat], cam: Table3DCamera) -> Bool {
        var s = seats[i]; s.nameTop = false; s.faceY = 0.28
        let k = cam.pointsPerUnit(at: s.pos), c = cam.project(s.pos)
        let pill = T3Rect(x0: c.x - s.sHalfW * k, y0: c.y + (s.sh / 2 - 0.55 * s.scale) * k, x1: c.x + s.sHalfW * k, y1: c.y + s.sh / 2 * k)
        return seats.indices.contains { j in
            guard j != i, seats[j].pos.z > s.pos.z + 0.05 else { return false }
            let o = seats[j], ko = cam.pointsPerUnit(at: o.pos), co = cam.project(o.pos)
            let box = T3Rect(x0: co.x - o.sHalfW * ko, y0: co.y - o.sh / 2 * ko, x1: co.x + o.sHalfW * ko, y1: co.y + o.sh / 2 * ko)
            return pill.intersects(box)
        }
    }

    /// The seated camera (the prototype's solveSeated): the horizon a little under the header, the seats along the
    /// sides filling the width, the discard pile's near edge just over your hand. Returns the camera and where the
    /// horizon ended up (it moves down if the far seats would reach under the header).
    static func solve(seats: [Table3DSeat], width W: Double, height H: Double, free: T3Rect, fovY: Double, horizon: Double) -> (Table3DCamera, Double) {
        let f = (H / 2) / tan(fovY * Double.pi / 360), fh = free.height, fw = min(W - 10, fh * 1.25)
        let nearEdge = T3Vec(0, 0, Table3D.pileAt.z + Table3D.cardH / 2 + 0.1), tableEnd = Table3D.a0 + Table3D.rx * Table3D.rim
        var yH = horizon, h = 3.0, zc = Table3D.rz + 6, pitch = 0.0
        func pose() -> Table3DCamera {
            Table3DCamera.lookAt(eye: T3Vec(0, h, zc), target: T3Vec(0, h - tan(pitch) * 10, zc - 10), fovY: fovY, width: W, height: H)
        }
        func halfWidth(_ c: Table3DCamera) -> Double {
            seats.flatMap { corners($0, c) }.map { abs($0.x - W / 2) }.max() ?? 0
        }
        var cam = pose()
        for _ in 0..<4 {
            pitch = atan((H / 2 - yH) / f)
            for _ in 0..<4 {
                var lo = tableEnd + 4.3, hi = 80.0
                for _ in 0..<20 { zc = (lo + hi) / 2; if halfWidth(pose()) > fw / 2 { lo = zc } else { hi = zc } }
                zc = hi; lo = 0.5; hi = 20
                for _ in 0..<20 { h = (lo + hi) / 2; if pose().project(nearEdge).y < free.y1 - 6 { lo = h } else { hi = h } }
                h = hi
            }
            cam = pose()
            let minY = seats.flatMap { corners($0, cam) }.map { $0.y }.min() ?? free.y0
            if minY < free.y0 + 4 { yH += free.y0 + 4 - minY } else { break }
        }
        return (pose(), yH)
    }

    /// Where a seat's billboard sits on the screen: its center and points per world unit there.
    public func screen(_ s: Table3DSeat) -> (x: Double, y: Double, k: Double) {
        let c = camera.project(s.pos)
        return (c.x, c.y, camera.pointsPerUnit(at: s.pos))
    }
}
