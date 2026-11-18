import SwiftUI
import SceneKit
import UIKit
import T2PCore

/// Close Enough's 3D board (#535): the question's scale as a long lit board. While a question is asked, your range sits
/// on it as a gold bar that follows the sliders. At the reveal every player's range rises out of their own lane, and
/// the answer drops onto the board as a beam of light: the ranges it passes through glow, the misses stay ember.
/// Reduce Motion: no drop and no glow pulse; everything is simply there. The flat scale and chart stay as the fallback
/// (You → "Flat Close Enough board").
struct CloseEnoughBoardState: Equatable {
    struct Lane: Equatable { var id: String; var name: String; var face: Int; var lo: Double?; var hi: Double?; var points: Int; var hit: Bool; var me: Bool }
    var n: Int
    var floor: Double, ceiling: Double
    var reveal: Bool
    var lanes: [Lane]
    var answer: Double?
    var labels: [String]          // floor, middle, ceiling, as the question writes numbers
    var answerLabel: String?
    var mineLabel: String? = nil
}

extension CloseEnoughBoardState {
    /// While asking: one lane, yours (or none for someone watching). At the reveal: everyone with a result, best first.
    static func make(q: CloseEnough.Question, players: [ScorePlayer], me: String, lo: Double, hi: Double, seated: Bool) -> CloseEnoughBoardState {
        let name = { (p: ScorePlayer) in p.id == me ? "You" : RoomPlayer.stripBot(p.name) }
        var lanes: [Lane] = []
        if q.stage == "reveal" {
            lanes = players.filter { q.results[$0.id] != nil }
                .sorted { (q.results[$0.id]?.points ?? 0) > (q.results[$1.id]?.points ?? 0) }
                .prefix(8)
                .map { p in
                    let r = q.results[p.id]
                    return Lane(id: p.id, name: name(p), face: p.face, lo: r?.lo, hi: r?.hi, points: r?.points ?? 0,
                                hit: (r?.points ?? 0) > 0, me: p.id == me)
                }
        } else if seated, let p = players.first(where: { $0.id == me }) {
            lanes = [Lane(id: p.id, name: "You", face: p.face, lo: lo, hi: hi, points: 0, hit: true, me: true)]
        }
        let mid = q.snap(q.floor + (q.ceiling - q.floor) / 2)
        return CloseEnoughBoardState(n: q.n, floor: q.floor, ceiling: q.ceiling, reveal: q.stage == "reveal", lanes: lanes,
                                     answer: q.stage == "reveal" ? q.answer : nil,
                                     labels: [q.format(q.floor), q.format(mid), q.format(q.ceiling)],
                                     answerLabel: q.answer.map { q.format($0) }, mineLabel: q.formatRange(lo, hi))
    }

    /// What VoiceOver reads for the board (the scene itself is decoration).
    var spoken: String {
        if !reveal {
            guard !lanes.isEmpty, let m = mineLabel else { return "Scale from \(labels[0]) to \(labels[2])" }
            return "Scale from \(labels[0]) to \(labels[2]); your range \(m)"
        }
        return lanes.map { "\($0.name): \($0.lo == nil ? "no range" : "\($0.points) points")" }.joined(separator: ". ")
    }
}

/// The scene: a board 8 units long (the scale), lanes 0.8 apart, names on the left, points on the right.
final class CloseEnoughBoardWorld {
    let scene = SCNScene()
    let camera = SCNNode()
    private let board = SCNNode()
    private var lanesNode = SCNNode()
    private var beam: SCNNode?
    private var mineBar: SCNNode?
    private var shown: CloseEnoughBoardState?
    static let length: Float = 8
    static let gap: Float = 0.8

    init() {
        let cam = SCNCamera()
        cam.fieldOfView = 70
        cam.projectionDirection = .horizontal
        cam.zNear = 0.1; cam.zFar = 80
        cam.wantsHDR = false
        camera.camera = cam
        scene.rootNode.addChildNode(camera)
        Scene3D.lights(into: scene)
        scene.rootNode.addChildNode(board)
        scene.rootNode.addChildNode(lanesNode)
    }

