import SwiftUI
import SceneKit
import UIKit
import T2PCore

/// The 3D wheel (#535): the face on a thick gold-rimmed wheel standing on a post, pegs round the rim, and a pointer at
/// the top that flicks as each peg passes. It turns by the same spin plan as the flat wheel (WheelModel), read each
/// frame on SceneKit's render thread. Reduce Motion: the spin is a short turn (the model plans it) and no flick.
final class Wheel3DWorld: NSObject, SCNSceneRendererDelegate {
    let scene = SCNScene()
    let camera = SCNNode()
    private let spinner = SCNNode()
    private let face = SCNNode()
    private let pegsNode = SCNNode()
    private let pointer = SCNNode()
    private var pegCount = 12
    private let lock = NSLock()
    private var source: (() -> (Double, Double))?
    private var flick: Float = 0
    private var lastPeg: Int?
    private var lastTime: TimeInterval?
    var reduced = false
    var onPeg: (() -> Void)?
    static let radius: CGFloat = 2

    override init() {
        super.init()
        let R = Self.radius
        let cam = SCNCamera(); cam.fieldOfView = 38; cam.zNear = 0.1; cam.zFar = 60
        camera.camera = cam
        camera.position = SCNVector3(1.1, 0.35, 7.4)
        camera.look(at: SCNVector3(0, -0.15, 0))
        scene.rootNode.addChildNode(camera)
        Scene3D.lights(into: scene, key: SCNVector3(-4, 6, 8))
        let spot = SCNNode(); spot.light = SCNLight(); spot.light!.type = .spot; spot.light!.intensity = 900
        spot.light!.spotOuterAngle = 50; spot.light!.castsShadow = true; spot.light!.shadowRadius = 6
        spot.light!.shadowColor = UIColor(white: 0, alpha: 0.5)
        spot.position = SCNVector3(2, 5, 6); spot.look(at: SCNVector3(0, -1, 0))
        scene.rootNode.addChildNode(spot)

        // the stand: a floor shadow catcher, a post and a foot
        let shadowFloor = SCNFloor(); shadowFloor.reflectivity = 0
        let floor = SCNNode(geometry: shadowFloor)
        let fm = SCNMaterial(); fm.lightingModel = .shadowOnly; fm.colorBufferWriteMask = .all
        floor.geometry!.materials = [fm]
        floor.position = SCNVector3(0, Float(-R - 1.0), 0)
        scene.rootNode.addChildNode(floor)
        let post = SCNNode(geometry: SCNCylinder(radius: 0.14, height: 1.2))
        post.geometry!.materials = [Scene3D.material(UIColor(hex: 0x2A3350), metal: 0.6, rough: 0.35)]
        post.position = SCNVector3(0, Float(-R - 0.4), -0.25)
        scene.rootNode.addChildNode(post)
        let foot = SCNNode(geometry: SCNCylinder(radius: 0.9, height: 0.16))
        foot.geometry!.materials = [Scene3D.material(UIColor(hex: 0x1B2236), metal: 0.5, rough: 0.4)]
        foot.position = SCNVector3(0, Float(-R - 0.95), -0.25)
        scene.rootNode.addChildNode(foot)

        // the wheel: a thick disc, the face on its front, a gold rim, pegs and a hub, all turning together
        scene.rootNode.addChildNode(spinner)
        let body = SCNNode(geometry: SCNCylinder(radius: R, height: 0.26))
        body.geometry!.materials = [Scene3D.material(UIColor(hex: 0x121A2E), metal: 0.3, rough: 0.5)]
        body.eulerAngles.x = .pi / 2
        body.position = SCNVector3(0, 0, -0.13)
        spinner.addChildNode(body)
        let plane = SCNPlane(width: R * 2, height: R * 2)
        let m = SCNMaterial(); m.lightingModel = .physicallyBased; m.roughness.contents = 0.45; m.metalness.contents = 0.05
        m.transparencyMode = .aOne
        plane.materials = [m]
        face.geometry = plane
        face.position = SCNVector3(0, 0, 0.005)
        spinner.addChildNode(face)
        let rim = SCNNode(geometry: SCNTorus(ringRadius: R, pipeRadius: 0.085))
        rim.geometry!.materials = [Scene3D.material(UIColor(hex: 0xE9B45A), metal: 0.9, rough: 0.25)]
        rim.eulerAngles.x = .pi / 2
        spinner.addChildNode(rim)
        let hub = SCNNode(geometry: SCNCylinder(radius: 0.26, height: 0.16))
        hub.geometry!.materials = [Scene3D.material(UIColor(hex: 0xE9B45A), metal: 0.9, rough: 0.2)]
        hub.eulerAngles.x = .pi / 2
        hub.position = SCNVector3(0, 0, 0.08)
        spinner.addChildNode(hub)
        spinner.addChildNode(pegsNode)

        // the pointer, hinged at its top so it can flick
        let pin = SCNNode(geometry: SCNPyramid(width: 0.34, height: 0.52, length: 0.14))
        pin.geometry!.materials = [Scene3D.material(UIColor(hex: 0xEEF1F7), metal: 0.2, rough: 0.3, glow: UIColor(white: 0.12, alpha: 1))]
        pin.eulerAngles.z = .pi           // point down at the wheel
        pin.position = SCNVector3(0, 0.12, 0)
        pointer.addChildNode(pin)
        let cap = SCNNode(geometry: SCNSphere(radius: 0.11))
        cap.geometry!.materials = [Scene3D.material(UIColor(hex: 0xE9B45A), metal: 0.9, rough: 0.2)]
        cap.position = SCNVector3(0, 0.16, 0)
        pointer.addChildNode(cap)
        pointer.position = SCNVector3(0, Float(R) + 0.3, 0.2)
        scene.rootNode.addChildNode(pointer)
    }

