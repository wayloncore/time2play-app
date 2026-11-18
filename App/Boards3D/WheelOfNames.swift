import SwiftUI
import UIKit
import T2PCore

/// The Wheel of Names (#535), the website's Library tool, played in the app: names on a wheel, a spin, one name picked.
/// The 3D wheel is the default; You → "Flat wheel" spins the flat one. Both turn by the same plan (T2PCore Wheel), so
/// they land on the same name. Nothing leaves the phone: the names are kept on this device only.
@MainActor
final class WheelModel: ObservableObject {
    static let namesKey = "t2p.wheel.names"
    @Published var wheel: Wheel { didSet { save() } }
    /// Where the wheel rests between spins.
    @Published private(set) var rotation: Double = 0
    @Published private(set) var spin: Wheel.Spin?
    @Published private(set) var started: Date?
    @Published var winner: String?
    /// Take the winner off the wheel after each spin (a classroom's "everyone gets a turn").
    @Published var removeWinners = false
    private var timer: DispatchWorkItem?

    /// Tests: -t2p-wheel-pick 2 fixes the winner; -t2p-wheel-freeze 1.0 stops a spin 1 second in (a still).
    private let fixedPick: Int? = WheelModel.argInt("-t2p-wheel-pick")
    let freeze: Double? = WheelModel.argDouble("-t2p-wheel-freeze")

    init() {
        let saved = UserDefaults.standard.data(forKey: WheelModel.namesKey).flatMap { try? JSONDecoder().decode([String].self, from: $0) }
        let reset = ProcessInfo.processInfo.arguments.contains("-uitest-reset")
        wheel = Wheel(names: (reset ? nil : saved).flatMap { $0.isEmpty ? nil : $0 } ?? Wheel.example)
    }

    private func save() { UserDefaults.standard.set(try? JSONEncoder().encode(wheel.names), forKey: WheelModel.namesKey) }

    var spinning: Bool { spin != nil }

    /// The wheel's turn right now (a spin in progress, or where it rests).
    func rotation(at date: Date) -> Double {
        guard let s = spin, let t0 = started else { return rotation }
        var t = date.timeIntervalSince(t0)
        if let f = freeze { t = min(t, f) }
        return s.rotation(at: t)
    }
    func speed(at date: Date) -> Double {
        guard let s = spin, let t0 = started else { return 0 }
        return s.speed(at: date.timeIntervalSince(t0))
    }

    func spinNow(reduced: Bool) {
        guard !spinning, wheel.names.count > 0 else { return }
        if let w = winner, removeWinners, wheel.names.count > 1, let i = wheel.names.firstIndex(of: w) { wheel.names.remove(at: i) }
        winner = nil
        let pick = fixedPick.map { min($0, wheel.names.count - 1) } ?? Int.random(in: 0..<wheel.names.count)
        guard let s = wheel.spin(from: rotation, pick: pick, turns: Int.random(in: 4...6), within: Double.random(in: 0...1), reduced: reduced) else { return }
        spin = s; started = Date()
        Haptics.play()
        UIAccessibility.post(notification: .announcement, argument: "Spinning")
        guard freeze == nil else { return }
        let w = DispatchWorkItem { [weak self] in self?.finish() }
        timer = w
        DispatchQueue.main.asyncAfter(deadline: .now() + s.duration, execute: w)
    }

    private func finish() {
        guard let s = spin else { return }
        rotation = Wheel.wrap(s.to)
        spin = nil; started = nil
        let name = wheel.names.indices.contains(s.winner) ? wheel.names[s.winner] : nil
        winner = name
        Haptics.yourTurn()
        if let n = name { UIAccessibility.post(notification: .announcement, argument: "The wheel picked \(n)") }
    }

    func setNames(_ text: String) {
        timer?.cancel(); spin = nil; started = nil; winner = nil
        let n = Wheel.parse(text)
        wheel = Wheel(names: n.isEmpty ? Wheel.example : n)
    }

    private static func argInt(_ a: String) -> Int? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: a), i + 1 < args.count else { return nil }
        return Int(args[i + 1])
    }
    private static func argDouble(_ a: String) -> Double? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: a), i + 1 < args.count else { return nil }
        return Double(args[i + 1])
    }
}