    private func x(_ v: Double, _ s: CloseEnoughBoardState) -> Float {
        let span = max(1e-9, s.ceiling - s.floor)
        return Float((min(s.ceiling, max(s.floor, v)) - s.floor) / span) * Self.length - Self.length / 2
    }
    private func z(_ i: Int, of n: Int) -> Float { (Float(i) - Float(max(0, n - 1)) / 2) * Self.gap }

    /// The board itself, sized for the number of lanes: a dark slab, a gold edge, ticks and the three numbers.
    private func buildBoard(_ s: CloseEnoughBoardState) {
        board.childNodes.forEach { $0.removeFromParentNode() }
        let n = max(1, s.lanes.count)
        let depth = CGFloat(Float(n) * Self.gap + 0.9)
        let slab = SCNNode(geometry: SCNBox(width: CGFloat(Self.length) + 3.4, height: 0.3, length: depth, chamferRadius: 0.12))
        slab.geometry!.materials = [Scene3D.material(UIColor(hex: 0x121A2E), metal: 0.1, rough: 0.55)]
        slab.position = SCNVector3(0, -0.15, 0)
        board.addChildNode(slab)
        // the scale's own strip, a shade lighter, with a gold front edge
        let strip = SCNNode(geometry: SCNBox(width: CGFloat(Self.length) + 0.2, height: 0.04, length: depth - 0.3, chamferRadius: 0.02))
        strip.geometry!.materials = [Scene3D.material(UIColor(hex: 0x1B2742), rough: 0.7)]
        strip.position = SCNVector3(0, 0.02, 0)
        board.addChildNode(strip)
        let edge = SCNNode(geometry: SCNBox(width: CGFloat(Self.length) + 0.2, height: 0.05, length: 0.05, chamferRadius: 0.02))
        edge.geometry!.materials = [Scene3D.material(UIColor(hex: 0xE9B45A), metal: 0.8, rough: 0.3, glow: UIColor(hex: 0x5A4010))]
        edge.position = SCNVector3(0, 0.04, Float(depth) / 2 - 0.15)
        board.addChildNode(edge)
        for k in 0...10 {
            let major = k % 5 == 0
            let t = SCNNode(geometry: SCNBox(width: 0.035, height: 0.03, length: major ? 0.34 : 0.18, chamferRadius: 0))
            t.geometry!.materials = [Scene3D.material(UIColor(hex: major ? 0xE9B45A : 0x8A95AD), glow: UIColor(hex: major ? 0x3A2808 : 0x101828))]
            t.position = SCNVector3(Float(k) / 10 * Self.length - Self.length / 2, 0.05, Float(depth) / 2 - 0.35)
            board.addChildNode(t)
        }
        for (k, text) in s.labels.enumerated() {
            let lab = Scene3D.plane(Scene3D.label(text, size: 40, color: UIColor(hex: 0xEEF1F7)), height: 0.5)
            // the end numbers sit inside the scale's ends, so a long one ("20,000 meters") never runs off the board
            let w = Float((lab.geometry as! SCNPlane).width)
            let x = k == 0 ? -Self.length / 2 + w / 2 - 0.2 : k == 2 ? Self.length / 2 - w / 2 + 0.2 : 0
            lab.position = SCNVector3(x, 0.06, Float(depth) / 2 + 0.32)
            lab.eulerAngles.x = -.pi / 2.6
            board.addChildNode(lab)
        }
        // lane grooves
        for i in 0..<s.lanes.count {
            let g = SCNNode(geometry: SCNBox(width: CGFloat(Self.length), height: 0.02, length: 0.44, chamferRadius: 0.01))
            g.geometry!.materials = [Scene3D.material(UIColor(hex: 0x0E1526), rough: 0.9)]
            g.position = SCNVector3(0, 0.045, z(i, of: s.lanes.count))
            board.addChildNode(g)
        }
        aim(lanes: n)
    }

    /// The camera, raised and pulled back as lanes are added, so the whole board always fits.
    private func aim(lanes n: Int) {
        let k = Float(max(1, n))
        camera.position = SCNVector3(0, 4.2 + k * 0.45, 5.6 + k * 0.4)
        camera.look(at: SCNVector3(0, 0.1, 0.45))
    }