    /// A new face (the names changed): the image and the pegs between slices.
    func setFace(_ image: UIImage, slices: Int) {
        face.geometry?.firstMaterial?.diffuse.contents = image
        pegCount = max(12, slices)
        pegsNode.childNodes.forEach { $0.removeFromParentNode() }
        let peg = SCNCylinder(radius: 0.04, height: 0.16)
        peg.materials = [Scene3D.material(UIColor(hex: 0xF4E2B8), metal: 0.8, rough: 0.25)]
        let R = Float(Self.radius) * 0.955
        for k in 0..<pegCount {
            let a = Float(k) / Float(pegCount) * 2 * .pi   // clockwise from the top
            let n = SCNNode(geometry: peg)
            n.eulerAngles.x = .pi / 2
            n.position = SCNVector3(R * sin(a), R * cos(a), 0.08)
            pegsNode.addChildNode(n)
        }
    }

    /// Where the wheel's turn comes from: (rotation, speed), asked every frame.
    func follow(_ f: @escaping () -> (Double, Double)) { lock.lock(); source = f; lock.unlock() }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        lock.lock(); let src = source; lock.unlock()
        let dt = Float(min(0.1, max(0, time - (lastTime ?? time)))); lastTime = time
        guard let now = src?() else { return }
        let (rot, speed) = now
        // clockwise on screen is a negative turn about +Z, toward the camera
        spinner.eulerAngles.z = Float(-rot)
        let peg = Int(floor(Wheel.wrap(rot) / (2 * .pi) * Double(pegCount)))
        if let last = lastPeg, last != peg, abs(speed) > 0.05 {
            if !reduced { flick = min(0.55, 0.18 + Float(abs(speed)) * 0.02) }
            let cb = onPeg
            DispatchQueue.main.async { cb?() }
        }
        lastPeg = peg
        flick *= exp(-dt * 14)
        pointer.eulerAngles.z = flick
    }
}

/// The 3D wheel in SwiftUI. The scene reads the model's turn every frame.
struct Wheel3DView: View {
    @ObservedObject var model: WheelModel
    let art: UIImage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var holder = Holder()

    final class Holder: ObservableObject {
        let world = Wheel3DWorld()
        lazy var view: SCNView = Scene3D.view(world.scene, camera: world.camera, delegate: world)
        var lastClick = Date.distantPast
    }

    var body: some View {
        Host(holder: holder)
            .onAppear {
                holder.world.setFace(art, slices: model.wheel.names.count)
                holder.world.reduced = reduceMotion
                // the turn as of now, read on the render thread: a snapshot of the plan, so nothing main-only is touched
                bindSource()
                holder.world.onPeg = { [weak h = holder] in
                    guard let h, Date().timeIntervalSince(h.lastClick) > 0.045 else { return }
                    h.lastClick = Date(); Haptics.select()
                }
            }
            .onChange(of: art) { _, a in holder.world.setFace(a, slices: model.wheel.names.count) }
            .onChange(of: model.spinning) { _, _ in bindSource() }
            .onChange(of: model.rotation) { _, _ in bindSource() }
            .onChange(of: reduceMotion) { _, r in holder.world.reduced = r }
    }

    /// Hands the scene a copy of the current plan; it works out the turn from the clock itself.
    private func bindSource() {
        let spin = model.spin, start = model.started, rest = model.rotation, freeze = model.freeze
        holder.world.follow {
            guard let s = spin, let t0 = start else { return (rest, 0) }
            var t = Date().timeIntervalSince(t0)
            if let f = freeze { t = min(t, f) }
            return (s.rotation(at: t), freeze != nil && t >= freeze! ? 0 : s.speed(at: t))
        }
    }

    struct Host: UIViewRepresentable {
        let holder: Holder
        func makeUIView(context: Context) -> SCNView { holder.view }
        func updateUIView(_ uiView: SCNView, context: Context) {}
    }
}
