import SceneKit
import UIKit
import simd
import T2PCore

/// The dice arena in SceneKit (#521): a felt-lined tray with a wooden rim and a keep shelf in front, a leather cup,
/// and the dice. A throw plays a simulated tumble (DiceSim) turned so each die lands on the room's face; everything
/// else is a short tween. Few nodes, no SceneKit physics: the tumble is worked out before it plays.
/// Build 48: the scene moves a frame at a time on a thread of its own, from the stage's display link (`tick`, see
/// SceneTicker), never from SceneKit's render callback. SceneKit sometimes stopped calling back after the first frame, so a
/// roll never landed, its dice couldn't be kept and Bank never came on. Other threads `post` changes, run at the start
/// of the next frame.
final class DiceArenaWorld: NSObject, SceneTicking {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    var reduced = false
    /// The tray's shape: Hot Dice's (shelf and cup) or Roll Call's row (#523).
    let tray: DiceTray
    private var row: Bool { !tray.shelf }

    // talking to the render thread
    private let lock = NSLock()
    private var pending: [() -> Void] = []
    private var lastTime: TimeInterval?
    private(set) var clock = 0.0

    // stills (screenshots): stop the clock a set time after a moment
    enum Moment { case pour, landed, kept }
    var freezeOn: (Moment, Double)?
    private var freezeAt: Double?
    private var frozenSaid = false
    var onFrozen: (() -> Void)?

    // what the scene tells the screen
    var onSpots: (([Int: DiceSpot]) -> Void)?
    var onLanded: ((String) -> Void)?
    var onFirstHit: (() -> Void)?
    /// The player has moved the view away from the fitted one (or put it back).
    var onMoved: ((Bool) -> Void)?
    private var movedSaid = false
    /// Build 45: the camera has eased in on your roll (true) or is on the whole tray (false).
    var onEased: ((Bool) -> Void)?
    private var easedSaid = false
    /// UI tests (-t2p-arena-debug): the scene's own state in one line, about twice a second.
    var onDebug: ((String) -> Void)?
    private var debugAt = 0.0, frames = 0

    // #716, option A of #708 (the director): your roll gets a held beat (the light drops a little and the camera
    // pushes in while the dice fly), a hit stop and a shake when they hit the felt, and a Farkle a harder knock.
    // Only with -t2p-cinema director; without it the arena is exactly as it was.
    let cinema = CinemaStyle.from(ProcessInfo.processInfo.arguments)
    private var director = CameraDirector()
    private var shot = DirectorShot.calm
    /// The scene's lights and their own intensities, for the held beat's drop.
    private var lights: [(light: SCNLight, base: CGFloat)] = []

    // the scene
    private var dieNodes: [Int: SCNNode] = [:]
    private var glowNodes: [Int: SCNNode] = [:]
    private var ringNodes: [Int: SCNNode] = [:]
    private var ringGold: UIImage?
    private let cup = SCNNode()
    private var glowGold: UIImage?, glowEmber: UIImage?
    private var glowing: [Int: (start: Double, peak: Double)] = [:]

    // the game as the scene shows it
    private var want: ArenaState?
    private var first = true
    private var thrown: String?
    private var landedKey: String?
    private var dice: [Int: DieRun] = [:]
    private var play: Throw?
    private var cupRun = CupRun()
    private var presim: (count: Int, seed: UInt32, th: DiceThrow)?
    private var simming = false
    private var lastSpots: [Int: DiceSpot] = [:]

    struct Pose { var p: SIMD3<Float>; var q: simd_quatf }
    enum Where: Equatable { case cup, felt, keep(Int), air }
    struct Tween {
        var from: Pose, to: Pose, t0: Double, dur: Double, arc: Float
        var fadeIn = false, fadeOut = false
        var end: Where
    }
    struct DieRun {
        var pose: Pose
        var at: Where = .cup
        var tween: Tween?
        var rest: Pose?
        var face: Int?
        var locked = false
        var shownLocked = false
    }
    struct Throw {
        var th: DiceThrow
        var ids: [Int]
        var fixes: [simd_quatf]
        var t0: Double
        var key: String
        var hitSaid = false
        var done = false
        /// Dice the room took back mid-tumble (they stop following the throw).
        var left: Set<Int> = []
        /// Played faster than real time (someone else's quick roll), with every die out from the start.
        var speed = 1.0
        var allOut = false
        /// The tumble is over and the dice are gliding to their places (Roll Call's slots, a reduced-motion drop):
        /// the throw lands when they're all there.
        var awaitingTweens = false
    }
    enum CupPhase { case away, hover, rest, tipped }
    struct CupRun {
        var phase = CupPhase.away
        var tween: (from: Pose, to: Pose, fromAlpha: Float, toAlpha: Float, t0: Double, dur: Double, then: CupPhase)?
        var pose = Pose(p: SIMD3<Float>(0, 9, -3.5), q: simd_quatf(angle: 0, axis: [0, 1, 0]))
        var alpha: Float = 0
        var shakeSince = 0.0
        var tipAt = 0.0
    }

    init(tray: DiceTray = .classic) {
        self.tray = tray
        super.init()
        build()
    }

    func post(_ f: @escaping () -> Void) { lock.lock(); pending.append(f); lock.unlock() }

    /// One frame (the Ticker's thread): what was posted, then the dice, the cup and the camera.
    func tick(_ time: TimeInterval) {
        lock.lock(); let work = pending; pending = []; lock.unlock()
        work.forEach { $0() }
        // a still keeps real time even when a slow simulator draws few frames, so it lands on time
        // (in play too, up to a tenth of a second a frame: a slow phone drops frames rather than falling behind the room)
        var dt = min(freezeOn == nil ? 0.1 : 0.25, max(0, time - (lastTime ?? time)))
        if lastTime == nil { dt = 1.0 / 60 }
        lastTime = time
        if let f = freezeAt {
            if clock >= f {
                dt = 0
                if !frozenSaid { frozenSaid = true; let cb = onFrozen; DispatchQueue.main.async { cb?() } }
            } else { dt = min(dt, f - clock) }
        }
        // #716: the director runs on real time, the scene on its time scale (0 during a hit stop: the dice hold)
        var directing = false
        if cinema == .director {
            director.reduced = reduced
            shot = director.step(dt)
            dt *= shot.timeScale
            directing = shot != .calm
            let lit = CGFloat(1 - 0.22 * shot.dim)
            for l in lights { l.light.intensity = l.base * lit }
        }
        clock += dt
        if dt > 0 || first { step() }
        if dt > 0 || first || rigDirty || directing { aimCamera(dt) }
        frames += 1
        if let cb = onDebug, clock - debugAt >= 0.5 { debugAt = clock; let line = debugLine(); DispatchQueue.main.async { cb(line) } }
    }