    private func bar(_ l: CloseEnoughBoardState.Lane, _ s: CloseEnoughBoardState, glow: Bool) -> SCNNode? {
        guard let a = l.lo, let b = l.hi else { return nil }
        let w = max(0.08, CGFloat(x(b, s) - x(a, s)))
        let box = SCNBox(width: w, height: 0.24, length: 0.4, chamferRadius: 0.07)
        let color = l.hit ? UIColor(hex: 0xE9B45A) : UIColor(hex: 0xE2662A)
        box.materials = [Scene3D.material(color, metal: 0.35, rough: 0.35, glow: glow ? color.withAlphaComponent(0.25) : nil)]
        let node = SCNNode(geometry: box)
        node.position = SCNVector3((x(a, s) + x(b, s)) / 2, 0.17, 0)
        return node
    }

    func apply(_ s: CloseEnoughBoardState, reduced: Bool) {
        let old = shown
        shown = s
        let sameBoard = old != nil && old!.n == s.n && old!.reveal == s.reveal && old!.lanes.map(\.id) == s.lanes.map(\.id)
            && old!.labels == s.labels
        if sameBoard, !s.reveal, let l = s.lanes.first, let a = l.lo, let b = l.hi, let bar = mineBar, let box = bar.geometry as? SCNBox {
            // your range following the sliders
            SCNTransaction.begin(); SCNTransaction.animationDuration = reduced ? 0 : 0.12
            box.width = max(0.08, CGFloat(x(b, s) - x(a, s)))
            bar.position.x = (x(a, s) + x(b, s)) / 2
            SCNTransaction.commit()
            return
        }
        if sameBoard { return }
        buildBoard(s)
        lanesNode.removeFromParentNode()
        lanesNode = SCNNode()
        scene.rootNode.addChildNode(lanesNode)
        beam = nil; mineBar = nil
        // the reveal plays once, when the board first shows it (the ask's board and the reveal's are separate views)
        let animate = s.reveal && !reduced && (old == nil || old!.n != s.n || !old!.reveal)
        for (i, l) in s.lanes.enumerated() {
            let lane = SCNNode()
            lane.position = SCNVector3(0, 0, z(i, of: s.lanes.count))
            lanesNode.addChildNode(lane)
            let nm = Scene3D.plane(Scene3D.label(l.name, size: 40, weight: l.me ? .bold : .semibold, color: .white, face: l.face), height: 0.56)
            nm.position = SCNVector3(-Self.length / 2 - 0.15 - Float((nm.geometry as! SCNPlane).width) / 2, 0.08, 0)
            nm.eulerAngles.x = -.pi / 2.6
            lane.addChildNode(nm)
            if let b = bar(l, s, glow: s.reveal && l.hit && !animate) {
                lane.addChildNode(b)
                if !s.reveal { mineBar = b }
                if animate {
                    // each range rises out of its lane, one after another
                    let up = b.position
                    b.position.y = -0.3; b.opacity = 0
                    let rise = SCNAction.move(to: up, duration: 0.35); rise.timingMode = .easeOut
                    b.runAction(.sequence([.wait(duration: 0.12 * Double(i)), .group([rise, .fadeIn(duration: 0.25)])]))
                }
            }
            if s.reveal {
                let txt = l.lo == nil ? "none" : l.points > 0 ? "+\(l.points)" : "0"
                let pts = Scene3D.plane(Scene3D.label(txt, size: 44, weight: .heavy, color: l.points > 0 ? UIColor(hex: 0x5CC88A) : UIColor(hex: 0x8A95AD)), height: 0.52)
                pts.position = SCNVector3(Self.length / 2 + 0.2 + Float((pts.geometry as! SCNPlane).width) / 2, 0.08, 0)
                pts.eulerAngles.x = -.pi / 2.6
                lane.addChildNode(pts)
                if animate { pts.opacity = 0; pts.runAction(.sequence([.wait(duration: 1.5 + 0.08 * Double(i)), .fadeIn(duration: 0.3)])) }
            }
        }
        if s.reveal, let ans = s.answer { dropBeam(at: x(ans, s), lanes: max(1, s.lanes.count), label: s.answerLabel, animate: animate) }
    }

