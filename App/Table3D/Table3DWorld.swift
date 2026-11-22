import SceneKit
import UIKit
import Metal
import simd
import T2PCore

/// The uniforms every scene shader reads (Table3DShaders.metal, T3DU). All float4, so Swift and Metal agree on layout.
struct T3DUniforms {
    var from = SIMD4<Float>(0, 1, 0, 0)
    var to = SIMD4<Float>(0, 1, 0, 0)
    var w = SIMD4<Float>(0, 1, 0, 0)
    var cam = SIMD4<Float>(0, 3, 11, 0)
    var a = SIMD4<Float>(0, 1, 1, 0)        // time, mix, wipe, flash
    var b = SIMD4<Float>(1.7, 0, -2.6, 0)   // seed, turn, ground, reduced
    var c = SIMD4<Float>(0, 0, 600, 70)     // grow, bolt, focal, max particle size
    var d = SIMD4<Float>(0, 0, 0, 0)        // particle opacity per element
    var e = SIMD4<Float>(0, 1, 0, 1)        // the arrows: the arc's from (rim s), its span, the chevrons' phase, the way they point
    var f = SIMD4<Float>(0.8, 0.8, 0.8, 0)  // the arrows: the suit's color, on (0 to 1)
    var g = SIMD4<Float>(-1, 0, 0, 0)       // the arrows: a Reverse's sweep (-1 none), where it started; -1: #719's "before" only
}

/// How much the scene draws: the effects step down on older phones (and again if frames run long).
enum T3DTier: Int, Comparable {
    case low, mid, high
    static func < (a: T3DTier, b: T3DTier) -> Bool { a.rawValue < b.rawValue }

    /// iPhone 12 class (A14, Metal's Apple 7 family) and newer draw everything; A13 a little less; older, the least.
    static var device: T3DTier {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-t2p-3d-tier"), i + 1 < args.count {
            switch args[i + 1] { case "low": return .low; case "mid": return .mid; default: return .high }
        }
        #if targetEnvironment(simulator)
        return .high
        #else
        guard let d = MTLCreateSystemDefaultDevice() else { return .low }
        var t: T3DTier = d.supportsFamily(.apple7) ? .high : d.supportsFamily(.apple6) ? .mid : .low
        if ProcessInfo.processInfo.isLowPowerModeEnabled && t > .low { t = T3DTier(rawValue: t.rawValue - 1) ?? .low }
        return t
        #endif
    }
}

/// The Overdraft table in SceneKit (#496): the glass table, the piles, the seats' hands, the turn flow, the element
/// scene round it (sky, ground, particles, grass, lightning, an optional painted backdrop per suit), and cards in the
/// air. Everything in the scene changes on the table's own clock thread (`tick`, from a SceneTicker; Nov 18,
/// wayloncore/tyleralocke#571): SceneKit's render callback sometimes stopped after a frame and the table froze, cards
/// in mid-air. Other threads `post` changes. The render callback now only times frames, for stepping down.
final class Table3DWorld: NSObject, SCNSceneRendererDelegate, SceneTicking {
    static let suits = ["ember", "wave", "bolt", "leaf"]   // the uniforms' element order
    let scene = SCNScene()
    let cameraNode = SCNNode()
    private(set) var tier: T3DTier
    var reduced = false

    private var u = T3DUniforms()
    /// The uniforms as the last frame left them, for the shaders (read on SceneKit's render thread).
    private var uShown = T3DUniforms()
    private let uLock = NSLock()
    private let lock = NSLock()
    private var pending: [() -> Void] = []
    private var lastTime: TimeInterval?

    // the clock: `clock` is real seconds since the table opened; `freezeAt` stops everything there (screenshots)
    private(set) var clock: Double = 0
    var freezeAt: Double?
    var onFrozen: (() -> Void)?
    private var frozenSaid = false
    /// Things scheduled on the scene's clock (still mode).
    private var timers: [(at: Double, run: () -> Void)] = []

    // the scene
    private let tableRoot = SCNNode(), pileNode = SCNNode(), deckNode = SCNNode(), handsNode = SCNNode()
    private var rimLine: SCNMaterial?
    private var boltNode = SCNNode()
    private var grassNode: SCNNode?
    private var addParts: SCNNode?, leafParts: SCNNode?
    private var backdrops: [String: SCNNode] = [:]
    private let ambient = SCNLight(), key = SCNLight(), fill = SCNLight(), flashLight = SCNLight()
    private var cardGeometry: SCNGeometry!
    private var blob: UIImage?

    // the game as the scene shows it
    private(set) var layout: Table3DLayout?
    private var seatHands: [SCNNode] = []
    private var shownCounts: [Int] = [], targetCounts: [Int] = [], inbound: [Int] = []
    private var pile: [(k: Int, node: SCNNode)] = []
    private var pileWanted: [(k: Int, art: String)] = []
    private var flyingK: Set<Int> = []
    private var deckShown = Table3D.deckCards
    private var suit = "wave"
    private var sceneSuit: String?
    private var turnTarget: Float = 0
    /// The storm: time since the last strike, time to the next, where it hit, how bright, and when (if) it flashes twice.
    private var storm = (t: 99.0, next: 1.2, x: 0.0, k: 1.0, twice: -1.0)
    private var flow = Flow()
    /// Still mode: the still's Reverse holds, so the table's own sync doesn't undo it.
    var flowPinned = false
    private var frameTimes: [Double] = []
    private var stepDowns = 0
    var autoStepDown = true
    var onStepDown: ((Int) -> Void)?
    /// The wall clock at the start of this frame (for the flights' safety net).
    private var wall: Double = 0
    /// How many cards the safety net put where they belong, and how many frames have run.
    private var rescued = 0, frames = 0
    /// A card still in the air this long after it should have landed is put where it belongs (Nov 18, #571).
    static let safetyNet = 6.0
    /// UI tests (-t2p-arena-debug): the table's own state in one line, about twice a second.
    var onDebug: ((String) -> Void)?
    private var debugAt = 0.0

    init(tier: T3DTier) {
        self.tier = tier
        super.init()
        build()
        uShown = u
    }

    // MARK: talking to the render thread

    /// Runs a change on the render thread, before the next frame.
    func post(_ f: @escaping () -> Void) { lock.lock(); pending.append(f); lock.unlock() }

    /// Runs a change at a time on the scene's clock (render thread; still mode).
    func addTimer(_ at: Double, _ f: @escaping () -> Void) { timers.append((at, f)) }

    /// Runs a change on the scene's clock, `after` seconds from now (still mode).
    func at(_ after: Double, _ f: @escaping () -> Void) { post { [weak self] in guard let s = self else { return }; s.timers.append((s.clock + after, f)) } }