/// The wheel's face, drawn once per list of names: the slices in the site's colors and each name along its slice.
enum WheelArt {
    static func image(_ w: Wheel, side: CGFloat = 1024) -> UIImage {
        let f = UIGraphicsImageRendererFormat(); f.scale = 1; f.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: f).image { ctx in
            let c = ctx.cgContext
            let r = side / 2, center = CGPoint(x: r, y: r)
            let n = max(1, w.names.count)
            let slice = 2 * CGFloat.pi / CGFloat(n)
            for i in 0..<n {
                let a0 = -CGFloat.pi / 2 + CGFloat(i) * slice
                let p = UIBezierPath()
                p.move(to: center)
                p.addArc(withCenter: center, radius: r * 0.985, startAngle: a0, endAngle: a0 + slice, clockwise: true)
                p.close()
                UIColor(hex: w.names.isEmpty ? 0x18223A : w.color(i)).setFill(); p.fill()
                UIColor(white: 0, alpha: 0.28).setStroke(); p.lineWidth = side * 0.004; p.stroke()
            }
            // a soft shade toward the rim, for depth
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [UIColor(white: 1, alpha: 0.10).cgColor, UIColor(white: 0, alpha: 0.0).cgColor, UIColor(white: 0, alpha: 0.22).cgColor] as CFArray,
                                  locations: [0, 0.55, 1])!
            c.saveGState()
            UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: side, height: side).insetBy(dx: side * 0.0075, dy: side * 0.0075)).addClip()
            c.drawRadialGradient(grad, startCenter: center, startRadius: 0, endCenter: center, endRadius: r, options: [])
            c.restoreGState()
            // names, from the rim inward
            let arc = slice * r * 0.62
            let size = min(r * 0.085, max(r * 0.03, arc * 0.62))
            for (i, name) in w.names.enumerated() {
                let lum = luminance(w.color(i))
                let color = lum > 0.55 ? UIColor(hex: 0x2A1A05) : UIColor.white
                let font = UIFont.systemFont(ofSize: size, weight: .bold)
                let para = NSMutableParagraphStyle(); para.alignment = .right; para.lineBreakMode = .byTruncatingHead
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: para]
                c.saveGState()
                c.translateBy(x: r, y: r)
                c.rotate(by: -CGFloat.pi / 2 + (CGFloat(i) + 0.5) * slice)
                let box = CGRect(x: r * 0.24, y: -font.lineHeight / 2, width: r * 0.68, height: font.lineHeight)
                (name as NSString).draw(with: box, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs, context: nil)
                c.restoreGState()
            }
        }
    }

    static func luminance(_ hex: UInt32) -> Double {
        let r = Double((hex >> 16) & 0xFF) / 255, g = Double((hex >> 8) & 0xFF) / 255, b = Double(hex & 0xFF) / 255
        return 0.299 * r + 0.587 * g + 0.114 * b
    }
}

/// The screen: the wheel, Spin, who it picked, and the names (one a line).
struct WheelOfNamesView: View {
    @StateObject private var model = WheelModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(Boards3D.flatWheelKey) private var flatWheel = false
    @State private var editing = false
    @State private var text = ""
    @State private var art: UIImage?
    @State private var artFor: [String] = []