    /// The answer: a beam of light across every lane, with the number over it.
    private func dropBeam(at bx: Float, lanes n: Int, label: String?, animate: Bool) {
        let depth = CGFloat(Float(n) * Self.gap + 0.4)
        let node = SCNNode()
        let sheet = SCNNode(geometry: SCNBox(width: 0.05, height: 0.9, length: depth, chamferRadius: 0.02))
        let m = SCNMaterial(); m.lightingModel = .constant
        m.diffuse.contents = UIColor(white: 1, alpha: 0.55); m.emission.contents = UIColor(white: 1, alpha: 1)
        m.blendMode = .add; m.writesToDepthBuffer = false
        sheet.geometry!.materials = [m]
        sheet.position = SCNVector3(0, 0.45, 0)
        node.addChildNode(sheet)
        let cap = SCNNode(geometry: SCNSphere(radius: 0.13))
        cap.geometry!.materials = [Scene3D.material(.white, metal: 0.2, rough: 0.2, glow: UIColor(hex: 0xFFF2D0))]
        cap.position = SCNVector3(0, 0.95, Float(depth) / 2)
        node.addChildNode(cap)
        if let t = label {
            let lab = Scene3D.plane(Scene3D.label(t, size: 46, weight: .heavy, color: UIColor(hex: 0x2A1A05), pill: UIColor(hex: 0xE9B45A)), height: 0.46, billboard: true)
            lab.position = SCNVector3(0, 1.45, Float(depth) / 2)
            node.addChildNode(lab)
        }
        node.position = SCNVector3(bx, 0, 0)
        lanesNode.addChildNode(node)
        beam = node
        guard animate else { return }
        node.position.y = 4; node.opacity = 0
        let land = SCNAction.move(to: SCNVector3(bx, 0, 0), duration: 0.45); land.timingMode = .easeIn
        let bounceUp = SCNAction.move(to: SCNVector3(bx, 0.18, 0), duration: 0.12); bounceUp.timingMode = .easeOut
        let settle = SCNAction.move(to: SCNVector3(bx, 0, 0), duration: 0.14); settle.timingMode = .easeIn
        node.runAction(.sequence([.wait(duration: 0.12 * Double(n) + 0.35), .group([.fadeIn(duration: 0.2), land]), bounceUp, settle,
                                  .run { [weak self] _ in DispatchQueue.main.async { self?.glowHits() } }]))
    }

    /// The ranges the answer fell in light up once, then keep a soft glow.
    private func glowHits() {
        guard let s = shown else { return }
        for (i, l) in s.lanes.enumerated() where l.hit && l.lo != nil {
            guard i < lanesNode.childNodes.count else { continue }
            for c in lanesNode.childNodes[i].childNodes where c.geometry is SCNBox {
                let m = c.geometry!.firstMaterial!
                SCNTransaction.begin(); SCNTransaction.animationDuration = 0.25
                m.emission.contents = UIColor(hex: 0xE9B45A)
                SCNTransaction.completionBlock = {
                    SCNTransaction.begin(); SCNTransaction.animationDuration = 0.6
                    m.emission.contents = UIColor(hex: 0xE9B45A).withAlphaComponent(0.25)
                    SCNTransaction.commit()
                }
                SCNTransaction.commit()
            }
        }
    }
}

/// The board in SwiftUI. Its height grows with the lanes.
struct CloseEnoughBoard3D: View {
    let state: CloseEnoughBoardState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var holder = Holder()

    final class Holder: ObservableObject {
        let world = CloseEnoughBoardWorld()
        lazy var view: SCNView = Scene3D.view(world.scene, camera: world.camera)
    }

    var body: some View {
        Host(holder: holder)
            .frame(height: 118 + CGFloat(max(1, state.lanes.count)) * 34)
            .background(LinearGradient(colors: [Color(hex: 0x0B1121), Color(hex: 0x16203A)], startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .onAppear { holder.world.apply(state, reduced: reduceMotion) }
            .onChange(of: state) { _, s in holder.world.apply(s, reduced: reduceMotion) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(state.spoken)
    }

    struct Host: UIViewRepresentable {
        let holder: Holder
        func makeUIView(context: Context) -> SCNView { holder.view }
        func updateUIView(_ uiView: SCNView, context: Context) {}
    }
}