    /// SceneKit's render callback: it only times frames now (stepping down when they run long). The scene moves in tick.
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        watchFrames(time)
        if Self.fpsOn { meterFrame(time) }
    }

    // #719: the frame rate the table really draws at, for the before-and-after comparison. Only with -t2p-fps (and
    // -t2p-arena-debug, whose line carries it): frames drawn over the last two seconds, and the longest frame.
    static let fpsOn = ProcessInfo.processInfo.arguments.contains("-t2p-fps")
    private var fpsStart: TimeInterval?, fpsLast: TimeInterval?, fpsCount = 0, fpsWorstNow = 0.0
    private var fpsShown = (0.0, 0.0)
    private func meterFrame(_ time: TimeInterval) {
        if let l = fpsLast { fpsWorstNow = max(fpsWorstNow, time - l) }
        fpsLast = time
        guard let s = fpsStart else { fpsStart = time; fpsCount = 0; return }
        fpsCount += 1
        if time - s >= 2 {
            let shown = (Double(fpsCount) / (time - s), fpsWorstNow * 1000)
            lock.lock(); fpsShown = shown; lock.unlock()
            fpsStart = time; fpsCount = 0; fpsWorstNow = 0
        }
    }

    /// One frame (the SceneTicker's thread): what was posted, the timers, then the table.
    func tick(_ time: TimeInterval) {
        wall = time
        lock.lock(); let work = pending; pending = []; lock.unlock()
        work.forEach { $0() }
        // a still (screenshots) keeps real time even when a slow simulator draws few frames, so it settles on time
        var dt = min(freezeAt == nil ? 0.05 : 0.25, max(0, time - (lastTime ?? time)))
        if lastTime == nil { dt = 1.0 / 60 }
        lastTime = time
        if let f = freezeAt {
            if clock >= f {
                dt = 0
                if !frozenSaid { frozenSaid = true; let cb = onFrozen; DispatchQueue.main.async { cb?() } }
            } else { dt = min(dt, f - clock) }
        }
        clock += dt
        let due = timers.filter { $0.at <= clock }
        timers.removeAll { $0.at <= clock }
        due.forEach { $0.run() }
        step(dt)
        uLock.lock(); uShown = u; uLock.unlock()
        frames += 1
        if let cb = onDebug, time - debugAt >= 0.5 {
            debugAt = time
            var line = "frames=\(frames) flights=\(flights.count) rescued=\(rescued) clk=\(String(format: "%.1f", clock))"
            if Self.fpsOn { lock.lock(); let f = fpsShown; lock.unlock(); line += String(format: " fps=%.1f worstms=%.0f", f.0, f.1) }
            DispatchQueue.main.async { cb(line) }
        }
    }

    // MARK: building the scene

    private func build() {
        let cam = SCNCamera()
        cam.projectionDirection = .vertical
        cam.fieldOfView = 60
        cam.zNear = 0.1; cam.zFar = 600
        cameraNode.camera = cam
        scene.rootNode.addChildNode(cameraNode)
        scene.background.contents = UIColor(red: 0.04, green: 0.04, blue: 0.07, alpha: 1)

        // lights (the prototype's, scaled for SceneKit's Lambert lighting)
        ambient.type = .ambient; ambient.intensity = 330
        let ambientNode = SCNNode(); ambientNode.light = ambient; scene.rootNode.addChildNode(ambientNode)
        key.type = .directional; key.intensity = 730
        let keyNode = SCNNode(); keyNode.light = key; keyNode.simdPosition = [-4.5, 9, 5.5]; keyNode.simdLook(at: .zero)
        scene.rootNode.addChildNode(keyNode)
        fill.type = .directional; fill.intensity = 290
        let fillNode = SCNNode(); fillNode.light = fill; fillNode.simdPosition = [5, 3.5, -4]; fillNode.simdLook(at: .zero)
        scene.rootNode.addChildNode(fillNode)
        flashLight.type = .directional; flashLight.intensity = 0; flashLight.color = UIColor(red: 0.74, green: 0.56, blue: 1, alpha: 1)   // #610: violet
        let flashNode = SCNNode(); flashNode.light = flashLight; flashNode.simdPosition = [-1, 9, 4]; flashNode.simdLook(at: .zero)
        scene.rootNode.addChildNode(flashNode)

        // the element: sky dome, ground, particles, grass, lightning
        let sky = SCNNode(geometry: SCNSphere(radius: 200))
        (sky.geometry as? SCNSphere)?.segmentCount = 32
        sky.geometry?.firstMaterial = programMaterial("t3d_sky_vert", "t3d_sky_frag") { m in
            m.cullMode = .front; m.writesToDepthBuffer = false; m.readsFromDepthBuffer = false
        }
        sky.renderingOrder = -10
        scene.rootNode.addChildNode(sky)

        let ground = SCNNode(geometry: SCNPlane(width: 700, height: 700))
        ground.geometry?.firstMaterial = programMaterial("t3d_world_vert", "t3d_ground_frag") { $0.isDoubleSided = true }
        ground.eulerAngles.x = -.pi / 2
        ground.simdPosition = [0, Float(u.b.z), 0]
        ground.renderingOrder = -5
        scene.rootNode.addChildNode(ground)

        for s in Self.suits {
            guard let img = Art.image("od3d-backdrop-\(s)") else { continue }   // painted skies Tyler may add later
            let m = SCNMaterial(); m.lightingModel = .constant; m.diffuse.contents = img
            m.writesToDepthBuffer = false; m.readsFromDepthBuffer = false; m.transparency = 0
            let n = SCNNode(geometry: SCNPlane(width: 360, height: 120)); n.geometry?.firstMaterial = m
            n.simdPosition = [0, 46, -170]; n.renderingOrder = -9; n.isHidden = true
            scene.rootNode.addChildNode(n); backdrops[s] = n
        }

        buildParticles()
        buildGrass()
        boltNode.renderingOrder = 4
        boltNode.isHidden = true
        scene.rootNode.addChildNode(boltNode)

        // the glass table
        buildGlass()
        scene.rootNode.addChildNode(tableRoot)

        // cards
        cardGeometry = Self.makeCardGeometry()
        blob = Self.blobImage()
        for (node, at) in [(deckNode, Table3D.deckAt), (pileNode, Table3D.pileAt)] {
            node.simdPosition = [Float(at.x), Float(at.y), Float(at.z + Table3D.cardH / 2 + 0.06)]
            let sh = SCNNode(geometry: SCNPlane(width: Table3D.cardW * 1.75, height: Table3D.cardH * 1.6))
            sh.geometry?.firstMaterial = blobMaterial(0.9)
            sh.eulerAngles.x = -.pi / 2
            sh.simdPosition = [0.05, 0.002, Float(-Table3D.cardH / 2 - 0.02)]
            sh.renderingOrder = 1
            node.addChildNode(sh)
            scene.rootNode.addChildNode(node)
        }
        for i in 0..<Table3D.deckCards {
            let c = card("card_back")
            c.simdOrientation = yaw(Float(Table3D.jitter(i, 9) - 0.5) * 0.07) * Self.faceDown
            c.simdPosition = [Float(Table3D.jitter(i, 4) - 0.5) * 0.024, Float(Table3D.cardT / 2 + Double(i) * Table3D.cardT),
                              Float(-Table3D.cardH / 2 - 0.06 + (Table3D.jitter(i, 5) - 0.5) * 0.024)]
            deckNode.addChildNode(c)
        }
        scene.rootNode.addChildNode(handsNode)
        buildFlow()
        applyElement(0)
    }

    private func programMaterial(_ v: String, _ f: String, opaque: Bool = true, _ setup: (SCNMaterial) -> Void = { _ in }) -> SCNMaterial {
        let p = SCNProgram()
        p.vertexFunctionName = v
        p.fragmentFunctionName = f
        p.isOpaque = opaque
        p.handleBinding(ofBufferNamed: "u", frequency: .perFrame) { [weak self] stream, _, _, _ in
            guard let self else { return }
            self.uLock.lock(); var u = self.uShown; self.uLock.unlock()
            stream.writeBytes(&u, count: MemoryLayout<T3DUniforms>.stride)
        }
        let m = SCNMaterial()
        m.program = p
        setup(m)
        return m
    }

    private func blobMaterial(_ alpha: CGFloat) -> SCNMaterial {
        let m = SCNMaterial(); m.lightingModel = .constant; m.diffuse.contents = blob
        m.transparency = alpha; m.writesToDepthBuffer = false; m.blendMode = .alpha
        return m
    }

    /// Sweeps a profile of (k, y) points round the stadium (k = 1 is the play surface's edge, 0 its center line).
    private static func sweep(_ profile: [(Double, Double)], uv: Bool = false) -> SCNGeometry {
        let N = 184, M = profile.count
        var pos: [Float] = [], tex: [Float] = [], idx: [UInt32] = []
        for i in 0...N {
            for j in 0..<M {
                let p = Table3D.rimPoint(Double(i) / Double(N) * Table3D.perim, profile[j].0)
                pos += [Float(p.x), Float(profile[j].1), Float(p.z)]
                tex += [Float(i) / Float(N) * 8, 1 - Float(j) / Float(max(1, M - 1))]
            }
        }
        for i in 0..<N { for j in 0..<(M - 1) {
            let a = UInt32(i * M + j), b = UInt32((i + 1) * M + j)
            idx += [a, b, a + 1, b, b + 1, a + 1]
        } }
        var sources = [source(pos, .vertex, 3)]
        if uv { sources.append(source(tex, .texcoord, 2)) }
        return SCNGeometry(sources: sources, elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
    }

    static func source(_ f: [Float], _ semantic: SCNGeometrySource.Semantic, _ comps: Int) -> SCNGeometrySource {
        let data = f.withUnsafeBufferPointer { Data(buffer: $0) }
        return SCNGeometrySource(data: data, semantic: semantic, vectorCount: f.count / comps, usesFloatComponents: true,
                                 componentsPerVector: comps, bytesPerComponent: 4, dataOffset: 0, dataStride: 4 * comps)
    }

    private func buildGlass() {
        let rim = Table3D.rim, gt = Table3D.glassT
        let top = SCNNode(geometry: Self.sweep([(0, 0), (rim, 0)]))
        top.geometry?.firstMaterial = programMaterial("t3d_world_vert", "t3d_glass_frag") { $0.isDoubleSided = true }
        tableRoot.addChildNode(top)
        let edge = SCNNode(geometry: Self.sweep([(rim, 0), (rim - 0.012, -gt)], uv: true))
        edge.geometry?.firstMaterial = programMaterial("t3d_worlduv_vert", "t3d_edge_frag", opaque: false) { m in
            m.isDoubleSided = true; m.blendMode = .alpha; m.writesToDepthBuffer = false
        }
        edge.renderingOrder = 3
        tableRoot.addChildNode(edge)
        let under = SCNNode(geometry: Self.sweep([(0, -gt), (rim - 0.012, -gt)]))
        let um = SCNMaterial(); um.lightingModel = .constant; um.diffuse.contents = UIColor(white: 0.02, alpha: 1)
        um.transparency = 0.35; um.isDoubleSided = true; um.writesToDepthBuffer = false
        under.geometry?.firstMaterial = um
        under.renderingOrder = 3
        tableRoot.addChildNode(under)
        let line = SCNNode(geometry: Self.sweep([(rim - 0.016, 0.002), (rim, 0.002)]))
        let lm = SCNMaterial(); lm.lightingModel = .constant; lm.diffuse.contents = UIColor.white; lm.transparency = 0.85
        lm.isDoubleSided = true; lm.writesToDepthBuffer = false
        line.geometry?.firstMaterial = lm
        line.renderingOrder = 3
        rimLine = lm
        tableRoot.addChildNode(line)
    }

    private func buildParticles() {
        let counts: [Int]
        switch tier {
        case .high: counts = [210, 100, 120, 130]
        case .mid: counts = [120, 56, 70, 76]
        case .low: counts = [56, 28, 32, 36]
        }
        func mesh(_ kinds: [(Float, Int)]) -> SCNGeometry {
            var pos: [Float] = [], t0: [Float] = [], t1: [Float] = [], idx: [UInt32] = []
            var q: UInt32 = 0
            for (kind, n) in kinds {
                for _ in 0..<n {
                    let s = (Float.random(in: 0..<1), Float.random(in: 0..<1), Float.random(in: 0..<1), Float.random(in: 0..<1))
                    for (cx, cy) in [(-1, -1), (1, -1), (1, 1), (-1, 1)] as [(Float, Float)] {
                        pos += [cx, cy, kind]; t0 += [s.0, s.1]; t1 += [s.2, s.3]
                    }
                    idx += [q, q + 1, q + 2, q, q + 2, q + 3]; q += 4
                }
            }
            let g = SCNGeometry(sources: [Self.source(pos, .vertex, 3), Self.source(t0, .texcoord, 2), Self.source(t1, .texcoord, 2)],
                                elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
            g.boundingBox = (SCNVector3(-400, -50, -400), SCNVector3(400, 100, 400))
            return g
        }
        addParts?.removeFromParentNode(); leafParts?.removeFromParentNode()
        let add = SCNNode(geometry: mesh([(0, counts[0]), (1, counts[1]), (2, counts[2])]))
        add.geometry?.firstMaterial = programMaterial("t3d_part_vert", "t3d_part_add_frag", opaque: false) { m in
            m.blendMode = .add; m.writesToDepthBuffer = false; m.isDoubleSided = true
        }
        add.renderingOrder = 5
        let leaf = SCNNode(geometry: mesh([(3, counts[3])]))
        leaf.geometry?.firstMaterial = programMaterial("t3d_part_vert", "t3d_part_frag", opaque: false) { m in
            m.blendMode = .alpha; m.writesToDepthBuffer = false; m.isDoubleSided = true
        }
        leaf.renderingOrder = 5
        scene.rootNode.addChildNode(add); scene.rootNode.addChildNode(leaf)
        addParts = add; leafParts = leaf
    }

    private func buildGrass() {
        grassNode?.removeFromParentNode(); grassNode = nil
        // one mesh for the whole meadow (one draw): most blades beside the table, where the aerial camera looks past
        // its sides (near grass, a little taller), the rest in the field out past the far end
        let n = tier == .high ? 14000 : tier == .mid ? 6000 : 0
        guard n > 0 else { return }
        var pos: [Float] = [], off: [Float] = [], r0: [Float] = [], r1: [Float] = [], idx: [UInt32] = []
        let shape: [(Float, Float)] = [(-0.5, 0), (0.5, 0), (-0.5, 0.5), (0.5, 0.5), (0, 1)]
        for i in 0..<n {
            var x: Float, z: Float, tall: Float = 1
            if Float.random(in: 0..<1) < 0.68 {
                let side: Float = Bool.random() ? 1 : -1
                x = side * (3.0 + 11 * pow(Float.random(in: 0..<1), 1.4)); z = .random(in: -12...9)
                tall = 1.15 + 0.25 * Float.random(in: 0..<1)
            } else {
                x = .random(in: -30...30); z = -9.5 - 40 * pow(Float.random(in: 0..<1), 1.3)
            }
            let r = (Float.random(in: 0..<1), Float.random(in: 0..<1), Float.random(in: 0..<1), Float.random(in: 0..<1))
            for (sx, sy) in shape { pos += [sx, sy, 0]; off += [x, z]; r0 += [r.0, r.1]; r1 += [r.2, r.3, tall] }
            let b = UInt32(i * 5)
            idx += [b, b + 1, b + 2, b + 1, b + 3, b + 2, b + 2, b + 3, b + 4]
        }
        let g = SCNGeometry(sources: [Self.source(pos, .vertex, 3), Self.source(off, .texcoord, 2), Self.source(r0, .texcoord, 2), Self.source(r1, .normal, 3)],
                            elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
        g.boundingBox = (SCNVector3(-400, -50, -400), SCNVector3(400, 100, 400))
        g.firstMaterial = programMaterial("t3d_grass_vert", "t3d_grass_frag") { $0.isDoubleSided = true }
        let node = SCNNode(geometry: g)
        node.isHidden = true
        scene.rootNode.addChildNode(node)
        grassNode = node
    }

    // MARK: cards

    static let faceDown = simd_quatf(angle: .pi, axis: [0, 0, 1])
    func yaw(_ a: Float) -> simd_quatf { simd_quatf(angle: a, axis: [0, 1, 0]) }

    /// A thin rounded slab, face up (+Y), its top edge toward -Z: the face, the back (mirrored), the edge.
    static func makeCardGeometry() -> SCNGeometry {
        let cw = Float(Table3D.cardW), ch = Float(Table3D.cardH), th = Float(Table3D.cardT)
        let r = cw * 0.075, hw = cw / 2, hh = ch / 2, N = 5
        var out: [(Float, Float)] = []
        func corner(_ cx: Float, _ cz: Float, _ a0: Float) {
            for i in 0...N { let a = a0 + Float(i) / Float(N) * .pi / 2; out.append((cx + cos(a) * r, cz + sin(a) * r)) }
        }
        corner(hw - r, hh - r, 0); corner(-hw + r, hh - r, .pi / 2); corner(-hw + r, -hh + r, .pi); corner(hw - r, -hh + r, .pi * 1.5)
        let n = out.count, y = th / 2
        var pos: [Float] = [], nor: [Float] = [], uv: [Float] = []
        var top: [UInt32] = [], bot: [UInt32] = [], side: [UInt32] = []
        pos += [0, y, 0]; nor += [0, 1, 0]; uv += [0.5, 0.5]
        for (x, z) in out { pos += [x, y, z]; nor += [0, 1, 0]; uv += [x / cw + 0.5, z / ch + 0.5] }
        for i in 0..<n { top += [0, UInt32(1 + (i + 1) % n), UInt32(1 + i)] }
        let b0 = UInt32(pos.count / 3)
        pos += [0, -y, 0]; nor += [0, -1, 0]; uv += [0.5, 0.5]
        for (x, z) in out { pos += [x, -y, z]; nor += [0, -1, 0]; uv += [0.5 - x / cw, 0.5 + z / ch] }
        for i in 0..<n { bot += [b0, b0 + 1 + UInt32(i), b0 + 1 + UInt32((i + 1) % n)] }
        let s0 = UInt32(pos.count / 3)
        for i in 0..<n {
            let (x, z) = out[i], (x2, z2) = out[(i + 1) % n]
            var nx = z2 - z, nz = -(x2 - x); let l = max(1e-6, (nx * nx + nz * nz).squareRoot()); nx /= l; nz /= l
            pos += [x, y, z, x2, y, z2, x2, -y, z2, x, -y, z]
            for _ in 0..<4 { nor += [nx, 0, nz]; uv += [0, 0] }
            let k = s0 + UInt32(i * 4)
            side += [k, k + 1, k + 2, k, k + 2, k + 3]
        }
        return SCNGeometry(sources: [source(pos, .vertex, 3), source(nor, .normal, 3), source(uv, .texcoord, 2)],
                           elements: [SCNGeometryElement(indices: top, primitiveType: .triangles),
                                      SCNGeometryElement(indices: bot, primitiveType: .triangles),
                                      SCNGeometryElement(indices: side, primitiveType: .triangles)])
    }

    private var faceMaterials: [String: SCNMaterial] = [:]
    private lazy var edgeMaterial: SCNMaterial = {
        let m = SCNMaterial(); m.lightingModel = .lambert; m.diffuse.contents = UIColor(red: 0.80, green: 0.75, blue: 0.62, alpha: 1)
        m.isDoubleSided = true
        return m
    }()

    private func faceMaterial(_ name: String) -> SCNMaterial {
        if let m = faceMaterials[name] { return m }
        let m = SCNMaterial()
        m.lightingModel = .lambert
        let img = Self.cardImage(name)
        m.diffuse.contents = img ?? UIColor(red: 0.1, green: 0.08, blue: 0.12, alpha: 1)
        m.emission.contents = img
        m.emission.intensity = name == "card_back" ? 0.3 : 0.42
        m.diffuse.mipFilter = .linear; m.diffuse.maxAnisotropy = 8
        m.emission.mipFilter = .linear
        m.isDoubleSided = true
        faceMaterials[name] = m
        return m
    }

    /// A card's art on its own dark ground (the art's corners are clear).
    static func cardImage(_ name: String) -> UIImage? {
        guard let art = Art.image(name) else { return nil }
        let size = CGSize(width: 320, height: 489)
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1; fmt.opaque = true
        return UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            UIColor(red: 0.10, green: 0.08, blue: 0.06, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            art.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    static func blobImage() -> UIImage {
        let size = CGSize(width: 128, height: 128)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [UIColor(white: 0, alpha: 0.62).cgColor, UIColor(white: 0, alpha: 0.34).cgColor, UIColor(white: 0, alpha: 0).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.55, 1]) {
                ctx.cgContext.drawRadialGradient(g, startCenter: CGPoint(x: 64, y: 64), startRadius: 0, endCenter: CGPoint(x: 64, y: 64), endRadius: 64, options: [])
            }
        }
    }

    func card(_ name: String) -> SCNNode {
        let g = cardGeometry.copy() as! SCNGeometry
        g.materials = [faceMaterial(name), faceMaterial("card_back"), edgeMaterial]
        let n = SCNNode(geometry: g)
        n.name = name
        return n
    }

    // MARK: the game, as the scene shows it (render thread: call through post)

    /// Seats and hands for a new layout; the camera fitted to the screen.
    func setLayout(_ l: Table3DLayout, counts: [Int]) {
        layout = l
        let c = l.camera
        cameraNode.camera?.fieldOfView = CGFloat(c.fovY)
        cameraNode.simdPosition = [Float(c.eye.x), Float(c.eye.y), Float(c.eye.z)]
        let m = simd_float3x3(columns: (SIMD3<Float>(Float(c.right.x), Float(c.right.y), Float(c.right.z)),
                                        SIMD3<Float>(Float(c.up.x), Float(c.up.y), Float(c.up.z)),
                                        SIMD3<Float>(Float(c.back.x), Float(c.back.y), Float(c.back.z))))
        cameraNode.simdOrientation = simd_quatf(m)
        u.cam = [Float(c.eye.x), Float(c.eye.y), Float(c.eye.z), 0]
        u.c.z = Float(c.focal)
        if seatHands.count != l.seats.count {
            seatHands.forEach { $0.removeFromParentNode() }
            seatHands = l.seats.map { _ in
                let h = SCNNode()
                h.simdScale = SIMD3(repeating: Float(Table3D.handScale))
                let sh = SCNNode(geometry: SCNPlane(width: 4.6, height: 3.4))
                sh.geometry?.firstMaterial = blobMaterial(0.55)
                sh.eulerAngles.x = -.pi / 2
                sh.simdPosition = [0, 0.004, 0.55]
                h.addChildNode(sh)
                for _ in 0..<7 { h.addChildNode(card("card_back")) }
                handsNode.addChildNode(h)
                return h
            }
            shownCounts = counts; inbound = Array(repeating: 0, count: counts.count)
        }
        for (i, s) in l.seats.enumerated() {
            seatHands[i].simdPosition = [Float(s.handPos.x), 0, Float(s.handPos.z)]
            seatHands[i].simdOrientation = yaw(Float(s.handYaw))
        }
        setCounts(counts)
        fanAll()
    }

    /// A new hand: every seat's hand empties, and the deal fills them again as its cards land.
    func resetShown() {
        shownCounts = Array(repeating: 0, count: shownCounts.count)
        fanAll()
    }

    /// Each seat's card count; a seat with cards on their way to it catches up as they land.
    func setCounts(_ counts: [Int]) {
        targetCounts = counts
        if shownCounts.count != counts.count { shownCounts = counts }
        if inbound.count != counts.count { inbound = Array(repeating: 0, count: counts.count) }
        for i in counts.indices where inbound[i] <= 0 { shownCounts[i] = counts[i] }
        fanAll()
    }

    /// Where each seat-hand card is going (build 45: a hand that grows or shrinks eases into its new fan).
    private var fanTargets: [ObjectIdentifier: (p: SIMD3<Float>, q: simd_quatf)] = [:]

    private func fanAll() {
        for (i, h) in seatHands.enumerated() where i < shownCounts.count {
            let fan = Table3D.handFan(shownCounts[i])
            let cards = h.childNodes.filter { $0.geometry === nil || !($0.geometry is SCNPlane) }
            for (j, c) in cards.enumerated() {
                let was = c.isHidden
                c.isHidden = j >= fan.count
                if j < fan.count {
                    let p = SIMD3<Float>(Float(fan[j].x), Float(fan[j].y), Float(fan[j].z)), q = yaw(Float(fan[j].yaw)) * Self.faceDown
                    let id = ObjectIdentifier(c)
                    // a card that just appeared (or the first layout, or Reduce Motion) goes straight to its place
                    if was || reduced || fanTargets[id] == nil { c.simdPosition = p; c.simdOrientation = q }
                    fanTargets[id] = (p, q)
                }
            }
        }
    }

    /// The seats' hands ease toward their fans (render thread, each frame).
    private func stepFans(_ dt: Float) {
        guard dt > 0 else { return }
        let k = 1 - exp(-13 * dt)
        for h in seatHands {
            for c in h.childNodes where !c.isHidden {
                guard let t = fanTargets[ObjectIdentifier(c)] else { continue }
                if simd_length(t.p - c.simdPosition) < 1e-4 { continue }
                c.simdPosition += (t.p - c.simdPosition) * k
                c.simdOrientation = simd_slerp(c.simdOrientation, t.q, k)
            }
        }
    }

    /// The draw pile's height follows how many cards are left.
    func setDeck(left: Int) {
        deckShown = left <= 0 ? 0 : min(Table3D.deckCards, max(1, (left + 2) / 3))
        for (i, c) in deckNode.childNodes.filter({ !($0.geometry is SCNPlane) }).enumerated() { c.isHidden = i >= deckShown }
    }

    /// The discard pile, newest last: (place in the pile, art). A card still in the air lands on it by itself.
    func setPile(_ cards: [(k: Int, art: String)]) {
        pileWanted = Array(cards.suffix(Table3D.pileCards))
        syncPile()
    }

    private func syncPile() {
        let wanted = pileWanted.filter { !flyingK.contains($0.k) }
        let keep = Set(wanted.map(\.k))
        for p in pile where !keep.contains(p.k) { p.node.removeFromParentNode() }
        pile.removeAll { !keep.contains($0.k) }
        for w in wanted where !pile.contains(where: { $0.k == w.k }) {
            let n = card(w.art)
            pileNode.addChildNode(n)
            pile.append((w.k, n))
        }
        pile.sort { $0.k < $1.k }
        for (i, p) in pile.enumerated() {
            let lie = Table3D.pileLie(p.k)
            p.node.simdPosition = pileLocal(i, lie.dx, lie.dz)
            p.node.simdOrientation = yaw(Float(p.k == pile.last?.k ? lie.yaw * 0.3 : lie.yaw))
        }
    }

    private func pileLocal(_ i: Int, _ dx: Double, _ dz: Double) -> SIMD3<Float> {
        [Float(dx), Float(Table3D.cardT / 2 + Double(i) * Table3D.cardT + 0.001), Float(-Table3D.cardH / 2 - 0.06 + dz)]
    }

    /// The suit in play: the scene changes to it like weather (never a cut), unless `instant`.
    func setSuit(_ s: String, instant: Bool = false) {
        guard Self.suits.contains(s) else { return }
        suit = s
        if instant || sceneSuit == nil {
            let one = Self.oneHot(s)
            u.from = one; u.to = one; u.w = one; u.a.y = 1
            sceneSuit = s
            if s == "bolt" { storm.next = 2.1 }
        }
    }

    static func oneHot(_ s: String) -> SIMD4<Float> {
        var v = SIMD4<Float>(0, 0, 0, 0); v[suits.firstIndex(of: s) ?? 1] = 1; return v
    }

    /// Your turn: the rim lights up in the element's color.
    func setMyTurn(_ on: Bool) { turnTarget = on ? 1 : 0 }

    // MARK: which way play goes: the website's arrows (#719)

    /// Tyler, Nov 22 (#719): "I like the arrows that I have on Overdraft on the website. I prefer those arrows to the
    /// one that you added." So these are time2play.live's (static/live/overdraft.html: flowPlace, flowArc, flowDraw),
    /// drawn by the glass's shader (Table3DShaders.metal, turnArrows): chevrons flowing round the rim the way play
    /// goes, and a curved arrow from whoever is on to whoever is next. A Reverse uses the website's timing: the
    /// chevrons slow to a stop (0.42 s), a sweep from whoever played it runs once round the rim turning each one (from
    /// 0.3 s, for 0.95 s), and they pick up the other way (0.42 s). Reduce Motion: nothing flows or sweeps.
    private struct Flow {
        var from = 0.0, len = 1.0, dir = 1.0      // the seat in turn (rim s), the way to the next seat, play's direction
        var phase = 0.0, vel = 0.0, pointing = 1.0 // the chevrons: offset round the rim, speed, the way they point
        var rev = -1.0, revFrom = 0.0, revOld = 1.0 // seconds into a Reverse (negative: none), where it started, the old way
        var on = 0.0, target = 0.0
        var set = false
    }
    /// How fast the chevrons flow (world units a second; the website's 34 px a second on its rail).
    private static let flowSpeed = 1.0

    /// #719's frame-rate comparison only: -t2p-719-before draws the comets the app had before, at their cost.
    static let before719 = ProcessInfo.processInfo.arguments.contains("-t2p-719-before")

    private func buildFlow() {
        u.g = SIMD4<Float>(-1, 0, Self.before719 ? -1 : 0, 0)
    }

    /// Whoever is on, whoever is next (rim positions) and play's direction. A change of direction is a Reverse,
    /// started from the seat that was on. `pin` (still mode) holds it.
    func setFlow(from: Double, to: Double, dir: Int, pin: Bool = false) {
        if flowPinned && !pin { return }
        if pin { flowPinned = true }
        let d = dir >= 0 ? 1.0 : -1.0, P = Table3D.perim
        var len = ((to - from) * d).truncatingRemainder(dividingBy: P)
        if len < 0 { len += P }
        if len < 0.01 { len = P }
        flow.target = 1
        if !flow.set || flow.on < 0.05 {   // the first turn, or a new hand after the arrows faded: no Reverse to show
            flow.set = true; flow.dir = d; flow.pointing = d; flow.vel = reduced ? 0 : d * Self.flowSpeed; flow.rev = -1
            if reduced { flow.on = 1 }
        } else if d != flow.dir {
            if reduced { flow.pointing = d; flow.rev = -1 }
            else { flow.rev = 0; flow.revFrom = flow.from; flow.revOld = flow.dir }
            flow.dir = d
        }
        flow.from = from; flow.len = len
    }

    /// The hand's over: the arrows fade away.
    func hideFlow() { flow.target = 0 }

    private func stepFlow(_ dt: Double) {
        let P = Table3D.perim, V = Self.flowSpeed
        var sweep = -1.0
        if flow.rev >= 0 {
            flow.rev += dt
            let t = flow.rev, goAt = 0.3 + 0.95 - 0.12
            func ease(_ x: Double) -> Double { let c = min(1, max(0, x)); return 1 - pow(1 - c, 3) }
            if t < 0.42 { flow.vel = flow.revOld * V * (1 - ease(t / 0.42)) }
            else if t < goAt { flow.vel = 0 }
            else { flow.vel = flow.dir * V * ease((t - goAt) / 0.42) }
            sweep = max(0, min(1, (t - 0.3) / 0.95)) * (P + P * 0.05)
            if t > goAt + 0.42 { flow.rev = -1; flow.pointing = flow.dir; flow.vel = flow.dir * V; sweep = -1 }
        } else if !reduced {
            flow.vel = flow.dir * V
        }
        if !reduced { flow.phase = (flow.phase + flow.vel * dt).truncatingRemainder(dividingBy: P) }
        flow.on += max(-dt * 3, min(dt * 3, flow.target - flow.on))
        let a = (flow.from.truncatingRemainder(dividingBy: P) + P).truncatingRemainder(dividingBy: P)
        let pointing = flow.rev >= 0 ? flow.revOld : flow.pointing
        u.e = SIMD4<Float>(Float(a), Float(flow.len), Float(flow.phase), Float(pointing))
        u.g.x = Float(sweep); u.g.y = Float(flow.revFrom)
        u.f.w = Float(flow.on)
    }

    private lazy var boltMaterial: SCNMaterial = programMaterial("t3d_bolt_vert", "t3d_bolt_frag", opaque: false) { m in
        m.blendMode = .add; m.writesToDepthBuffer = false; m.isDoubleSided = true
    }

    // MARK: cards in the air

    /// A card in the air (build 45: CardMotion's pickup, flight and settle; Reduce Motion: a fade in place).
    private struct Flight {
        var node: SCNNode, shadow: SCNNode
        var p0: SIMD3<Float>, q0: simd_quatf, p1: SIMD3<Float>, q1: simd_quatf
        var dur: Float, arc: Float, spin: Float, s0: Float, s1: Float, slide: Float, settle: Float
        var t: Float
        var landed = false
        /// The pickup: how long, and where it lifts to (and how it's turned there).
        var lift: Float = 0, liftP: SIMD3<Float> = .zero, liftQ = simd_quatf(angle: 0, axis: [0, 1, 0])
        /// Where it touches down (short of p1 by the slide), how it's turned then, and how fast it's going.
        var landP: SIMD3<Float> = .zero, landQ = simd_quatf(angle: 0, axis: [0, 1, 0]), speed: Float = 0
        var dir: SIMD3<Float> = [0, 0, 1], axis: SIMD3<Float> = [1, 0, 0]
        /// The flight's curve to one side, its arrival speed (CardMotion.travel), and the touchdown's rock and turn.
        var bow: Float = 0, arrive: Float = 0, rock: Float = 0, kick: Float = 0
        var fade = false
        var onLand: (() -> Void)?, onDone: (() -> Void)?
        /// When it should be down, on the wall clock (the safety net's reference).
        var due: Double = 0
    }
    private var flights: [Flight] = []

    /// Sends a card from p0 to p1. `lift` picks it up first, `liftDir` the way it lifts (world up, or the screen's up
    /// for a card from your hand). `slide` is how far it slides on the pile after touching down (0: it eases to a stop).
    private func fly(_ node: SCNNode, p0: SIMD3<Float>, q0: simd_quatf, p1: SIMD3<Float>, q1: simd_quatf, dur: Float, arc: Float = 0.8,
                     spin: Float = 0, s0: Float = 1, s1: Float = 1, slide: Float = 0, settle: Float = Float(CardMotion.settleSeconds),
                     delay: Float = 0, lift: Float = Float(CardMotion.pickupSeconds), liftDir: SIMD3<Float> = [0, 1, 0],
                     onLand: (() -> Void)? = nil, onDone: (() -> Void)? = nil) {
        var f = Flight(node: node, shadow: SCNNode(geometry: SCNPlane(width: Table3D.cardW * 1.6, height: Table3D.cardH * 1.5)),
                       p0: p0, q0: q0, p1: p1, q1: q1, dur: dur, arc: arc, spin: spin, s0: s0, s1: s1, slide: slide,
                       settle: slide > 0 ? settle : 0, t: -delay)
        if reduced {
            // Reduce Motion: no flight, the card fades in where it ends up
            f.fade = true; f.dur = 0.22; f.lift = 0; f.settle = 0
        } else {
            var dir = SIMD3<Float>(p1.x - p0.x, 0, p1.z - p0.z)
            dir = simd_length(dir) > 1e-5 ? simd_normalize(dir) : [0, 0, 1]
            let turn: Float = spin == 0 ? (Bool.random() ? 1 : -1) : (spin > 0 ? 1 : -1)
            f.dir = dir
            f.axis = [dir.z, 0, -dir.x]
            // a spinning card turns one full time round as it flies, from none at the start (the website's and the
            // old flight started already turned by the spin, so a card jumped sideways the moment it left the hand)
            f.spin = spin == 0 ? 0 : turn * 2 * .pi
            f.lift = lift
            f.liftP = p0 + simd_normalize(liftDir) * Float(CardMotion.pickupLift) * max(0.5, s0)
            // picked up: tipped back a little and turned a hair
            f.liftQ = q0 * simd_quatf(angle: Float(CardMotion.pickupTilt), axis: [1, 0, 0]) * simd_quatf(angle: Float(CardMotion.pickupTurn) * turn, axis: [0, 0, 1])
            f.landP = p1 - dir * slide
            let dist = simd_length(f.landP - f.liftP)
            f.speed = Float(CardMotion.landingSpeed(slide: Double(slide)))
            f.arrive = Float(CardMotion.arrive(speed: Double(f.speed), distance: Double(dist), seconds: Double(dur)))
            // a slight curve to one side, the way it spins
            f.bow = 0.22 * turn * min(1, dist / 4)
            if slide > 0 {
                // it touches down a little tipped and still turning, and both die away as it settles
                f.rock = 0.07; f.kick = 0.1 * turn
            }
            f.landQ = simd_quatf(angle: f.kick, axis: [0, 1, 0]) * simd_quatf(angle: f.rock, axis: f.axis) * q1
        }
        f.onLand = onLand; f.onDone = onDone
        f.due = wall + Double(delay + f.lift + f.dur + f.settle)
        node.isHidden = true
        node.renderingOrder = 6
        scene.rootNode.addChildNode(node)
        f.shadow.geometry?.firstMaterial = blobMaterial(0.0)
        f.shadow.eulerAngles.x = -.pi / 2
        f.shadow.renderingOrder = 1
        f.shadow.isHidden = true
        scene.rootNode.addChildNode(f.shadow)
        flights.append(f)
    }

    private func stepFlights(_ dt: Float) {
        var i = flights.count - 1
        while i >= 0 {
            var f = flights[i]
            f.t += dt
            // the safety net (Nov 18, #571): a card still flying well after it should be down goes where it belongs now
            if freezeAt == nil, wall > f.due + Self.safetyNet {
                f.t = max(f.t, f.lift + f.dur + f.settle)
                rescued += 1
            }
            if f.t < 0 { flights[i] = f; i -= 1; continue }
            f.node.isHidden = false
            var done = false
            let up = f.t - f.lift, total = f.lift + f.dur + f.settle
            if f.fade {
                f.node.simdPosition = f.p1; f.node.simdOrientation = f.q1; f.node.simdScale = SIMD3(repeating: f.s1)
                f.node.opacity = CGFloat(min(1, f.t / f.dur))
                if f.t >= f.dur { if !f.landed { f.landed = true; f.onLand?() }; done = true }
            } else if f.t < f.lift {
                // the pickup: up and tipped back, slowing to a stop
                let e = Float(CardMotion.pickup(Double(f.t / f.lift)))
                f.node.simdPosition = simd_mix(f.p0, f.liftP, SIMD3(repeating: e))
                f.node.simdOrientation = simd_slerp(f.q0, f.liftQ, e)
                f.node.simdScale = SIMD3(repeating: f.s0 * (1 + 0.05 * e))
            } else if up < f.dur {
                // the flight: a gentle start, a curve up and to one side, flat by the time it lands, still moving
                let u = up / f.dur
                let h = Float(CardMotion.travel(Double(u), arrive: Double(f.arrive)))
                var p = simd_mix(f.liftP, f.landP, SIMD3(repeating: h))
                p.y += Float(CardMotion.arc(Double(u), Double(f.arc)))
                p += f.axis * (f.bow * 4 * h * (1 - h))
                var q = simd_slerp(f.liftQ, f.landQ, u * u * (3 - 2 * u))
                if f.spin != 0 { q = simd_quatf(angle: f.spin * h, axis: [0, 1, 0]) * q }
                f.node.simdPosition = p; f.node.simdOrientation = q
                let sa = f.s0 * 1.05
                f.node.simdScale = SIMD3(repeating: sa + (f.s1 - sa) * h)
            } else if f.t < total {
                // the settle: it slides on, just past its spot and back, and its rock and turn die away
                if !f.landed { f.landed = true; f.onLand?() }
                let tt = Double(up - f.dur)
                let x = Float(CardMotion.settle(tt, slide: Double(f.slide), speed: Double(f.speed)))
                let g = Float(CardMotion.settleShare(tt, slide: Double(f.slide), speed: Double(f.speed)))
                f.node.simdPosition = f.p1 + f.dir * x
                f.node.simdOrientation = simd_quatf(angle: f.kick * g, axis: [0, 1, 0]) * simd_quatf(angle: f.rock * g, axis: f.axis) * f.q1
                f.node.simdScale = SIMD3(repeating: f.s1)
            } else {
                if !f.landed { f.landed = true; f.onLand?() }
                done = true
            }
            if done {
                f.node.removeFromParentNode(); f.shadow.removeFromParentNode()
            } else {
                // a soft shadow on the glass under the card, fading as it climbs
                let p = f.node.simdPosition, k = max(0, 1 - p.y / 1.4)
                f.shadow.isHidden = f.fade
                f.shadow.simdPosition = [p.x + p.y * 0.25, 0.006, p.z + p.y * 0.2]
                f.shadow.simdScale = SIMD3(repeating: f.node.simdScale.x * (1 + p.y * 0.3))
                f.shadow.geometry?.firstMaterial?.transparency = CGFloat(0.8 * k)
                flights[i] = f
            }
            if done {
                let cb = f.onDone
                flights.remove(at: i)
                cb?()
            }
            i -= 1
        }
    }

    private func pileTarget(_ k: Int) -> (p: SIMD3<Float>, q: simd_quatf) {
        let lie = Table3D.pileLie(k)
        let local = pileLocal(min(pile.count, Table3D.pileCards), lie.dx, lie.dz)
        return (pileNode.simdPosition + local, yaw(Float(lie.yaw * 0.3)))
    }

    private func seatHandPoint(_ i: Int) -> SIMD3<Float> {
        guard let l = layout, l.seats.indices.contains(i) else { return [0, 0.12, -4] }
        let p = l.seats[i].handPos
        return [Float(p.x), 0.12, Float(p.z)]
    }

    private func landed(_ k: Int, _ art: String, _ node: SCNNode, haptic: Bool) {
        flyingK.remove(k)
        if !pileWanted.contains(where: { $0.k == k }) { pileWanted.append((k, art)) }
        node.removeFromParentNode()
        syncPile()
        if haptic { DispatchQueue.main.async { Haptics.play() } }
    }

    /// A seat throws a card onto the pile: up from its hand in an arc, spinning, and it lands and settles.
    func throwFromSeat(_ i: Int, art: String, k: Int) {
        guard let l = layout, l.seats.indices.contains(i) else { return }
        let s = l.seats[i], n = card(art), tg = pileTarget(k)
        flyingK.insert(k); syncPile()
        let q0 = yaw(Float(atan2(s.nx, s.nz))) * simd_quatf(angle: 0.3, axis: [1, 0, 0]) * Self.faceDown
        if shownCounts.indices.contains(i) { shownCounts[i] = max(0, shownCounts[i] - 1); fanAll() }
        fly(n, p0: seatHandPoint(i), q0: q0, p1: tg.p, q1: tg.q, dur: 0.62, arc: 1.0, spin: (Bool.random() ? -1 : 1) * .random(in: 2.2...4.2),
            s0: Float(Table3D.handScale), s1: 1, slide: 0.16,
            onLand: { DispatchQueue.main.async { Haptics.play() } },
            onDone: { [weak self] in self?.landed(k, art, n, haptic: false) })
    }

    /// Where a card in your hand on the screen is in the world: on the camera's ray through it, at the depth where
    /// it's `cardPoints` wide, but never below the glass (build 45: on an iPad's camera that depth is under the table,
    /// so your card started, and a drawn card ended, hidden under it). Brought nearer, it's drawn smaller to match:
    /// `s` is its scale.
    private func handPoint(_ l: Table3DLayout, x: Double, y: Double, cardPoints: Double) -> (p: SIMD3<Float>, s: Float) {
        let c = l.camera
        let want = Table3D.cardW * c.focal / max(1, cardPoints)
        let ray = c.right * ((x - c.width / 2) / c.focal) + c.up * (-(y - c.height / 2) / c.focal) - c.back
        var depth = want
        if ray.y < -1e-6 { depth = min(want, max(0.5, (c.eye.y - 0.6) / -ray.y)) }
        let p = c.eye + ray * depth
        return ([Float(p.x), Float(p.y), Float(p.z)], Float(depth / want))
    }

    /// You throw a card: from where it sat in your hand on the screen (`x`, `y`, `cardPoints` wide, turned `roll`°).
    func throwFromScreen(x: Double, y: Double, cardPoints: Double, roll: Double, art: String, k: Int) {
        guard let l = layout else { return }
        let n = card(art), tg = pileTarget(k)
        flyingK.insert(k); syncPile()
        let h = handPoint(l, x: x, y: y, cardPoints: cardPoints)
        fly(n, p0: h.p, q0: facingCamera(roll: Float(roll * .pi / 180)), p1: tg.p, q1: tg.q, dur: 0.7, arc: 0.9,
            s0: h.s, slide: 0.2, liftDir: cameraUp,
            onDone: { [weak self] in self?.landed(k, art, n, haptic: false) })
    }

    /// The screen's up, in the world.
    private var cameraUp: SIMD3<Float> {
        guard let c = layout?.camera else { return [0, 1, 0] }
        return [Float(c.up.x), Float(c.up.y), Float(c.up.z)]
    }

    /// A card faces the camera, as it does in your hand on the screen.
    private func facingCamera(roll: Float) -> simd_quatf {
        guard let c = layout?.camera else { return Self.faceDown }
        let r = SIMD3<Float>(Float(c.right.x), Float(c.right.y), Float(c.right.z))
        let up = SIMD3<Float>(Float(c.up.x), Float(c.up.y), Float(c.up.z))
        let b = SIMD3<Float>(Float(c.back.x), Float(c.back.y), Float(c.back.z))
        return simd_quatf(simd_float3x3(columns: (r, b, -up))) * yaw(-roll)
    }

    private func deckTop() -> (p: SIMD3<Float>, q: simd_quatf) {
        (deckNode.simdPosition + SIMD3<Float>(0, Float(Double(deckShown) * Table3D.cardT + 0.02), Float(-Table3D.cardH / 2 - 0.06)), Self.faceDown)
    }

    /// Cards fly from the draw pile to a seat's hand, one after another.
    func drawToSeat(_ i: Int, count: Int, delay: Double = 0) {
        guard let l = layout, l.seats.indices.contains(i) else { return }
        let s = l.seats[i], target = seatHandPoint(i), q1 = yaw(Float(atan2(s.nx, s.nz))) * Self.faceDown
        if inbound.indices.contains(i) { inbound[i] += count }
        for j in 0..<count {
            let from = deckTop()
            fly(card("card_back"), p0: from.p, q0: from.q, p1: target, q1: q1, dur: 0.55, arc: 0.7,
                s1: Float(Table3D.handScale), delay: Float(delay + Double(j) * 0.16), lift: 0.06,
                onDone: { [weak self] in
                    guard let self, self.inbound.indices.contains(i) else { return }
                    self.inbound[i] -= 1
                    if self.shownCounts.indices.contains(i) {
                        self.shownCounts[i] = self.inbound[i] <= 0 ? self.targetCounts[i] : min(self.targetCounts[i], self.shownCounts[i] + 1)
                        self.fanAll()
                    }
                })
        }
    }

    /// Cards fly from the draw pile to your hand on the screen, each to its own spot in the fan (`spots`: its center,
    /// width in points and turn in degrees), and each lands as the card there appears.
    func drawToScreen(spots: [(x: Double, y: Double, w: Double, roll: Double)], arts: [String], delay: Double = 0, landed: @escaping (Int) -> Void) {
        guard let l = layout else { return }
        for (j, art) in arts.enumerated() where spots.indices.contains(j) {
            let sp = spots[j]
            let h = handPoint(l, x: sp.x, y: sp.y, cardPoints: sp.w)
            let from = deckTop()
            fly(card(art), p0: from.p, q0: from.q, p1: h.p, q1: facingCamera(roll: Float(sp.roll * .pi / 180)),
                dur: 0.6, arc: 0.7, s1: h.s, delay: Float(delay + Double(j) * 0.16), lift: 0.06,
                onDone: { DispatchQueue.main.async { landed(j) } })
        }
    }

    // MARK: lightning

    /// A strike. `at` (0 to 1 across the screen) places it for a still; otherwise it lands somewhere in the strip of
    /// scene over the far seats, a little dimmer or brighter each time, and now and then it flashes twice.
    /// #610 (Tyler, Nov 20: "increase the impact of the lightning"): more branches, and often a second, fainter bolt
    /// beside the first. Photosensitivity: one strike is at most two flashes (the second 0.4 s or more after the
    /// first), and strikes are at least 1.4 s apart, so the scene never flashes 3 times in a second.
    func strike(at: Double? = nil) {
        let spot = strikeSpot(at)
        let live = freezeAt == nil
        var bolts: [(x: Float, z: Float, w: Float, br: Float)] = [(Float(spot.x), Float(spot.z), Float(spot.w), 1)]
        if !live || Double.random(in: 0..<1) < (tier == .low ? 0.25 : 0.55) {
            let other = strikeSpot(at.map { $0 < 0.5 ? $0 + 0.38 : $0 - 0.38 })
            bolts.append((Float(other.x), Float(other.z), Float(other.w) * 0.8, 0.6))
        }
        buildBolt(bolts)
        storm.t = 0; storm.x = spot.x
        storm.k = live ? .random(in: 0.75...1) : 1
        storm.twice = live && Double.random(in: 0..<1) < 0.4 ? .random(in: 0.4...0.55) : -1
        u.b.x = .random(in: 0...50)
    }

    /// Where a strike reaches the ground: under a point in the strip of scene between the header and the far seats,
    /// so it's seen but never crosses the table; and how wide its bolt is drawn, so it looks the same near or far.
    private func strikeSpot(_ at: Double?) -> (x: Double, z: Double, w: Double) {
        guard let l = layout else { return ((at.map { $0 - 0.5 } ?? .random(in: -0.4...0.4)) * 20, .random(in: -34 ... -24), 1) }
        let c = l.camera, top = l.free.y0, bottom = max(l.free.y0 + 10, l.stripBottom)
        let sx = (at ?? .random(in: 0.12...0.88)) * c.width
        let sy = top + (bottom - top) * (at == nil ? .random(in: 0.25...0.65) : 0.45)
        let g = c.ground(x: sx, y: sy, level: Double(u.b.z))
        let z = min(-14, max(-80, g?.z ?? -40)), x = min(30, max(-30, g?.x ?? 0))
        let w = min(2.4, max(0.6, c.depth(T3Vec(x, Double(u.b.z), z)) / 40))
        return (x, z, w)
    }

    private func buildBolt(_ bolts: [(x: Float, z: Float, w: Float, br: Float)]) {
        var pos: [Float] = [], ua: [Float] = []
        var z: Float = 0
        // #610: more branching (each limb forks more often, one level deeper), a little less on the oldest phones
        let fork: (Float, Float) = tier == .low ? (0.12, 0.07) : (0.2, 0.12)
        let deepest = tier == .low ? 3 : 4
        func seg(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ w: Float, _ br: Float) {
            let d = b - a, l = max(1e-4, simd_length(d)), n = SIMD2<Float>(-d.y / l * w, d.x / l * w)
            let v: [(SIMD2<Float>, Float)] = [(a - n, -1), (a + n, 1), (b + n, 1), (b - n, -1)]
            for i in [0, 1, 2, 0, 2, 3] { pos += [v[i].0.x, v[i].0.y, z]; ua += [v[i].1, br] }
        }
        func limb(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ w: Float, _ br: Float, _ depth: Int) {
            var pts = [a, b]
            for _ in 0..<6 {
                var np = [pts[0]]
                for i in 1..<pts.count {
                    let p = pts[i - 1], q = pts[i], l = simd_length(q - p)
                    np.append(SIMD2((p.x + q.x) / 2 + .random(in: -1...1) * l * 0.19, (p.y + q.y) / 2 + .random(in: -1...1) * l * 0.06))
                    np.append(q)
                }
                pts = np
            }
            for i in 1..<pts.count {
                seg(pts[i - 1], pts[i], w, br)
                if depth < deepest && i > 4 && i < pts.count - 4 && Float.random(in: 0..<1) < (depth == 0 ? fork.0 : fork.1) {
                    let p = pts[i], rest = max(1.5, p.y - b.y) * .random(in: 0.35...0.7), dir = (Bool.random() ? -1 : 1) * Float.random(in: 0.3...0.9)
                    limb(p, SIMD2(p.x + sin(dir) * rest, p.y - cos(dir) * rest), w * 0.62, br * 0.6, depth + 1)
                }
            }
        }
        for b in bolts {
            z = b.z
            limb(SIMD2(b.x + .random(in: -4...4) * b.w, 30), SIMD2(b.x, u.b.z), 0.55 * b.w, b.br, 0)
        }
        let idx = (0..<UInt32(pos.count / 3)).map { $0 }
        let g = SCNGeometry(sources: [Self.source(pos, .vertex, 3), Self.source(ua, .texcoord, 2)],
                            elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
        g.firstMaterial = boltMaterial
        boltNode.geometry = g
    }

    // MARK: each frame

    private static let light: [String: [UInt32]] = [   // ambient sky, ambient ground, fill, key
        "ember": [0xffb388, 0x7a1e06, 0xff5a1e, 0xffd2a0], "wave": [0xbfdcff, 0x0e3f7a, 0x3a8cff, 0xffe6c4],
        "bolt": [0xa89ad0, 0x1a1228, 0x8a4cff, 0xdcd0f4], "leaf": [0xffe2b0, 0x35521a, 0xffa848, 0xffd08a],   // late-afternoon sun
    ]

    /// The arrows' color per element: the website's suit colors (--sc), which its arrows mix with their creams.
    private static let flowColor: [String: UInt32] = ["ember": 0xE2662A, "wave": 0x2E7FD4, "bolt": 0x8B5FD6, "leaf": 0x4A9E4E]
    /// The comets' colors before #719, for the frame-rate comparison only.
    private static let flowColorBefore: [String: UInt32] = ["ember": 0xFF8A45, "wave": 0x5AAEFF, "bolt": 0xB08CFF, "leaf": 0x9BE07E]

    private func step(_ dt: Double) {
        let f = Float(dt)
        u.a.x += f * (reduced ? 0.12 : 1)
        u.b.w = reduced ? 1 : 0
        applyElement(dt)
        stepFlow(dt)
        stepFlights(f)
        stepFans(f)
        u.b.y += max(-f * 3, min(f * 3, turnTarget - u.b.y))
        rimLine?.transparency = CGFloat(0.55 + 0.45 * u.b.y)
    }

    private func applyElement(_ dt: Double) {
        // a change of suit is weather, never a cut: the new scene sweeps in from the horizon over about two seconds
        if let s = sceneSuit, s != suit {
            u.from = u.w; u.to = Self.oneHot(suit); u.a.y = 0; sceneSuit = suit
            if suit == "bolt" { storm.next = 2.1 }
            DispatchQueue.main.async { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
        }
        u.a.z = reduced ? 0 : 1
        if u.a.y < 1 { u.a.y = min(1, u.a.y + Float(dt / (reduced ? 2.6 : 2.1))) }
        let m = u.a.y * u.a.y * (3 - 2 * u.a.y)
        u.w = u.from + (u.to - u.from) * m
        var acc = [SIMD3<Float>](repeating: .zero, count: 4)
        for (i, s) in Self.suits.enumerated() {
            let w = u.w[i]
            guard w > 0, let hexes = Self.light[s] else { continue }
            for j in 0..<4 { acc[j] += Self.rgb(hexes[j]) * w }
        }
        ambient.color = Self.color((acc[0] + acc[1]) * 0.5)
        fill.color = Self.color(acc[2])
        key.color = Self.color(acc[3])
        rimLine?.diffuse.contents = Self.color(acc[0] + (SIMD3<Float>(1, 1, 1) - acc[0]) * 0.45)
        var fc = SIMD3<Float>(0, 0, 0)
        for (i, s) in Self.suits.enumerated() {
            if Self.before719 { if let h = Self.flowColorBefore[s] { fc += Self.rgb(h) * u.w[i] } }
            else if let h = Self.flowColor[s] { fc += Self.rgb(h) * u.w[i] }
        }
        u.f.x = fc.x; u.f.y = fc.y; u.f.z = fc.z
        let po: Float = reduced ? 0.45 : 1
        u.d = u.w * po
        addParts?.isHidden = max(u.d.x, max(u.d.y, u.d.z)) < 0.01
        leafParts?.isHidden = u.d.w < 0.01
        // the storm (Tyler, Nov 17: "more frequent lightning"; #610, Nov 20: "increase the impact"): a strike every
        // 1.4 to 3.2 seconds (2 to 4 on the oldest phones), irregular, sometimes a second flash; the clouds flicker
        // in between. Each flash is one smooth swell, never a strobe, and lights the scene and the table's rim, not
        // the hand or the text (those are drawn over the scene). Reduce Motion: no strikes and no flashes, only the
        // clouds' slow, gentle flicker (Table3DShaders.metal).
        let wb = Double(u.w.z)
        storm.t += dt
        if wb > 0.6 && freezeAt == nil && !reduced {
            storm.next -= dt
            if storm.next <= 0 { strike(); storm.next = tier == .low ? .random(in: 2...4) : .random(in: 1.4...3.2) }
        }
        var fl = 0.0, bi = 0.0
        if !reduced {
            let t = storm.t
            // one flash: at its brightest at once, then a smooth fall over about a third of a second (no flicker
            // inside it, which would count as more flashes)
            fl = exp(-t * 6)
            if storm.twice > 0 && t > storm.twice {
                let t2 = t - storm.twice
                fl += 0.75 * exp(-t2 * 7)
            }
            let end = 0.6 + max(0, storm.twice)
            bi = t < end ? min(1, fl * 1.7 + 0.3 * (1 - t / end)) : 0
        }
        u.a.w = Float(min(1.2, max(0, fl)) * wb * 0.7 * storm.k)
        u.c.y = Float(bi * wb)
        boltNode.isHidden = u.c.y < 0.01 || boltNode.geometry == nil
        flashLight.intensity = CGFloat(u.a.w) * 1800 / .pi
        ambient.intensity = 330 * CGFloat(1 + u.a.w * 0.5)
        u.c.x = u.w.w
        grassNode?.isHidden = u.w.w < 0.01
        for (s, n) in backdrops { let w = u.w[Self.suits.firstIndex(of: s) ?? 0]; n.isHidden = w < 0.01; n.geometry?.firstMaterial?.transparency = CGFloat(w) }
    }

    static func rgb(_ hex: UInt32) -> SIMD3<Float> {
        [Float((hex >> 16) & 0xff) / 255, Float((hex >> 8) & 0xff) / 255, Float(hex & 0xff) / 255]
    }
    static func color(_ c: SIMD3<Float>) -> UIColor { UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1) }

    // MARK: stepping down

    /// If frames run long for a few seconds, draw less: first the grass, then fewer particles.
    private func watchFrames(_ time: TimeInterval) {
        guard autoStepDown, freezeAt == nil, stepDowns < 2 else { return }
        frameTimes.append(time)
        if frameTimes.count < 120 { return }
        let span = (frameTimes.last ?? 0) - (frameTimes.first ?? 0)
        frameTimes.removeAll()
        guard span / 119 > 1.0 / 48 else { return }
        stepDowns += 1
        let n = stepDowns
        // the scene changes on its own clock thread
        post { [weak self] in
            guard let self else { return }
            if n == 1 && self.grassNode != nil {
                self.grassNode?.removeFromParentNode(); self.grassNode = nil
            } else {
                self.tier = T3DTier(rawValue: max(0, self.tier.rawValue - 1)) ?? .low
                self.buildParticles()
            }
        }
        DispatchQueue.main.async { [weak self] in self?.onStepDown?(n) }
    }
}