    private var use3D: Bool { Boards3D.wheel3D(flat: flatWheel) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Done") { dismiss() }.foregroundStyle(T2P.goldText).accessibilityIdentifier("wheel-done")
                Spacer()
                Text("Wheel of Names").font(.headline).foregroundStyle(T2P.text).accessibilityAddTraits(.isHeader)
                Spacer()
                Button { text = model.wheel.names.joined(separator: "\n"); editing = true } label: { Text("Names") }
                    .foregroundStyle(T2P.goldText).accessibilityIdentifier("wheel-names")
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            GeometryReader { g in
                let side = min(g.size.width - 24, g.size.height - 8)
                ZStack {
                    if let a = art {
                        if use3D {
                            Wheel3DView(model: model, art: a).frame(width: side, height: side)
                        } else {
                            WheelFlatView(model: model, art: a).frame(width: side, height: side)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                // a flick spins it, as on the website
                .gesture(DragGesture(minimumDistance: 24).onEnded { v in
                    if hypot(v.predictedEndTranslation.width, v.predictedEndTranslation.height) > 120 { model.spinNow(reduced: reduceMotion) }
                })
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("The wheel, \(model.wheel.names.count) names")
                .accessibilityIdentifier(use3D ? "wheel-3d" : "wheel-flat")
            }
            .padding(.horizontal, 12)
            VStack(spacing: 12) {
                Group {
                    if let w = model.winner {
                        VStack(spacing: 2) {
                            Text("The wheel picked").font(.subheadline.weight(.semibold)).foregroundStyle(T2P.muted)
                            Text(w).font(.system(size: 40, weight: .heavy, design: .rounded)).foregroundStyle(T2P.gold)
                                .lineLimit(1).minimumScaleFactor(0.5).accessibilityIdentifier("wheel-winner")
                        }
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.7).combined(with: .opacity))
                    } else {
                        Text(model.spinning ? "Spinning…" : "\(model.wheel.names.count) names on the wheel")
                            .font(.headline).foregroundStyle(T2P.muted)
                    }
                }
                .frame(minHeight: 64)
                .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.4), value: model.winner)
                Button(model.winner == nil ? "Spin" : model.removeWinners ? "Take \(model.winner!) off and spin" : "Spin again") {
                    model.spinNow(reduced: reduceMotion)
                }
                .buttonStyle(GoldButtonStyle())
                .disabled(model.spinning)
                .accessibilityIdentifier("wheel-spin")
                Toggle(isOn: $model.removeWinners) {
                    Text("Take each name off once it’s picked").font(.subheadline).foregroundStyle(T2P.text)
                }
                .tint(T2P.gold)
                .accessibilityIdentifier("wheel-remove")
            }
            .padding(.horizontal, 20).padding(.bottom, 16)
            .frame(maxWidth: 560)
        }
        .background(T2P.navy.ignoresSafeArea())
        .onAppear { redraw() }
        .onChange(of: model.wheel) { _, _ in redraw() }
        .sheet(isPresented: $editing) { names }
    }

    private func redraw() {
        guard artFor != model.wheel.names || art == nil else { return }
        artFor = model.wheel.names
        art = WheelArt.image(model.wheel)
    }

    private var names: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                Text("One name a line, up to \(Wheel.maxNames). They stay on this phone.").font(.subheadline).foregroundStyle(T2P.muted)
                TextEditor(text: $text)
                    .font(.body).foregroundStyle(T2P.text)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(T2P.panel, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(T2P.line))
                    .autocorrectionDisabled()
                    .accessibilityLabel("Names, one a line")
                    .accessibilityIdentifier("wheel-names-text")
            }
            .padding(20)
            .background(T2P.navy.ignoresSafeArea())
            .navigationTitle("Names")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editing = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { model.setNames(text); editing = false }.accessibilityIdentifier("wheel-names-save")
                }
            }
        }
    }
}

/// The flat wheel: the same face, turned in SwiftUI, with the pointer at the top.
struct WheelFlatView: View {
    @ObservedObject var model: WheelModel
    let art: UIImage
    var body: some View {
        TimelineView(.animation(paused: !model.spinning)) { ctx in
            let r = model.rotation(at: ctx.date)
            ZStack(alignment: .top) {
                Image(uiImage: art).resizable().scaledToFit()
                    .rotationEffect(.radians(r))
                    .overlay(Circle().stroke(T2P.gold, lineWidth: 6))
                    .overlay(Circle().fill(T2P.gold).frame(width: 34, height: 34).overlay(Circle().stroke(T2P.ink.opacity(0.4), lineWidth: 2)))
                    .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
                Triangle().fill(T2P.text).frame(width: 30, height: 34).shadow(radius: 3).offset(y: -12)
            }
        }
    }
    struct Triangle: Shape {
        func path(in r: CGRect) -> Path {
            var p = Path(); p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.midX, y: r.maxY)); p.closeSubpath(); return p
        }
    }
}
