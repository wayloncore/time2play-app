import SceneKit
import UIKit

/// The dice's faces (#521): ivory with inset pips, the 1's pip red, drawn once at launch. Each face has a picture and
/// a normal map that sinks the pips into the surface, so the light catches their rims.
enum DieArt {
    static let size = 256
    private static var faces: [Int: (UIImage, UIImage)] = [:]
    private static let lock = NSLock()

    /// A fresh material for a face (each die has its own, so a set-aside die can be shaded on its own).
    static func material(_ face: Int) -> SCNMaterial {
        let (img, nrm) = art(face)
        let m = SCNMaterial()
        m.lightingModel = .blinn
        m.diffuse.contents = img
        m.diffuse.mipFilter = .linear
        m.diffuse.maxAnisotropy = 4
        m.normal.contents = nrm
        m.normal.intensity = 1
        m.specular.contents = UIColor(white: 0.55, alpha: 1)
        m.shininess = 0.42
        m.multiply.contents = UIColor.white
        return m
    }

    /// Where the pips go, in 0...1 across a face.
    static func spots(_ v: Int) -> [(CGFloat, CGFloat)] {
        let a: CGFloat = 0.26, b: CGFloat = 0.5, c: CGFloat = 0.74
        switch v {
        case 1: return [(b, b)]
        case 2: return [(a, a), (c, c)]
        case 3: return [(a, a), (b, b), (c, c)]
        case 4: return [(a, a), (c, a), (a, c), (c, c)]
        case 5: return [(a, a), (c, a), (b, b), (a, c), (c, c)]
        default: return [(a, a), (c, a), (a, b), (c, b), (a, c), (c, c)]
        }
    }
    static func radius(_ v: Int) -> CGFloat { v == 1 ? 0.118 : 0.083 }

    private static func art(_ face: Int) -> (UIImage, UIImage) {
        lock.lock(); defer { lock.unlock() }
        if let a = faces[face] { return a }
        let a = (picture(face), normals(face))
        faces[face] = a
        return a
    }

    private static func picture(_ v: Int) -> UIImage {
        let s = CGFloat(size)
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1; fmt.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: s, height: s), format: fmt).image { ctx in
            let c = ctx.cgContext
            // ivory, a touch warmer toward the edges (old bone, not plastic white)
            let ivory = UIColor(red: 0.965, green: 0.925, blue: 0.835, alpha: 1)
            ivory.setFill(); c.fill(CGRect(x: 0, y: 0, width: s, height: s))
            let space = CGColorSpaceCreateDeviceRGB()
            if let g = CGGradient(colorsSpace: space, colors: [UIColor(white: 1, alpha: 0).cgColor,
                                                               UIColor(red: 0.80, green: 0.72, blue: 0.56, alpha: 0.35).cgColor] as CFArray,
                                  locations: [0.55, 1]) {
                c.drawRadialGradient(g, startCenter: CGPoint(x: s / 2, y: s / 2), startRadius: 0, endCenter: CGPoint(x: s / 2, y: s / 2),
                                     endRadius: s * 0.75, options: [.drawsAfterEndLocation])
            }
            let red = v == 1
            let base = red ? UIColor(red: 0.69, green: 0.17, blue: 0.15, alpha: 1) : UIColor(red: 0.14, green: 0.10, blue: 0.06, alpha: 1)
            let deep = red ? UIColor(red: 0.42, green: 0.07, blue: 0.06, alpha: 1) : UIColor(red: 0.05, green: 0.035, blue: 0.02, alpha: 1)
            for (x, y) in spots(v) {
                let r = radius(v) * s, ctr = CGPoint(x: x * s, y: y * s)
                // a soft shade just outside the pip (the hole's lip), then the pip: darker in its upper part, where the
                // rim shadows it
                if let lip = CGGradient(colorsSpace: space, colors: [UIColor(red: 0.55, green: 0.47, blue: 0.36, alpha: 0.45).cgColor,
                                                                     UIColor(white: 1, alpha: 0).cgColor] as CFArray, locations: [0, 1]) {
                    c.drawRadialGradient(lip, startCenter: ctr, startRadius: r * 0.95, endCenter: ctr, endRadius: r * 1.28, options: [])
                }
                c.saveGState()
                c.addEllipse(in: CGRect(x: ctr.x - r, y: ctr.y - r, width: 2 * r, height: 2 * r))
                c.clip()
                if let g = CGGradient(colorsSpace: space, colors: [base.cgColor, deep.cgColor] as CFArray, locations: [0, 1]) {
                    c.drawLinearGradient(g, start: CGPoint(x: ctr.x, y: ctr.y + r), end: CGPoint(x: ctr.x, y: ctr.y - r), options: [])
                }
                c.restoreGState()
            }
        }
    }

    /// A tangent-space normal map: flat, with a shallow round dish at each pip and a crisp rim.
    private static func normals(_ v: Int) -> UIImage {
        let n = size
        var px = [UInt8](repeating: 0, count: n * n * 4)
        let pips = spots(v).map { (Double($0.0) * Double(n), Double($0.1) * Double(n)) }
        let r = Double(radius(v)) * Double(n)
        for y in 0..<n {
            for x in 0..<n {
                var nx = 0.0, ny = 0.0
                for (cx, cy) in pips {
                    let dx = Double(x) + 0.5 - cx, dy = Double(y) + 0.5 - cy
                    let d = (dx * dx + dy * dy).squareRoot()
                    if d < r {
                        // inside the dish: the surface slopes down toward the center
                        nx = -dx / r * 0.55; ny = -dy / r * 0.55
                    } else if d < r + 2.2 {
                        // the rim: a steep edge
                        nx = dx / d * 0.9; ny = dy / d * 0.9
                    }
                }
                let l = (nx * nx + ny * ny + 1).squareRoot()
                let i = (y * n + x) * 4
                px[i] = UInt8(max(0, min(255, (nx / l * 0.5 + 0.5) * 255)))
                px[i + 1] = UInt8(max(0, min(255, (-ny / l * 0.5 + 0.5) * 255)))   // the image's rows run down; a normal map's green runs up
                px[i + 2] = UInt8(max(0, min(255, (1 / l * 0.5 + 0.5) * 255)))
                px[i + 3] = 255
            }
        }
        return Self.image(px, n, n) ?? UIImage()
    }

    static func image(_ px: [UInt8], _ w: Int, _ h: Int) -> UIImage? {
        var bytes = px
        let made: CGImage? = bytes.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
            return ctx.makeImage()
        }
        return made.map { UIImage(cgImage: $0) }
    }
}

