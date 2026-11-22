import SwiftUI
import SceneKit
import UIKit
import T2PCore

/// The 3D boards added in #535, each behind its own setting (You → "Flat Close Enough board", "Flat wheel"). The 3D
/// board is what a new player gets; the setting plays the flat one, which stays as it was. UI tests force either:
/// -t2p-ce3d / -t2p-ce-flat, -t2p-wheel3d / -t2p-wheel-flat. Saved data: new keys only.
enum Boards3D {
    static let flatCloseEnoughKey = "t2p.flatCloseEnough"
    /// #707: a player's Close Enough takes the website's look; this setting (off unless turned on) plays the 3D board
    /// instead. A new key, so 1.1 still reads the old one (which the host's big screen still uses).
    static let closeEnough3DKey = "t2p.closeEnough3D"
    static let flatWheelKey = "t2p.flatWheel"
    private static func arg(_ a: String) -> Bool { ProcessInfo.processInfo.arguments.contains(a) }
    static func closeEnough3D(flat: Bool) -> Bool { arg("-t2p-ce3d") || (!arg("-t2p-ce-flat") && !flat) }
    /// A player's Close Enough: the 3D board only when You → "3D Close Enough board" is on (or -t2p-ce3d).
    static func playerCloseEnough3D(on: Bool) -> Bool { arg("-t2p-ce3d") || (!arg("-t2p-ce-flat") && !arg("-t2p-ce-web") && on) }
    static func wheel3D(flat: Bool) -> Bool { arg("-t2p-wheel3d") || (!arg("-t2p-wheel-flat") && !flat) }
}

/// Small helpers the 3D boards share: words and faces drawn into images for planes in the scene, and materials.
enum Scene3D {
    /// Words as an image (white on clear unless a color is given), at 3× for sharp text on any screen.
    static func label(_ text: String, size: CGFloat = 44, weight: UIFont.Weight = .semibold, color: UIColor = .white,
                      face: Int? = nil, pill: UIColor? = nil) -> UIImage {
        let font = UIFont.systemFont(ofSize: size, weight: weight)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let t = (text as NSString).size(withAttributes: attrs)
        let faceSide = face == nil ? 0 : size * 1.5
        let gap: CGFloat = face == nil ? 0 : size * 0.3
        let padX: CGFloat = pill == nil ? 4 : size * 0.45, padY: CGFloat = pill == nil ? 4 : size * 0.22
        let w = ceil(t.width + faceSide + gap + padX * 2), h = ceil(max(t.height, faceSide) + padY * 2)
        let f = UIGraphicsImageRendererFormat(); f.scale = 2; f.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: f).image { ctx in
            if let p = pill {
                p.setFill()
                UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: h / 2).fill()
            }
            if let fi = face {
                let r = CGRect(x: padX, y: (h - faceSide) / 2, width: faceSide, height: faceSide)
                ctx.cgContext.saveGState()
                UIBezierPath(ovalIn: r).addClip()
                if let img = Art.image(Faces.name(fi)) { img.draw(in: r) } else { UIColor(hex: 0x18223A).setFill(); UIRectFill(r) }
                ctx.cgContext.restoreGState()
            }
            let shadow = NSShadow(); shadow.shadowColor = UIColor.black.withAlphaComponent(pill == nil ? 0.7 : 0); shadow.shadowBlurRadius = size * 0.12
            var a = attrs; a[.shadow] = shadow
            (text as NSString).draw(at: CGPoint(x: padX + faceSide + gap, y: (h - t.height) / 2), withAttributes: a)
        }
    }

    /// A plane showing an image, `height` tall in world units, facing +Z.
    static func plane(_ image: UIImage, height: CGFloat, billboard: Bool = false) -> SCNNode {
        let p = SCNPlane(width: height * image.size.width / max(1, image.size.height), height: height)
        let m = SCNMaterial()
        m.diffuse.contents = image
        m.lightingModel = .constant
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        p.materials = [m]
        let n = SCNNode(geometry: p)
        n.renderingOrder = 10
        if billboard { let c = SCNBillboardConstraint(); c.freeAxes = .Y; n.constraints = [c] }
        return n
    }

    static func material(_ color: UIColor, metal: CGFloat = 0, rough: CGFloat = 0.5, glow: UIColor? = nil) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.metalness.contents = metal
        m.roughness.contents = rough
        if let g = glow { m.emission.contents = g }
        return m
    }

    /// A soft key light, a fill and an ambient wash: the boards' lighting.
    static func lights(into scene: SCNScene, key: SCNVector3 = SCNVector3(-3, 8, 6)) {
        let amb = SCNNode(); amb.light = SCNLight(); amb.light!.type = .ambient; amb.light!.intensity = 380
        amb.light!.color = UIColor(red: 0.75, green: 0.8, blue: 1, alpha: 1)
        let k = SCNNode(); k.light = SCNLight(); k.light!.type = .directional; k.light!.intensity = 1100
        k.position = key; k.look(at: SCNVector3(0, 0, 0))
        let fill = SCNNode(); fill.light = SCNLight(); fill.light!.type = .omni; fill.light!.intensity = 420
        fill.light!.color = UIColor(red: 1, green: 0.85, blue: 0.6, alpha: 1)
        fill.position = SCNVector3(4, 3, 5)
        [amb, k, fill].forEach(scene.rootNode.addChildNode)
    }

    /// An SCNView set up the way the app's 3D scenes are: clear, untouchable, out of VoiceOver's way.
    /// `continuous`: redraw every frame (a scene moved by a SceneTicker).
    static func view(_ scene: SCNScene, camera: SCNNode, delegate: SCNSceneRendererDelegate? = nil, continuous: Bool = false) -> SCNView {
        let v = SCNView(frame: .zero)
        v.scene = scene
        v.pointOfView = camera
        v.delegate = delegate
        v.isPlaying = true
        v.rendersContinuously = delegate != nil || continuous
        v.preferredFramesPerSecond = 60
        v.antialiasingMode = .multisampling4X
        v.backgroundColor = .clear
        v.isOpaque = false
        v.isUserInteractionEnabled = false
        v.isAccessibilityElement = false
        v.accessibilityElementsHidden = true
        return v
    }
}
