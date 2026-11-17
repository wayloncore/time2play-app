import SwiftUI
import SceneKit
import T2PCore

/// The switch for the 3D dice (#521): off by default until Tyler approves it on TestFlight. You → "3D dice (preview)"
/// turns it on; UI tests pass the launch argument -t2p-dice3d. The flat dice stay as they are when it's off.
enum Dice3DSwitch {
    static let key = "t2p.dice3d"
    static var forced: Bool { ProcessInfo.processInfo.arguments.contains("-t2p-dice3d") }
}

/// The arena's bridge between SwiftUI and SceneKit: it owns the scene (made the first time it's drawn, so a game with
/// the switch off never builds it), fits the camera to the space it's given, and publishes where the dice are and
/// which roll has landed.
@MainActor
final class DiceArenaStage: ObservableObject {
    @Published private(set) var spots: [Int: DiceSpot] = [:]
    /// The roll ("n.seq", or Roll Call's roll key) whose dice have all come to rest.
    @Published private(set) var landed: String?
    @Published private(set) var camera: Table3DCamera?
    /// Still mode: the scene has stopped where a screenshot wants it.
    @Published private(set) var frozen = false
    private(set) var world: DiceArenaWorld?
    private var scnView: SCNView?
    private var last: ArenaState?
    private var reduced = false
    var freezeOn: (DiceArenaWorld.Moment, Double)?
    /// Still mode (screenshots, DiceStill): when every arena stops.
    static var stillFreeze: (DiceArenaWorld.Moment, Double)?
    /// Your own roll landing: a light tap (a Farkle's warning comes with its banner).
    var onFirstHit: (() -> Void)?

    func view() -> SCNView {
        if let v = scnView { return v }
        let w = DiceArenaWorld()
        w.reduced = reduced
        w.freezeOn = freezeOn ?? Self.stillFreeze
        w.onSpots = { [weak self] s in self?.spots = s }
        w.onLanded = { [weak self] k in self?.landed = k }
        w.onFirstHit = { [weak self] in self?.onFirstHit?() }
        w.onFrozen = { [weak self] in self?.frozen = true }
        let v = SCNView(frame: .zero)
        v.scene = w.scene
        v.pointOfView = w.cameraNode
        v.delegate = w
        v.isPlaying = true
        v.rendersContinuously = true
        v.preferredFramesPerSecond = 60
        v.antialiasingMode = .multisampling4X
        v.backgroundColor = .clear
        v.isOpaque = false
        v.isUserInteractionEnabled = false
        v.isAccessibilityElement = false
        v.accessibilityElementsHidden = true   // the dice speak through the buttons over them
        world = w; scnView = v
        if let s = last { w.post { w.apply(s) } }
        if let c = camera { place(c, in: w) }
        return v
    }

    private func place(_ cam: Table3DCamera, in w: DiceArenaWorld) {
        let eye = DiceArenaWorld.f(cam.eye), target = DiceArenaWorld.f(cam.eye - cam.back)
        w.post {
            w.cameraNode.camera?.fieldOfView = CGFloat(cam.fovY)
            w.cameraNode.simdPosition = eye
            w.cameraNode.simdLook(at: target)
        }
    }

    func update(_ s: ArenaState, reduced r: Bool) {
        if r != reduced { reduced = r; if let w = world { w.post { w.reduced = r } } }
        guard s != last else { return }
        last = s
        if let w = world { w.post { w.apply(s) } }
    }

    func fit(width: Double, height: Double) {
        guard width > 50, height > 50 else { return }
        let cam = DiceArena.camera(width: width, height: height)
        if cam == camera { return }
        camera = cam
        if let w = world { place(cam, in: w) }
    }

    /// A world point on the screen.
    func screen(_ p: T3Vec) -> CGPoint? {
        guard let c = camera else { return nil }
        let s = c.project(p)
        return CGPoint(x: s.x, y: s.y)
    }
}

/// SceneKit's view.
struct DiceArenaSceneHost: UIViewRepresentable {
    let stage: DiceArenaStage
    func makeUIView(context: Context) -> SCNView { stage.view() }
    func updateUIView(_ uiView: SCNView, context: Context) {}
}

/// How a die speaks and acts over the 3D arena: its accessibility identifier, label and value, and whether a tap does
/// anything. Nil leaves it out (a set-aside die is a plain element, not a button).
struct ArenaDieButton {
    var id: String
    var label: String
    var value: String
    var enabled: Bool
    var button = true
}

/// The 3D dice arena (#521): the tray drawn by SceneKit, with a clear button over each die (taps and VoiceOver).
struct DiceArenaView: View {
    @ObservedObject var stage: DiceArenaStage
    let state: ArenaState
    var button: (ArenaDie) -> ArenaDieButton?
    var onTap: (Int) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .topLeading) {
                DiceArenaSceneHost(stage: stage).accessibilityHidden(true)
                overlay
                Text(stage.frozen ? "ready" : "").font(.system(size: 2)).opacity(0.02)
                    .accessibilityIdentifier(stage.frozen ? "dice3d-ready" : "dice3d-wait")
            }
            .onAppear { stage.fit(width: g.size.width, height: g.size.height); stage.update(state, reduced: reduceMotion) }
            .onChange(of: g.size) { _, s in stage.fit(width: s.width, height: s.height) }
        }
        .onChange(of: state) { _, s in stage.update(s, reduced: reduceMotion) }
        .onChange(of: reduceMotion) { _, r in stage.update(state, reduced: r) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dice-3d")
    }

    @ViewBuilder private var overlay: some View {
        if let cam = stage.camera {
            ForEach(state.dice, id: \.id) { d in
                if let b = button(d) {
                    let spot = stage.spots[d.id] ?? DiceSpot(p: DiceArena.cupMouth, shown: false)
                    let top = spot.p + T3Vec(0, DiceArena.half, 0)
                    let at = cam.project(top)
                    let side = max(44, min(84, cam.pointsPerUnit(at: top) * 1.15))
                    Group {
                        if b.button {
                            Button { onTap(d.id) } label: { Color.clear.frame(width: side, height: side).contentShape(Rectangle()) }
                                .buttonStyle(DieButtonStyle())
                                .disabled(!b.enabled || !spot.shown)
                                .accessibilityAddTraits(d.place != .tray && d.place != .cup ? .isSelected : [])
                        } else {
                            Color.clear.frame(width: side, height: side)
                        }
                    }
                    .accessibilityLabel(b.label)
                    .accessibilityValue(b.value)
                    .accessibilityIdentifier(b.id)
                    .position(x: at.x, y: at.y)
                    .opacity(spot.shown ? 1 : 0.001)
                }
            }
        }
    }
}