extension DiceArenaWorld {
    /// A small seeded noise source for the textures.
    private struct Noise {
        var s: UInt32
        mutating func next() -> Double { s ^= s << 13; s ^= s >> 17; s ^= s << 5; return Double(s) / 4_294_967_296 }
    }

    /// Green felt: fine fibres over a slightly uneven ground.
    static func feltImage() -> UIImage? {
        let n = 256
        var px = [UInt8](repeating: 0, count: n * n * 4)
        var r = Noise(s: 99)
        for i in 0..<(n * n) {
            let k = 0.9 + r.next() * 0.2
            let x = i % n, y = i / n
            let wave = 0.97 + 0.03 * sin(Double(x) * 0.09) * cos(Double(y) * 0.07)
            px[i * 4] = UInt8(min(255, 26 * k * wave)); px[i * 4 + 1] = UInt8(min(255, 84 * k * wave)); px[i * 4 + 2] = UInt8(min(255, 60 * k * wave))
            px[i * 4 + 3] = 255
        }
        return DieArt.image(px, n, n)
    }

    /// The felt's nap, as a normal map.
    static func feltNormal() -> UIImage? {
        let n = 256
        var px = [UInt8](repeating: 0, count: n * n * 4)
        var r = Noise(s: 7)
        for i in 0..<(n * n) {
            px[i * 4] = UInt8(128 + Int((r.next() - 0.5) * 70)); px[i * 4 + 1] = UInt8(128 + Int((r.next() - 0.5) * 70))
            px[i * 4 + 2] = 240; px[i * 4 + 3] = 255
        }
        return DieArt.image(px, n, n)
    }

