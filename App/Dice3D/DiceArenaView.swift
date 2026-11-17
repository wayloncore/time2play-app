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
    /// #523: the player has zoomed, turned or slid the view (a reset button shows).
    @Published private(set) var moved = false
    private(set) var world: DiceArenaWorld?
    private var scnView: SCNView?
    private var last: ArenaState?
    private var reduced = false
    var freezeOn: (DiceArenaWorld.Moment, Double)?
    /// Still mode (screenshots, DiceStill): when every arena stops.
    static var stillFreeze: (DiceArenaWorld.Moment, Double)?
    static var stillZoom: Double?
    /// Your own roll landing: a light tap (a Farkle's warning comes with its banner).
    var onFirstHit: (() -> Void)?
    /// The tray's shape: Hot Dice's, or Roll Call's row (#523).
    let tray: DiceTray
    private var top = 0.0

    init(tray: DiceTray = .classic) { self.tray = tray }

    func view() -> SCNView {
        if let v = scnView { return v }
        let w = DiceArenaWorld(tray: tray)
        w.reduced = reduced
        w.freezeOn = freezeOn ?? Self.stillFreeze
        w.onSpots = { [weak self] s in self?.spots = s }
        w.onLanded = { [weak self] k in self?.landed = k }
        w.onFirstHit = { [weak self] in self?.onFirstHit?() }
        w.onFrozen = { [weak self] in self?.frozen = true }
        w.onMoved = { [weak self] m in self?.moved = m }
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
        if let c = camera { w.post { w.setBase(c) } }
        if let z = Self.stillZoom, tray.shelf { w.post { w.zoom(by: Float(z)); w.orbit(dx: -50, dy: 20) } }
        return v
    }

    // #523: what the player does to the view (Hot Dice): pinch, one finger to look round, two to slide, double-tap
    func zoom(by k: CGFloat) { if let w = world { w.post { w.zoom(by: Float(k)) } } }
    func orbit(_ d: CGSize) { if let w = world { w.post { w.orbit(dx: Float(d.width), dy: Float(d.height)) } } }
    func pan(_ d: CGSize) { if let w = world { w.post { w.pan(dx: Float(d.width), dy: Float(d.height)) } } }
    func resetView() { if let w = world { w.post { w.resetView() } } }

    func update(_ s: ArenaState, reduced r: Bool) {
        if r != reduced { reduced = r; if let w = world { w.post { w.reduced = r } } }
        guard s != last else { return }
        last = s
        if let w = world { w.post { w.apply(s) } }
    }

    /// Fits the camera to the view; `top` keeps the tray below words drawn over the top of it.
    func fit(width: Double, height: Double, top: Double = 0) {
        guard width > 50, height > 50 else { return }
        let cam = DiceArena.camera(width: width, height: height, tray: tray, top: top)
        if cam == camera { return }
        camera = cam
        if let w = world { w.post { w.setBase(cam) } }
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
    /// A word over the die (Roll Call's "HOLD").
    var tag: String? = nil
}

/// The 3D dice arena (#521): the tray drawn by SceneKit, with a clear button over each die (taps and VoiceOver).
/// #523: `zoomable` lets the player pinch, look round (one finger), slide (two fingers) and double-tap back.
struct DiceArenaView: View {
    @ObservedObject var stage: DiceArenaStage
    let state: ArenaState
    var button: (ArenaDie) -> ArenaDieButton?
    var onTap: (Int) -> Void
    /// Room at the top for words drawn over the scene (the tray fits below it).
    var top: Double = 0
    var zoomable = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lastScale: CGFloat = 1
    @State private var lastDrag: CGSize = .zero
    @State private var pinching = false

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .topLeading) {
                DiceArenaSceneHost(stage: stage).accessibilityHidden(true)
                if zoomable {
                    // a double-tap on the felt (not a die) puts the view back
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture(count: 2) { stage.resetView(); Haptics.select() }
                        .accessibilityHidden(true)
                }
                overlay
                Text(stage.frozen ? "ready" : "").font(.system(size: 2)).opacity(0.02)
                    .accessibilityIdentifier(stage.frozen ? "dice3d-ready" : "dice3d-wait")
            }
            .onAppear { stage.fit(width: g.size.width, height: g.size.height, top: top); stage.update(state, reduced: reduceMotion) }
            .onChange(of: g.size) { _, s in stage.fit(width: s.width, height: s.height, top: top) }
            .onChange(of: top) { _, t in stage.fit(width: g.size.width, height: g.size.height, top: t) }
        }
        .simultaneousGesture(magnify, including: zoomable ? .all : .subviews)
        .simultaneousGesture(drag, including: zoomable ? .all : .subviews)
        .onChange(of: state) { _, s in stage.update(s, reduced: reduceMotion) }
        .onChange(of: reduceMotion) { _, r in stage.update(state, reduced: r) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dice-3d")
        .accessibilityAction(named: "Reset the view") { stage.resetView() }
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { v in
                let k = v.magnification / max(0.01, lastScale)
                lastScale = v.magnification
                pinching = true
                stage.zoom(by: k)
            }
            .onEnded { _ in lastScale = 1; pinching = false }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { v in
                let d = CGSize(width: v.translation.width - lastDrag.width, height: v.translation.height - lastDrag.height)
                lastDrag = v.translation
                if pinching { stage.pan(d) } else { stage.orbit(d) }
            }
            .onEnded { _ in lastDrag = .zero }
    }

    @ViewBuilder private var overlay: some View {
        if stage.camera != nil {
            ForEach(state.dice, id: \.id) { d in
                if let b = button(d), let spot = stage.spots[d.id] {
                    let side = CGFloat(spot.size)
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
                    .position(x: spot.screen.x, y: spot.screen.y)
                    .opacity(spot.shown ? 1 : 0.001)
                    if let tag = b.tag, spot.shown {
                        Text(tag).font(.caption2.weight(.heavy)).tracking(1).foregroundStyle(T2P.gold)
                            .shadow(color: .black.opacity(0.6), radius: 2)
                            .position(x: spot.screen.x, y: spot.screen.y - side * 0.62)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
    }
}