    private func debugLine() -> String {
        func at(_ w: Where) -> String { switch w { case .cup: return "c"; case .felt: return "f"; case .air: return "a"; case let .keep(k): return "k\(k)" } }
        let ds = (0..<6).compactMap { id in dice[id].map { "\(id)\(at($0.at))\($0.tween == nil ? "" : "~")" } }.joined(separator: " ")
        let p = play.map { "\($0.key)\($0.done ? "done" : "live")\($0.awaitingTweens ? "+tw" : "")" } ?? "-"
        return String(format: "render clk=%.1f frames=%d wall=%.1f ", clock, frames, Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1000)) + "want=\(want?.roll ?? "-")\(want?.shaking == true ? "/shake" : "") thrown=\(thrown ?? "-") landed=\(landedKey ?? "-") play=\(p) cup=\(cupRun.phase)\(cupRun.tween == nil ? "" : "~") tip=\(cupRun.tipAt > 0 ? "y" : "n") dice=\(ds)"
    }

    private func moment(_ m: Moment) {
        guard freezeAt == nil, let f = freezeOn, f.0 == m else { return }
        freezeAt = clock + f.1
    }

    // MARK: building the scene

    static let felt = UIColor(red: 0.10, green: 0.30, blue: 0.22, alpha: 1)

    private func build() {
        let cam = SCNCamera()
        cam.projectionDirection = .vertical
        cam.fieldOfView = 32
        cam.zNear = 0.5; cam.zFar = 200
        cameraNode.camera = cam
        scene.rootNode.addChildNode(cameraNode)
        scene.background.contents = UIColor.clear

        // a warm light over the tray with soft shadows, and a little warm fill
        let ambient = SCNLight(); ambient.type = .ambient; ambient.intensity = 380
        ambient.color = UIColor(red: 1, green: 0.93, blue: 0.84, alpha: 1)
        let an = SCNNode(); an.light = ambient; scene.rootNode.addChildNode(an)
        let key = SCNLight(); key.type = .spot; key.intensity = 1050
        key.color = UIColor(red: 1, green: 0.88, blue: 0.72, alpha: 1)
        key.spotInnerAngle = 40; key.spotOuterAngle = 95
        key.castsShadow = true
        key.shadowMode = .forward
        key.shadowSampleCount = 12
        key.shadowRadius = 5
        key.shadowMapSize = CGSize(width: 1536, height: 1536)
        key.shadowColor = UIColor(white: 0, alpha: 0.55)
        key.zNear = 2; key.zFar = 48
        // high enough that its pool of light covers build 45's bigger tray
        let kn = SCNNode(); kn.light = key; kn.simdPosition = [1.9, 15, 3.6]; kn.simdLook(at: [0, 0, 0.1])
        scene.rootNode.addChildNode(kn)
        let fill = SCNLight(); fill.type = .directional; fill.intensity = 160
        fill.color = UIColor(red: 0.85, green: 0.9, blue: 1, alpha: 1)
        let fn = SCNNode(); fn.light = fill; fn.simdPosition = [-6, 5, 8]; fn.simdLook(at: .zero)
        scene.rootNode.addChildNode(fn)
        lights = [(ambient, ambient.intensity), (key, key.intensity), (fill, fill.intensity)]

        buildTray()
        if tray.shelf { buildCup() }
        ringGold = Self.ringImage()
        glowGold = Self.glowImage(UIColor(red: 1, green: 0.84, blue: 0.48, alpha: 1))
        glowEmber = Self.glowImage(UIColor(red: 0.95, green: 0.38, blue: 0.16, alpha: 1))
    }

    private func box(_ w: Double, _ h: Double, _ l: Double, chamfer: Double = 0, _ m: SCNMaterial, at p: SIMD3<Float>) -> SCNNode {
        let g = SCNBox(width: w, height: h, length: l, chamferRadius: chamfer)
        g.materials = [m]
        let n = SCNNode(geometry: g)
        n.simdPosition = p
        scene.rootNode.addChildNode(n)
        return n
    }

    private func buildTray() {
        let X = tray.x, zb = tray.zBack, zf = tray.zFront, rw = tray.rimW, rh = tray.rimH
        let sy = DiceArena.shelfY, z1 = tray.outerZ1
        let wood = Self.material(Self.woodImage(), specular: 0.22, shine: 0.3, scale: 1)
        // the felt's weave keeps its size next to the dice whatever the tray's size (3 repeats across the first tray)
        let weave = Float(3 * 2 * X / 8.6)
        let felt = Self.material(Self.feltImage(), specular: 0, shine: 0.05, scale: weave)
        felt.normal.contents = Self.feltNormal(); felt.normal.intensity = 0.5
        felt.normal.wrapS = .repeat; felt.normal.wrapT = .repeat
        felt.normal.contentsTransform = SCNMatrix4MakeScale(weave, weave, 1)

        // the base under everything, then the felt floor
        _ = box(2 * (X + rw), 0.3, z1 - (zb - rw), chamfer: 0.06, wood, at: [0, -0.2, Float((z1 + zb - rw) / 2)])
        _ = box(2 * X, 0.1, zf - zb, felt, at: [0, -0.05, Float((zb + zf) / 2)])
        // the rim: two sides, the back
        for s in [-1.0, 1.0] {
            _ = box(rw, rh + 0.25, z1 - (zb - rw), chamfer: 0.1, wood, at: [Float(s * (X + rw / 2)), Float((rh - 0.25) / 2), Float((z1 + zb - rw) / 2)])
        }
        _ = box(2 * X + 0.02, rh + 0.25, rw, chamfer: 0.1, wood, at: [0, Float((rh - 0.25) / 2), Float(zb - rw / 2)])
        if !tray.shelf {
            // Roll Call: a plain front rim, and a faint mark on the felt for each die's place
            _ = box(2 * X + 0.02, rh + 0.25, rw, chamfer: 0.1, wood, at: [0, Float((rh - 0.25) / 2), Float(zf + rw / 2)])
            let mark = SCNMaterial(); mark.lightingModel = .constant
            mark.diffuse.contents = UIColor(white: 0, alpha: 1); mark.transparency = 0.16
            mark.writesToDepthBuffer = false; mark.blendMode = .alpha
            for i in 0..<5 {
                let spot = tray.slot(i, of: 5)
                let n = SCNNode(geometry: SCNPlane(width: 1.18, height: 1.18))
                (n.geometry as? SCNPlane)?.cornerRadius = 0.2
                n.geometry?.firstMaterial = mark
                n.eulerAngles.x = -.pi / 2
                n.simdPosition = [Float(spot.x), 0.006, Float(spot.z)]
                n.renderingOrder = 1
                scene.rootNode.addChildNode(n)
            }
        }
        addBlob(X: X, rw: rw, zb: zb, z1: z1)
        guard tray.shelf else { return }
        // the keep shelf: wood, with a dark leather strip on top where kept dice sit, edged in thin gold
        _ = box(2 * X + 0.02, sy + 0.25, z1 - zf, chamfer: 0.08, wood, at: [0, Float((sy - 0.25) / 2), Float((zf + z1) / 2)])
        let leather = Self.material(Self.leatherImage(UIColor(red: 0.16, green: 0.10, blue: 0.07, alpha: 1)), specular: 0.12, shine: 0.25, scale: 2)
        let stripL = z1 - zf - 0.42
        _ = box(2 * X - 0.36, 0.03, stripL, chamfer: 0.012, leather, at: [0, Float(sy + 0.012), Float((zf + z1) / 2)])
        let gold = SCNMaterial(); gold.lightingModel = .blinn
        gold.diffuse.contents = UIColor(red: 0.80, green: 0.62, blue: 0.30, alpha: 1)
        gold.specular.contents = UIColor(white: 0.8, alpha: 1); gold.shininess = 0.6
        for s in [-1.0, 1.0] {
            _ = box(2 * X - 0.3, 0.035, 0.035, gold, at: [0, Float(sy + 0.02), Float((zf + z1) / 2 + s * (stripL / 2 + 0.02))])
        }
    }

    /// A soft shadow round the tray, so it sits on the screen's felt.
    private func addBlob(X: Double, rw: Double, zb: Double, z1: Double) {
        let blob = SCNNode(geometry: SCNPlane(width: CGFloat(2 * (X + rw) + 2.6), height: CGFloat(z1 - zb + rw + 2.6)))
        let bm = SCNMaterial(); bm.lightingModel = .constant; bm.diffuse.contents = Self.blobImage()
        bm.writesToDepthBuffer = false; bm.blendMode = .alpha
        blob.geometry?.firstMaterial = bm
        blob.eulerAngles.x = -.pi / 2
        blob.simdPosition = [0, -0.36, Float((z1 + zb - rw) / 2) + 0.25]
        blob.renderingOrder = -1
        scene.rootNode.addChildNode(blob)
    }

    private func buildCup() {
        // the cup's node sits at its mouth; the body hangs below it (local -Y)
        let h = DiceArena.cupHeight, r = DiceArena.cupRadius
        let leather = Self.material(Self.leatherImage(UIColor(red: 0.34, green: 0.17, blue: 0.10, alpha: 1)), specular: 0.18, shine: 0.3, scale: 1)
        let inside = SCNMaterial(); inside.lightingModel = .blinn; inside.diffuse.contents = UIColor(red: 0.30, green: 0.17, blue: 0.10, alpha: 1)
        inside.emission.contents = UIColor(red: 0.10, green: 0.05, blue: 0.03, alpha: 1)
        let tube = SCNTube(innerRadius: CGFloat(r - 0.1), outerRadius: CGFloat(r), height: CGFloat(h))
        tube.radialSegmentCount = 40
        tube.materials = [leather, inside, leather, leather]
        let body = SCNNode(geometry: tube); body.simdPosition = [0, Float(-h / 2), 0]
        let base = SCNNode(geometry: SCNCylinder(radius: CGFloat(r), height: 0.12))
        base.geometry?.materials = [leather]
        base.simdPosition = [0, Float(-h + 0.06), 0]
        let gold = SCNMaterial(); gold.lightingModel = .blinn
        gold.diffuse.contents = UIColor(red: 0.82, green: 0.64, blue: 0.32, alpha: 1)
        gold.specular.contents = UIColor(white: 0.9, alpha: 1); gold.shininess = 0.7
        let band = SCNNode(geometry: SCNTube(innerRadius: CGFloat(r - 0.02), outerRadius: CGFloat(r + 0.035), height: 0.14))
        band.geometry?.materials = [gold]
        band.simdPosition = [0, -0.16, 0]
        for n in [body, base, band] { n.castsShadow = true; cup.addChildNode(n) }
        cup.opacity = 0
        cup.simdPosition = cupRun.pose.p
        scene.rootNode.addChildNode(cup)
    }

    private func dieNode(_ id: Int) -> SCNNode {
        if let n = dieNodes[id] { return n }
        let g = SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0.15)
        g.chamferSegmentCount = 4
        // SceneKit's box order: front (+Z), right (+X), back (-Z), left (-X), top (+Y), bottom (-Y)
        g.materials = [2, 3, 5, 4, 1, 6].map { DieArt.material($0) }
        let n = SCNNode(geometry: g)
        n.castsShadow = true
        n.opacity = 0
        scene.rootNode.addChildNode(n)
        dieNodes[id] = n
        let glow = SCNNode(geometry: SCNPlane(width: 2.9, height: 2.9))
        let m = SCNMaterial(); m.lightingModel = .constant; m.diffuse.contents = glowGold
        m.blendMode = .add; m.writesToDepthBuffer = false; m.isDoubleSided = true
        glow.geometry?.firstMaterial = m
        glow.eulerAngles.x = -.pi / 2
        glow.opacity = 0
        glow.renderingOrder = 2
        glow.castsShadow = false
        scene.rootNode.addChildNode(glow)
        glowNodes[id] = glow
        if row {
            // a held die's gold ring on the felt, under it (#523)
            let ring = SCNNode(geometry: SCNPlane(width: 1.62, height: 1.62))
            let rm = SCNMaterial(); rm.lightingModel = .constant; rm.diffuse.contents = ringGold
            rm.blendMode = .alpha; rm.writesToDepthBuffer = false; rm.isDoubleSided = true
            ring.geometry?.firstMaterial = rm
            ring.eulerAngles.x = -.pi / 2
            ring.opacity = 0
            ring.renderingOrder = 2
            ring.castsShadow = false
            scene.rootNode.addChildNode(ring)
            ringNodes[id] = ring
        }
        return n
    }

    // MARK: what to show

    /// The game moved on: where every die should be now.
    func apply(_ s: ArenaState) {
        want = s
        for d in s.dice where dice[d.id] == nil {
            _ = dieNode(d.id)
            dice[d.id] = DieRun(pose: Pose(p: Self.f(DiceArena.cupMouth), q: Self.q(.identity)))
        }
        for d in s.dice { if let f = d.face { dice[d.id]?.face = f } }
        if s.shaking { presimulate(count: s.dice.filter { $0.place == .cup }.count, key: "shake\(s.dice.count)") }
    }

    /// Works a throw out ahead (it doesn't depend on the faces) while the cup shakes, off the render thread.
    private func presimulate(count: Int, key: String) {
        guard count > 0, !simming, presim?.count != count else { return }
        simming = true
        let seed = UInt32(truncatingIfNeeded: Int(clock * 1000) &+ count &* 7919)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let th = DiceSim.run(count: count, seed: seed)
            self?.post { self?.presim = (count, seed, th); self?.simming = false }
        }
    }

    private func seed(_ key: String) -> UInt32 {
        var h: UInt32 = 2_166_136_261
        for b in key.utf8 { h = (h ^ UInt32(b)) &* 16_777_619 }
        return h
    }

    // MARK: every frame

    private func step() {
        guard let s = want else { return }
        let now = clock
        if first { placeAtOnce(s); first = false }
        let newRoll = s.roll != nil && s.roll != thrown
        let throwIds = newRoll ? s.dice.filter { $0.place == .tray }.map(\.id) : []
        // someone else's roll the room has already shown (Roll Call's bots roll every second or so): no cup, the dice
        // are picked up where they lie and thrown a little quicker, so the screen keeps up with the room
        // Roll Call's row always throws this way: the dice are picked up from their slots and tossed across the tray
        let quick = newRoll && !reduced && (row || (!s.mine && !s.shaking))
        if quick, let key = s.roll, !throwIds.isEmpty {
            quickThrow(key, ids: throwIds, faces: throwIds.map { s.die($0)?.face ?? 1 }, now: now)
        }

        // each die toward where it belongs
        for d in s.dice {
            guard var run = dice[d.id] else { continue }
            run.locked = { if case let .keep(_, l) = d.place { return l }; return false }()
            let toCup = d.place == .cup || (throwIds.contains(d.id) && !quick)
            let tumbling = isInThrow(d.id) && !(play?.done ?? true)
            if tumbling {
                // the room moved on mid-tumble (a new turn, a quick roll): pick it up from where it is
                if toCup { play?.left.insert(d.id); run.at = .air; run = sendToCup(run, id: d.id, now: now) }
            } else if run.tween == nil {
                if toCup {
                    if run.at != .cup { run = sendToCup(run, id: d.id, now: now) }
                } else if case let .keep(slot, _) = d.place {
                    if run.at != .keep(slot) { run = sendToKeep(run, slot: slot, slots: s.slots, now: now) }
                } else if d.place == .tray, run.at != .felt {
                    let rest = row ? slotPose(d.id, face: run.face) : run.rest ?? Pose(p: [Float(-3.0 + Double(d.id) * 1.2), 0.5, 0.2], q: Self.q(DiceArena.neat(run.face ?? 1)))
                    run.rest = rest
                    run.tween = Tween(from: run.at == .cup ? Pose(p: rest.p + [0, 0.35, 0], q: rest.q) : run.pose, to: rest, t0: now,
                                      dur: reduced ? 0.16 : 0.34, arc: reduced || run.at == .cup ? 0 : 0.8, fadeIn: run.at == .cup, end: .felt)
                    run.at = .air
                }
            }
            dice[d.id] = run
        }

        // the cup: comes for dice, shakes, pours, leaves, or rests holding them
        let cupDiceAll = s.dice.allSatisfy { $0.place == .cup }
        let gathering = dice.values.contains { $0.tween?.end == .cup }
        let needHover = gathering || s.shaking || (newRoll && !quick)
        if !reduced && tray.shelf {
            if needHover && cupRun.phase != .hover && cupRun.phase != .tipped && cupRun.tween?.then != .hover {
                moveCup(to: .hover, dur: cupRun.phase == .rest ? 0.26 : 0.3, now: now)
            } else if !needHover && cupDiceAll && cupRun.phase == .hover && cupRun.tween == nil {
                moveCup(to: .rest, dur: 0.4, now: now)
            } else if !needHover && !cupDiceAll && cupRun.phase == .rest && cupRun.tween == nil {
                moveCup(to: .away, dur: 0.4, now: now)
            }
        }

        // the throw, once its dice are all in the cup and it has shaken a moment
        if newRoll, !quick, let key = s.roll, !throwIds.isEmpty, throwIds.allSatisfy({ dice[$0]?.at == .cup && dice[$0]?.tween == nil }) {
            let shook = now - cupRun.shakeSince
            if reduced || (cupRun.phase == .hover && cupRun.tween == nil && shook >= (s.shaking ? 0.35 : 0.22)) {
                if reduced || cupRun.tipAt <= 0 {
                    if !reduced { cupRun.tipAt = now; moveCup(to: .tipped, dur: 0.18, now: now) }
                    else { pour(key, ids: throwIds, faces: throwIds.map { s.die($0)?.face ?? 1 }, now: now) }
                }
            }
            if !reduced, cupRun.tipAt > 0, now - cupRun.tipAt >= 0.16 {
                cupRun.tipAt = 0
                pour(key, ids: throwIds, faces: throwIds.map { s.die($0)?.face ?? 1 }, now: now)
            }
        }
        if cupRun.phase == .tipped, cupRun.tween == nil, let p = play, now - p.t0 > 0.3 { moveCup(to: .away, dur: 0.5, now: now) }

        advance(now)
        if tray.shelf { drawCup(now) }
        easeHomeIfDone(s, now: now)
    }

    /// The website eases back to the whole tray when you roll again, bank, Farkle or the turn ends: here, as soon as
    /// the roll the camera eased in on is no longer the one on the felt, or the cup is shaking for the next one.
    private func easeHomeIfDone(_ s: ArenaState, now: Double) {
        guard let k = easedKey, ease.to > 0 else { return }
        if s.roll != k || s.shaking || s.farkle || !s.mine || reduced {
            easeTo(0, dur: DiceArena.easeHomeSeconds, now: now)
            easedKey = nil
        }
    }

    private func isInThrow(_ id: Int) -> Bool { guard let p = play else { return false }; return p.ids.contains(id) && !p.left.contains(id) }

    private func sendToCup(_ r0: DieRun, id: Int, now: Double) -> DieRun {
        var r = r0
        if r.at == .cup || r.at == .air && r.tween?.end == .cup { return r }
        if reduced || row || dieNodes[id]?.opacity ?? 0 < 0.05 {
            r.tween = Tween(from: r.pose, to: r.pose, t0: now, dur: reduced || row ? 0.18 : 0.01, arc: 0, fadeOut: true, end: .cup)
        } else {
            let order = Double(id % 6) * 0.05
            let mouth = Pose(p: Self.f(DiceArena.cupMouth) + [0, 0.25, 0], q: r.pose.q * simd_quatf(angle: 2.2, axis: simd_normalize(SIMD3<Float>(1, 0.4, 0.3))))
            r.tween = Tween(from: r.pose, to: mouth, t0: now + 0.12 + order, dur: 0.34, arc: 1.3, fadeOut: true, end: .cup)
        }
        r.at = .air
        return r
    }

    private func sendToKeep(_ r0: DieRun, slot: Int, slots: Int, now: Double) -> DieRun {
        var r = r0
        let spot = Pose(p: Self.f(tray.keep(slot, of: slots)), q: Self.q(DiceArena.neat(r.face ?? 1)))
        if row && r.at == .felt {   // already in its own slot: it just becomes held
            r.tween = Tween(from: r.pose, to: spot, t0: now, dur: 0.12, arc: 0, end: .keep(slot))
            r.at = .air
            return r
        }
        let fromCup = r.at == .cup
        r.tween = Tween(from: fromCup ? Pose(p: spot.p + [0, 0.3, 0], q: spot.q) : r.pose, to: spot, t0: now,
                        dur: reduced || fromCup ? 0.18 : 0.36, arc: reduced || fromCup ? 0 : 0.95, fadeIn: fromCup, end: .keep(slot))
        r.at = .air
        return r
    }

    /// The cup tips and the dice pour: a simulated throw, each die turned to land on its face.
    private func pour(_ key: String, ids: [Int], faces: [Int], now: Double) {
        let th: DiceThrow
        if let p = presim, p.count == ids.count { th = p.th } else { th = DiceSim.run(count: ids.count, seed: seed(key)) }
        presim = nil
        let fixes = th.fixes(for: faces).map(Self.q)
        thrown = key
        landedKey = nil
        if reduced {
            // no tumble: each die drops a little onto its spot
            for (k, id) in ids.enumerated() {
                let rest = th.rest[k]
                let to = row ? slotPose(id, face: faces[k]) : Pose(p: Self.f(rest.p), q: Self.q(rest.q) * fixes[k])
                dice[id]?.rest = to
                dice[id]?.tween = Tween(from: Pose(p: to.p + [0, 0.35, 0], q: to.q), to: to, t0: now, dur: 0.2, arc: 0, fadeIn: true, end: .felt)
                dice[id]?.at = .air
            }
            play = Throw(th: th, ids: ids, fixes: fixes, t0: now - th.duration, key: key, hitSaid: false, done: true, awaitingTweens: true)
        } else {
            for (k, id) in ids.enumerated() {
                let rest = th.rest[k]
                dice[id]?.rest = Pose(p: Self.f(rest.p), q: Self.q(rest.q) * fixes[k])
                dice[id]?.at = .air
            }
            play = Throw(th: th, ids: ids, fixes: fixes, t0: now, key: key)
            // #716: your roll is the director's moment; its held beat lasts until the first die hits the felt
            if cinema == .director, want?.mine == true, !row {
                director.cue(strength: 0.75, lead: th.firstHit.min() ?? 0.4)
            }
        }
        moment(.pour)
    }

    /// Someone else's roll, thrown straight from where the dice lie (no cup).
    private func quickThrow(_ key: String, ids: [Int], faces: [Int], now: Double) {
        // held dice lie still in their slots: the throw bounces off them
        let held: [T3Vec] = row ? (want?.dice ?? []).compactMap { d in
            if case let .keep(slot, _) = d.place { return tray.keep(slot, of: want?.slots ?? 5) }
            return nil
        } : []
        let th = DiceSim.run(count: ids.count, seed: seed(key), maxT: row ? 1.5 : 2.4, tray: tray, still: held)
        let fixes = th.fixes(for: faces).map(Self.q)
        thrown = key
        landedKey = nil
        let lift = 0.22
        for (k, id) in ids.enumerated() {
            guard var r = dice[id] else { continue }
            let st = th.frames[0][k], rest = th.rest[k]
            let start = Pose(p: Self.f(st.p), q: Self.q(st.q) * fixes[k])
            let hidden = r.at == .cup || (dieNodes[id]?.opacity ?? 0) < 0.05
            r.tween = Tween(from: hidden ? start : r.pose, to: start, t0: now, dur: lift, arc: hidden ? 0 : 0.6, fadeIn: hidden, end: .air)
            r.rest = row ? slotPose(id, face: faces[k]) : Pose(p: Self.f(rest.p), q: Self.q(rest.q) * fixes[k])
            r.at = .air
            dice[id] = r
        }
        play = Throw(th: th, ids: ids, fixes: fixes, t0: now + lift, key: key, speed: row && want?.mine == true ? 1.15 : 1.35, allOut: true)
        moment(.pour)
    }

    /// A die in its own slot of Roll Call's row, its face up and square to the row.
    private func slotPose(_ id: Int, face: Int?) -> Pose {
        Pose(p: Self.f(tray.slot(id, of: want?.slots ?? 5)), q: Self.q(DiceArena.neat(face ?? 1)))
    }

    /// The room revealed roll `key` a while ago and the scene still hasn't landed it (build 48: Tyler couldn't keep dice,
    /// so couldn't bank): its dice go straight to where they rest and it lands now. Returns the scene's state from just
    /// before (for the UI tests), or "" when there was nothing to do (the scene moved on, or the roll has landed).
    func settleNow(_ key: String) -> String {
        guard let s = want, s.roll == key, landedKey != key else { return "" }
        let before = debugLine()
        let ids = s.dice.filter { $0.place == .tray }.map(\.id)
        if !ids.isEmpty {
            let th = DiceSim.run(count: ids.count, seed: seed(key))
            let fixes = th.fixes(for: ids.map { s.die($0)?.face ?? 1 }).map(Self.q)
            for (k, id) in ids.enumerated() {
                let rest = row ? slotPose(id, face: s.die(id)?.face) : Pose(p: Self.f(th.rest[k].p), q: Self.q(th.rest[k].q) * fixes[k])
                dice[id]?.rest = rest; dice[id]?.pose = rest; dice[id]?.at = .felt; dice[id]?.tween = nil
                dieNodes[id]?.opacity = 1
                apply(rest, to: dieNodes[id])
            }
        }
        play = nil
        thrown = key
        cupRun.tipAt = 0
        if tray.shelf && !reduced && cupRun.phase != .away { moveCup(to: .away, dur: 0.3, now: clock) }
        landed(key, ids: ids, now: clock)
        rigDirty = true
        return before
    }

    /// Everything where it belongs with no animation: the screen opened mid-game.
    private func placeAtOnce(_ s: ArenaState) {
        if let key = s.roll {
            let ids = s.dice.filter { $0.place == .tray }.map(\.id)
            if row {
                for id in ids { let p = slotPose(id, face: s.die(id)?.face); dice[id]?.rest = p; dice[id]?.pose = p; dice[id]?.at = .felt }
            } else if !ids.isEmpty {
                let th = DiceSim.run(count: ids.count, seed: seed(key))
                let fixes = th.fixes(for: ids.map { s.die($0)?.face ?? 1 }).map(Self.q)
                for (k, id) in ids.enumerated() {
                    let rest = Pose(p: Self.f(th.rest[k].p), q: Self.q(th.rest[k].q) * fixes[k])
                    dice[id]?.rest = rest; dice[id]?.pose = rest; dice[id]?.at = .felt
                }
            }
            thrown = key
            landedKey = key
            let cb = onLanded
            DispatchQueue.main.async { cb?(key) }
            // still mode: a scene that first draws after the roll arrived (a slow launch) still stops on "landed"
            moment(.landed)
        }
        for d in s.dice {
            if case let .keep(slot, _) = d.place {
                dice[d.id]?.pose = Pose(p: Self.f(tray.keep(slot, of: s.slots)), q: Self.q(DiceArena.neat(d.face ?? 1)))
                dice[d.id]?.at = .keep(slot)
            }
        }
        for (id, r) in dice { dieNodes[id]?.opacity = r.at == .cup ? 0 : 1; apply(r.pose, to: dieNodes[id]) }
        if !reduced && tray.shelf && s.dice.allSatisfy({ $0.place == .cup }) {
            cupRun.phase = .rest; cupRun.pose = cupPose(.rest); cupRun.alpha = 1
        }
    }

    // MARK: moving things

    private func advance(_ now: Double) {
        // the throw
        if var p = play, !p.done {
            let t = max(0, now - p.t0) * p.speed
            for (k, id) in p.ids.enumerated() where dice[id]?.tween == nil && !p.left.contains(id) {
                let pose = p.th.pose(k, at: t)
                let shown = Pose(p: Self.f(pose.p), q: Self.q(pose.q) * p.fixes[k])
                dice[id]?.pose = shown
                apply(shown, to: dieNodes[id])
                dieNodes[id]?.opacity = pose.out || p.allOut ? 1 : 0
            }
            if !p.hitSaid, let first = p.th.firstHit.min(), t >= first {
                p.hitSaid = true
                if want?.mine == true { let cb = onFirstHit; DispatchQueue.main.async { cb?() } }
            }
            if t >= p.th.duration {
                p.done = true
                if row {
                    // each die glides from where it stopped into its own slot; the throw lands when they're all there
                    for id in p.ids where dice[id]?.tween == nil && !p.left.contains(id) {
                        guard let from = dice[id]?.pose, let to = dice[id]?.rest else { continue }
                        dice[id]?.tween = Tween(from: from, to: to, t0: now, dur: 0.3, arc: 0.45, end: .felt)
                        dice[id]?.at = .air
                    }
                    p.awaitingTweens = true
                } else {
                    for id in p.ids where dice[id]?.tween == nil && !p.left.contains(id) {
                        if let rest = dice[id]?.rest { dice[id]?.pose = rest; apply(rest, to: dieNodes[id]) }
                        dice[id]?.at = .felt
                        dieNodes[id]?.opacity = 1
                    }
                    landed(p.key, ids: p.ids, now: now)
                }
            }
            play = p
        }
        // tweens
        for (id, var r) in dice {
            guard let tw = r.tween else { continue }
            let k = Float(max(0, min(1, (now - tw.t0) / tw.dur)))
            if now < tw.t0 { continue }
            let e = k * k * (3 - 2 * k)
            var at = tw.from.p + (tw.to.p - tw.from.p) * e
            at.y += tw.arc * sin(Float.pi * e)
            let pose = Pose(p: at, q: simd_slerp(tw.from.q, tw.to.q, e))
            r.pose = pose
            apply(pose, to: dieNodes[id])
            if tw.fadeIn { dieNodes[id]?.opacity = CGFloat(min(1, k * 2.5)) }
            if tw.fadeOut { dieNodes[id]?.opacity = CGFloat(k < 0.7 ? 1 : max(0, (1 - k) / 0.3)) }
            if k >= 1 {
                r.tween = nil
                r.at = tw.end
                if tw.end == .cup {
                    dieNodes[id]?.opacity = 0
                    if cupRun.phase == .hover { cupRun.shakeSince = max(cupRun.shakeSince, now) }
                } else { dieNodes[id]?.opacity = 1 }
                if case .keep = tw.end { moment(.kept) }
                // a throw whose dice glide or drop into place lands when the last one is there
                if let pl = play, pl.awaitingTweens, pl.ids.contains(id),
                   pl.ids.allSatisfy({ $0 == id || pl.left.contains($0) || dice[$0]?.tween == nil }) {
                    play?.awaitingTweens = false
                    if reduced && want?.mine == true { let cb = onFirstHit; DispatchQueue.main.async { cb?() } }
                    landed(pl.key, ids: pl.ids, now: now)
                }
            }
            dice[id] = r
        }
        // set-aside dice are a shade darker than the ones you just picked
        for (id, r) in dice where r.locked != r.shownLocked {
            dice[id]?.shownLocked = r.locked
            dieNodes[id]?.geometry?.materials.forEach { $0.multiply.contents = r.locked ? UIColor(white: 0.8, alpha: 1) : UIColor.white }
        }
        // a held die's ring (Roll Call's row)
        for (id, ring) in ringNodes {
            guard let r = dice[id] else { continue }
            let held: Bool = { if case .keep = r.at { return true }; if case .keep = r.tween?.end { return true }; return false }()
            let target: CGFloat = held && r.at != .cup ? 1 : 0
            ring.opacity += (target - ring.opacity) * 0.25
            ring.simdPosition = [r.pose.p.x, 0.02, r.pose.p.z]
        }
        // the light under the dice that could score, fading
        for (id, gl) in glowing {
            guard let g = glowNodes[id] else { continue }
            let t = now - gl.start
            let o: Double = t < 0 ? 0 : t < 0.3 ? t / 0.3 : t < 0.8 ? 1 : max(0, 1 - (t - 0.8) / 0.9)
            g.opacity = CGFloat(o * gl.peak)
            if let p = dice[id]?.pose.p { g.simdPosition = [p.x, 0.035, p.z] }
            if t > 1.8 || dice[id]?.at != .felt { glowing[id] = nil; g.opacity = 0 }
        }
    }

    private func landed(_ key: String, ids: [Int], now: Double) {
        landedKey = key
        // build 45: like the website's Hot Dice, your own roll eases the camera in toward where the dice came to rest,
        // and it holds there while you pick (no bounce back); see easeHomeIfDone. Never for someone else's roll, a
        // Farkle, Roll Call's row, Reduce Motion, or a view the player has moved themselves.
        if !reduced && !row && user == Rig(), let s = want, s.roll == key, s.mine, !s.farkle, let b = base {
            let ps = ids.compactMap { dice[$0]?.pose.p }.map(Self.t3)
            let cam = Table3DCamera.lookAt(eye: Self.t3(b.eye), target: Self.t3(b.target), fovY: b.fov, width: b.w, height: b.h)
            let e = DiceArena.easeIn(camera: cam, tray: tray, dice: ps, slots: s.slots, top: baseTop)
            if e.k < 1 {
                easeTo(1, dur: DiceArena.easeInSeconds, now: now)
                easeLook = Self.f(e.look); easeK = Float(e.k); easedKey = key; easeDice = (ps, s.slots)
            }
        }
        let cb = onLanded
        DispatchQueue.main.async { cb?(key) }
        guard let s = want, s.roll == key else { moment(.landed); return }
        // #716: your Farkle lands with a harder knock (no held beat: it's only known once the dice are down)
        if cinema == .director, s.mine, s.farkle, !row { director.cue(strength: 0.9, lead: 0) }
        let lit = s.farkle ? Set(ids) : s.scoring
        for id in lit {
            guard let g = glowNodes[id] else { continue }
            g.geometry?.firstMaterial?.diffuse.contents = s.farkle ? glowEmber : glowGold
            glowing[id] = (start: now + 0.05, peak: s.farkle ? 0.7 : 0.85)
        }
        moment(.landed)
    }

    // MARK: the cup

    private func cupPose(_ phase: CupPhase) -> Pose {
        let up = simd_quatf(angle: 0, axis: [0, 1, 0])
        switch phase {
        case .away: return Pose(p: Self.f(DiceArena.cupMouth) + [0.6, 7.5, -1.5], q: up)
        case .hover: return Pose(p: Self.f(DiceArena.cupMouth) + [0, 0.25, 0], q: up)
        case .rest: return Pose(p: Self.f(DiceArena.cupRest) + [0, Float(DiceArena.cupHeight), 0], q: up)
        case .tipped: return Pose(p: Self.f(DiceArena.cupMouth) + [0, -0.05, 0.15], q: simd_quatf(angle: 1.65, axis: [1, 0, 0]))
        }
    }

    private func moveCup(to phase: CupPhase, dur: Double, now: Double) {
        var from = cupRun.pose
        if cupRun.phase == .away && cupRun.tween == nil { from = cupPose(.away) }
        cupRun.tween = (from: from, to: cupPose(phase), fromAlpha: cupRun.alpha, toAlpha: phase == .away ? 0 : 1, t0: now, dur: dur, then: phase)
    }

    private func drawCup(_ now: Double) {
        if let tw = cupRun.tween {
            let k = Float(max(0, min(1, (now - tw.t0) / tw.dur))), e = k * k * (3 - 2 * k)
            cupRun.pose = Pose(p: tw.from.p + (tw.to.p - tw.from.p) * e, q: simd_slerp(tw.from.q, tw.to.q, e))
            cupRun.alpha = tw.fromAlpha + (tw.toAlpha - tw.fromAlpha) * min(1, k * (tw.toAlpha > tw.fromAlpha ? 3 : 1))
            if k >= 1 {
                cupRun.tween = nil
                cupRun.phase = tw.then
                if tw.then == .hover { cupRun.shakeSince = now }
            }
        }
        var p = cupRun.pose.p, q = cupRun.pose.q
        // shaking: dice inside, hovering, before the pour
        let inside = dice.values.contains { $0.at == .cup } && (want?.dice.contains { $0.place == .cup || $0.place == .tray } ?? false)
        if cupRun.phase == .hover, cupRun.tween == nil, inside, !reduced, want?.shaking == true || (want?.roll != nil && want?.roll != thrown) {
            let t = Float(now - cupRun.shakeSince)
            p += [0.10 * sin(t * 44), 0.07 * sin(t * 57 + 1), 0.05 * sin(t * 31)]
            q = q * simd_quatf(angle: 0.10 * sin(t * 39), axis: [0, 0, 1]) * simd_quatf(angle: 0.08 * sin(t * 51 + 0.5), axis: [1, 0, 0])
        }
        cup.simdPosition = p
        cup.simdOrientation = q
        cup.opacity = CGFloat(reduced ? 0 : cupRun.alpha)
        cup.isHidden = reduced || cupRun.alpha < 0.01
    }

    // MARK: telling the screen where the dice are

    private func publishSpots() {
        guard let s = want, let cam = liveCam else { return }
        var spots: [Int: DiceSpot] = [:]
        for d in s.dice {
            guard let r = dice[d.id] else { continue }
            var p = DiceArena.cupMouth, shown = false
            switch r.at {
            case .felt: p = Self.t3(r.pose.p); shown = true
            case let .keep(slot): p = tray.keep(slot, of: s.slots); shown = true
            case .cup: break
            case .air:
                if let tw = r.tween {
                    switch tw.end {
                    case .felt, .keep: p = Self.t3(tw.to.p); shown = true
                    default: break
                    }
                } else if let rest = r.rest, isInThrow(d.id) { p = Self.t3(rest.p); shown = true }
            }
            let top = p + T3Vec(0, DiceArena.half, 0)
            let at = cam.project(top)
            // whole points: the overlay only moves when a die moves on screen
            spots[d.id] = DiceSpot(p: p, shown: shown, screen: CGPoint(x: at.x.rounded(), y: at.y.rounded()),
                                   size: DiceArena.tapSide(pointsPerUnit: cam.pointsPerUnit(at: top)))
        }
        spotFrame += 1
        if spots != lastSpots && (spotFrame % 2 == 0 || !rigDirty) {
            lastSpots = spots
            let cb = onSpots
            DispatchQueue.main.async { cb?(spots) }
        }
    }

    // MARK: the camera (#523): the fitted view, what the player has done to it, a lean-in when dice land

    struct Rig: Equatable {
        var zoom: Float = 1, yaw: Float = 0, tilt: Float = 0
        var pan = SIMD2<Float>(0, 0)
    }
    private var base: (eye: SIMD3<Float>, target: SIMD3<Float>, fov: Double, w: Double, h: Double)?
    private var user = Rig(), shownRig = Rig()
    /// Build 45: the ease-in after your roll (0 is the fitted view, 1 eased in on `easeLook` at `easeK` of the
    /// fitted distance), as a tween from `from` to `to`.
    private var ease = (from: 0.0, to: 0.0, t0: 0.0, dur: 0.5)
    private var easeLook = SIMD3<Float>(0, 0, 0), easeK: Float = 1
    private var easedKey: String?
    /// The dice the ease-in was worked out for (and the keep row's size), to work it out again for a new view size.
    private var easeDice: (dice: [T3Vec], slots: Int) = ([], 6)
    /// The band of words over the top of the view (the dice stay below it when the camera eases in).
    private var baseTop = 0.0
    private(set) var rigDirty = true
    private var liveCam: Table3DCamera?
    private var spotFrame = 0
    static let zoomRange: ClosedRange<Float> = 1...2.8

    /// The fitted camera for the view's size (render thread). `top` is the band of words over the top of it.
    func setBase(_ cam: Table3DCamera, top: Double = 0) {
        base = (Self.f(cam.eye), Self.f(tray.target), cam.fovY, cam.width, cam.height)
        baseTop = top
        // a new size (a line of words came or went): work the eased-in view out again for it, so it holds
        if ease.to > 0 {
            let e = DiceArena.easeIn(camera: cam, tray: tray, dice: easeDice.dice, slots: easeDice.slots, top: top)
            if e.k < 1 { easeLook = Self.f(e.look); easeK = Float(e.k) } else { easeTo(0, dur: 0.01, now: clock); easedKey = nil }
        }
        rigDirty = true
    }

    /// How far eased in the camera is now (0 to 1).
    private func easeAmount(_ now: Double) -> Double {
        let k = ease.dur <= 0 ? 1 : (now - ease.t0) / ease.dur
        return ease.from + (ease.to - ease.from) * DiceArena.easeInOut(k)
    }

    private func easeTo(_ to: Double, dur: Double, now: Double) {
        let at = easeAmount(now)
        ease = (at, to, now, reduced ? 0 : dur)
        rigDirty = true
        let on = to > 0
        if on != easedSaid { easedSaid = on; let cb = onEased; DispatchQueue.main.async { cb?(on) } }
    }
    func zoom(by k: Float) {
        user.zoom = min(Self.zoomRange.upperBound, max(Self.zoomRange.lowerBound, user.zoom * k))
        rigDirty = true
        noteMoved()
    }
    /// One finger: turn round the tray and tip toward or away from it (points dragged).
    func orbit(dx: Float, dy: Float) {
        user.yaw = min(0.75, max(-0.75, user.yaw - dx * 0.006))
        user.tilt = min(0.32, max(-0.4, user.tilt + dy * 0.004))
        rigDirty = true
        noteMoved()
    }
    /// Two fingers: slide the view (points dragged); the middle of the view never leaves the tray.
    func pan(dx: Float, dy: Float) {
        guard let c = liveCam, let b = base else { return }
        let ppu = Float(max(1, c.pointsPerUnit(at: Self.t3(b.target))))
        let wx = -dx / ppu, wz = -dy / ppu, yw = shownRig.yaw
        var p = user.pan + SIMD2<Float>(wx * cos(yw) + wz * sin(yw), -wx * sin(yw) + wz * cos(yw))
        p.x = min(Float(tray.x) - b.target.x, max(-Float(tray.x) - b.target.x, p.x))
        p.y = min(Float(tray.outerZ1) - b.target.z, max(Float(tray.zBack) - b.target.z, p.y))
        user.pan = p
        rigDirty = true
        noteMoved()
    }
    /// Double-tap or the reset button: back to the whole tray (the ease-in too).
    func resetView() {
        user = Rig()
        if reduced { shownRig = user }
        if ease.to > 0 { easeTo(0, dur: DiceArena.easeHomeSeconds, now: clock); easedKey = nil }
        rigDirty = true
        noteMoved()
    }

    private func noteMoved() {
        let m = user != Rig()
        guard m != movedSaid else { return }
        movedSaid = m
        let cb = onMoved
        DispatchQueue.main.async { cb?(m) }
    }

    private func aimCamera(_ dt: Double) {
        guard let b = base else { return }
        let k = reduced || dt <= 0 ? 1 : Float(1 - exp(-14 * dt))
        shownRig.zoom += (user.zoom - shownRig.zoom) * k
        shownRig.yaw += (user.yaw - shownRig.yaw) * k
        shownRig.tilt += (user.tilt - shownRig.tilt) * k
        shownRig.pan += (user.pan - shownRig.pan) * k
        // the ease-in after your roll: same angle, toward easeLook, easeK of the distance (the player's own pinch,
        // turn and slide sit on top of it)
        let easing = clock < ease.t0 + ease.dur
        let a = Float(easeAmount(clock))
        let o = b.eye - b.target, d = simd_length(o)
        let pitch0 = asin(o.y / d), yaw0 = atan2(o.x, o.z)
        let target = b.target + SIMD3<Float>(shownRig.pan.x, 0, shownRig.pan.y) + (easeLook - b.target) * a
        let pitch = min(1.5, max(0.42, pitch0 + shownRig.tilt)), yaw = yaw0 + shownRig.yaw
        let dist = d * (1 + (easeK - 1) * a) / shownRig.zoom
        let eye = target + dist * SIMD3<Float>(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw))
        // #716: the director's push-in moves the eye along its line of sight (the spots on the screen follow it); its
        // shake turns the camera on top (mostly roll) and isn't followed, so a tap still lands on the die it meant
        let pushed = target + (eye - target) * (1 - 0.12 * Float(shot.push))
        cameraNode.simdPosition = pushed
        cameraNode.simdLook(at: target)
        cameraNode.camera?.fieldOfView = CGFloat(b.fov)
        liveCam = Table3DCamera.lookAt(eye: Self.t3(pushed), target: Self.t3(target), fovY: b.fov, width: b.w, height: b.h)
        if shot.roll != 0 || shot.yaw != 0 || shot.pitch != 0 {
            let q = cameraNode.simdOrientation
            let right = q.act([1, 0, 0]), up = q.act([0, 1, 0])
            cameraNode.simdPosition = pushed + (right * Float(shot.shiftX) + up * Float(shot.shiftY)) * simd_length(pushed - target) * 0.01
            cameraNode.simdOrientation = q * simd_quatf(angle: Float(shot.yaw), axis: [0, 1, 0])
                * simd_quatf(angle: Float(shot.pitch), axis: [1, 0, 0]) * simd_quatf(angle: Float(shot.roll), axis: [0, 0, 1])
        }
        let settled = abs(shownRig.zoom - user.zoom) < 0.001 && abs(shownRig.yaw - user.yaw) < 0.0005
            && abs(shownRig.tilt - user.tilt) < 0.0005 && simd_length(shownRig.pan - user.pan) < 0.001
        if settled { shownRig = user }
        rigDirty = !settled || easing
        publishSpots()
    }

    // MARK: small helpers

    private func apply(_ pose: Pose, to node: SCNNode?) {
        node?.simdPosition = pose.p
        node?.simdOrientation = pose.q
    }
    static func f(_ v: T3Vec) -> SIMD3<Float> { SIMD3<Float>(Float(v.x), Float(v.y), Float(v.z)) }
    static func t3(_ v: SIMD3<Float>) -> T3Vec { T3Vec(Double(v.x), Double(v.y), Double(v.z)) }
    static func q(_ d: DQuat) -> simd_quatf { simd_quatf(ix: Float(d.x), iy: Float(d.y), iz: Float(d.z), r: Float(d.w)) }

    static func material(_ img: UIImage?, specular: CGFloat, shine: CGFloat, scale: Float) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .blinn
        m.diffuse.contents = img
        m.diffuse.wrapS = .repeat; m.diffuse.wrapT = .repeat
        m.diffuse.mipFilter = .linear
        if scale != 1 { m.diffuse.contentsTransform = SCNMatrix4MakeScale(scale, scale, 1) }
        m.specular.contents = UIColor(white: specular, alpha: 1)
        m.shininess = shine
        return m
    }
}

/// Where a die is for the screen: its center in the world, whether it's out of the cup, and where its top is on the
/// screen (points) with how big it looks there.
struct DiceSpot: Equatable { var p: T3Vec; var shown: Bool; var screen: CGPoint = .zero; var size: Double = 44 }