    /// Walnut: long grain with a few darker streaks.
    static func woodImage() -> UIImage? {
        let w = 512, h = 128
        var px = [UInt8](repeating: 0, count: w * h * 4)
        var r = Noise(s: 3)
        var rows = [Double](repeating: 0, count: h)
        for y in 0..<h { rows[y] = r.next() }
        for y in 0..<h {
            for x in 0..<w {
                let fx = Double(x) / Double(w), fy = Double(y) / Double(h)
                let g = sin((fy * 38 + sin(fx * 9 + rows[y / 8 * 8] * 6) * 0.9 + sin(fx * 23) * 0.15) * .pi)
                let streak = 0.5 + 0.5 * g
                let k = 0.78 + 0.22 * streak + (r.next() - 0.5) * 0.05
                let i = (y * w + x) * 4
                px[i] = UInt8(min(255, 118 * k)); px[i + 1] = UInt8(min(255, 74 * k)); px[i + 2] = UInt8(min(255, 44 * k)); px[i + 3] = 255
            }
        }
        return DieArt.image(px, w, h)
    }

    /// Leather: a base color with a fine pebble.
    static func leatherImage(_ base: UIColor) -> UIImage? {
        let n = 128
        var px = [UInt8](repeating: 0, count: n * n * 4)
        var r = Noise(s: 11)
        var cr: CGFloat = 0, cg: CGFloat = 0, cb: CGFloat = 0, ca: CGFloat = 0
        base.getRed(&cr, green: &cg, blue: &cb, alpha: &ca)
        for i in 0..<(n * n) {
            let k = 0.88 + r.next() * 0.24
            px[i * 4] = UInt8(min(255, Double(cr) * 255 * k)); px[i * 4 + 1] = UInt8(min(255, Double(cg) * 255 * k))
            px[i * 4 + 2] = UInt8(min(255, Double(cb) * 255 * k)); px[i * 4 + 3] = 255
        }
        return DieArt.image(px, n, n)
    }

    /// A soft dark oval: the tray's shadow on the screen's felt.
    static func blobImage() -> UIImage {
        let s = CGSize(width: 256, height: 256)
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1; fmt.opaque = false
        return UIGraphicsImageRenderer(size: s, format: fmt).image { ctx in
            let space = CGColorSpaceCreateDeviceRGB()
            guard let g = CGGradient(colorsSpace: space, colors: [UIColor(white: 0, alpha: 0.55).cgColor, UIColor(white: 0, alpha: 0.4).cgColor,
                                                                  UIColor(white: 0, alpha: 0).cgColor] as CFArray, locations: [0, 0.62, 1]) else { return }
            ctx.cgContext.drawRadialGradient(g, startCenter: CGPoint(x: 128, y: 128), startRadius: 0, endCenter: CGPoint(x: 128, y: 128),
                                             endRadius: 128, options: [])
        }
    }

    /// A held die's ring on the felt (#523): a soft gold band, clear in the middle.
    static func ringImage() -> UIImage {
        let s = CGSize(width: 128, height: 128)
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1; fmt.opaque = false
        return UIGraphicsImageRenderer(size: s, format: fmt).image { ctx in
            let c = ctx.cgContext
            let gold = UIColor(red: 0.96, green: 0.76, blue: 0.33, alpha: 1)
            c.setShadow(offset: .zero, blur: 10, color: gold.withAlphaComponent(0.9).cgColor)
            c.setStrokeColor(gold.cgColor)
            c.setLineWidth(7)
            c.addPath(UIBezierPath(roundedRect: CGRect(x: 14, y: 14, width: 100, height: 100), cornerRadius: 22).cgPath)
            c.strokePath()
        }
    }

    /// A pool of light, for the faint glow under dice that could score (added to what's under it).
    static func glowImage(_ color: UIColor) -> UIImage {
        let s = CGSize(width: 128, height: 128)
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1; fmt.opaque = true
        return UIGraphicsImageRenderer(size: s, format: fmt).image { ctx in
            UIColor.black.setFill(); ctx.fill(CGRect(origin: .zero, size: s))
            let space = CGColorSpaceCreateDeviceRGB()
            guard let g = CGGradient(colorsSpace: space, colors: [color.cgColor, color.withAlphaComponent(0.75).cgColor,
                                                                  color.withAlphaComponent(0.3).cgColor, UIColor(white: 0, alpha: 0).cgColor] as CFArray,
                                     locations: [0, 0.35, 0.62, 1]) else { return }
            ctx.cgContext.drawRadialGradient(g, startCenter: CGPoint(x: 64, y: 64), startRadius: 0, endCenter: CGPoint(x: 64, y: 64),
                                             endRadius: 64, options: [])
        }
    }
}
