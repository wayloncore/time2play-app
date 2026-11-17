import SwiftUI
import SceneKit
import UIKit
import T2PCore

/// Which table Overdraft plays at (#496). Since Nov 17 (Tyler: "Everyone.") the 3D table is the default; You →
/// "Classic table" goes back to the flat one. UI tests force either with -t2p-3d or -t2p-classic.
enum Table3DSwitch {
    /// The old "3D table (preview)" switch: kept under its name (the version before reads it), and written to match
    /// "Classic table" so a step back to that version keeps the same table.
    static let key = "t2p.table3d"
    /// "Classic table": on plays the flat table. Never touched (false) plays the 3D table.
    static let classicKey = "t2p.classicTable"
    static var forced: Bool { ProcessInfo.processInfo.arguments.contains("-t2p-3d") }
    static var forcedClassic: Bool { ProcessInfo.processInfo.arguments.contains("-t2p-classic") }
    /// The 3D table unless "Classic table" is on (or a test asks for the classic one).
    static func use3D(classic: Bool) -> Bool { forced || (!forcedClassic && !classic) }
}

/// The 3D table's bridge between SwiftUI and SceneKit: it owns the scene and its view, fits the camera to the screen,
/// and publishes where the seats landed so SwiftUI can draw faces, counts and names over them.
@MainActor
final class Table3DStage: ObservableObject {
    let world: Table3DWorld
    let scnView: SCNView
    @Published private(set) var layout: Table3DLayout?
    /// Still mode: the scene has stopped where a screenshot wants it.
    @Published var frozen = false
    private var fitKey = ""

    init() {
        let tier = T3DTier.device
        world = Table3DWorld(tier: tier)
        let v = SCNView(frame: .zero)
        v.scene = world.scene
        v.pointOfView = world.cameraNode
        v.delegate = world
        v.isPlaying = true
        v.rendersContinuously = true
        v.preferredFramesPerSecond = 60
        v.antialiasingMode = tier == .high ? .multisampling4X : tier == .mid ? .multisampling2X : .none
        v.backgroundColor = .black
        v.isUserInteractionEnabled = false
        v.isAccessibilityElement = false
        // the scene is decoration (faces, piles and the suit are SwiftUI over it): accessibility never walks into it
        v.accessibilityElementsHidden = true
        scnView = v
        world.onFrozen = { [weak self] in self?.frozen = true }
        world.onStepDown = { [weak self] n in if n >= 2 { self?.scnView.antialiasingMode = .none } }
    }

    /// Fits the camera and seats to the screen; does nothing if nothing that matters changed.
    func fit(width: Double, height: Double, free: T3Rect, players: Int, labels: [Double], counts: [Int]) {
        guard width > 50, height > 50, free.height > 40 else { return }
        let key = "\(Int(width))x\(Int(height)) \(Int(free.y0))-\(Int(free.y1)) \(players) \(labels.map { Int($0 * 100) })"
        guard key != fitKey else { return }
        fitKey = key
        let l = Table3DLayout.make(players: players, width: width, height: height, free: free, labels: labels)
        layout = l
        world.post { [world] in world.setLayout(l, counts: counts) }
    }

    /// A name's width in world units at a seat's name size (0.35), with " bot" after a bot's name.
    static func labelUnits(_ name: String, bot: Bool) -> Double {
        let f = UIFont.systemFont(ofSize: 100, weight: .semibold)
        var w = (name as NSString).size(withAttributes: [.font: f]).width / 100 * 0.35
        if bot { w += (" bot" as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 80, weight: .medium)]).width / 100 * 0.35 }
        return Double(w)
    }

    /// A world point on the screen (points).
    func screen(_ p: T3Vec) -> CGPoint? {
        guard let c = layout?.camera else { return nil }
        let s = c.project(p)
        return CGPoint(x: s.x, y: s.y)
    }
}

/// SceneKit's view, full screen under everything.
struct Table3DSceneHost: UIViewRepresentable {
    let stage: Table3DStage
    func makeUIView(context: Context) -> SCNView { stage.scnView }
    func updateUIView(_ uiView: SCNView, context: Context) {}
}
