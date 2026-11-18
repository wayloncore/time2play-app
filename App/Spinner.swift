import SwiftUI

/// The app's loading spinner (wayloncore/tyleralocke#543): the gold ring of the Time2Play mark turning, with a light
/// glint traveling around it. Drawn in code (no video, no image), so it's sharp at any size from 20 to 80 points, on a
/// clear background. Reduce Motion: the ring stays still and gently pulses. It stands in for the system's plain
/// spinner wherever the app waits: opening a game, joining a room, opening a hosted room.
struct T2PSpinner: View {
    var size: CGFloat = 40
    /// For the screenshots: draw it as Reduce Motion does (true) or always turning (false), whatever the setting.
    var still: Bool? = nil
    var label: String = "Loading"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The app's gold (#E9B45A), a deeper gold for the ring's shading, and the glint's warm white.
    static let gold = Color(red: 0xE9 / 255, green: 0xB4 / 255, blue: 0x5A / 255)
    static let deep = Color(red: 0x96 / 255, green: 0x62 / 255, blue: 0x16 / 255)
    static let glint = Color.white
    /// One turn, in seconds; and one pulse under Reduce Motion.
    static let turn = 1.15
    static let pulse = 1.6

    private var reduced: Bool {
        still ?? (reduceMotion || ProcessInfo.processInfo.arguments.contains("-t2p-reduce-motion"))
    }

    var body: some View {
        TimelineView(.animation) { t in
            let s = t.date.timeIntervalSinceReferenceDate
            let angle = reduced ? -60.0 : (s / Self.turn).truncatingRemainder(dividingBy: 1) * 360
            let glow = reduced ? 0.55 + 0.45 * (0.5 + 0.5 * cos(s * 2 * Double.pi / Self.pulse)) : 1.0
            ring(angle: angle).opacity(glow)
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier("spinner")
    }

    private func ring(angle: Double) -> some View {
        let line = max(2.5, size * 0.12)
        return ZStack {
            // the ring: gold, shaded deeper on one side so its turn shows
            Circle()
                .strokeBorder(AngularGradient(stops: [.init(color: Self.gold, location: 0), .init(color: Self.gold, location: 0.3),
                                                      .init(color: Self.deep, location: 0.68), .init(color: Self.gold, location: 1)],
                                              center: .center, startAngle: .degrees(0), endAngle: .degrees(360)),
                              lineWidth: line)
            // the glint: a short arc of light that brightens and fades along the ring
            Circle()
                .inset(by: line / 2)
                .trim(from: 0, to: 0.24)
                .stroke(AngularGradient(stops: [.init(color: Self.glint.opacity(0), location: 0),
                                                .init(color: Self.glint.opacity(0.55), location: 0.11),
                                                .init(color: Self.glint, location: 0.19),
                                                .init(color: Self.glint.opacity(0), location: 0.24),
                                                .init(color: Self.glint.opacity(0), location: 1)],
                                        center: .center, startAngle: .degrees(0), endAngle: .degrees(360)),
                        style: StrokeStyle(lineWidth: line * 0.8, lineCap: .butt))
        }
        .rotationEffect(.degrees(angle))
    }
}

/// The spinner at its sizes, turning and as Reduce Motion draws it, on the app's navy and on a light panel, for the
/// screenshots a simulator run takes (-t2p-spinner-gallery).
struct SpinnerGallery: View {
    static var requested: Bool { ProcessInfo.processInfo.arguments.contains("-t2p-spinner-gallery") }
    private let sizes: [CGFloat] = [20, 28, 40, 56, 80]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("Loading spinner").font(.title2.bold()).foregroundStyle(T2P.text)
                row("Turning", still: false)
                row("Reduce Motion: still, with a pulse", still: true)
                VStack(alignment: .leading, spacing: 10) {
                    Text("On a light panel").font(.headline).foregroundStyle(T2P.muted)
                    HStack(spacing: 22) { ForEach(sizes, id: \.self) { T2PSpinner(size: $0, still: false) } }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(hex: 0xF4F1EA), in: RoundedRectangle(cornerRadius: 16))
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Where it's used").font(.headline).foregroundStyle(T2P.muted)
                    HStack(spacing: 40) {
                        VStack(spacing: 16) {
                            T2PSpinner(size: 56, still: false)
                            Text("Opening room K7QP…").font(.headline).foregroundStyle(T2P.text)
                        }
                        T2PSpinner(size: 48, still: false).padding(24).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(T2P.navy.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("spinner-gallery")
    }

    private func row(_ title: String, still: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).foregroundStyle(T2P.muted)
            HStack(alignment: .center, spacing: 22) {
                ForEach(sizes, id: \.self) { s in
                    VStack(spacing: 6) {
                        T2PSpinner(size: s, still: still)
                        Text("\(Int(s)) pt").font(.caption.monospacedDigit()).foregroundStyle(T2P.faint)
                    }
                }
            }
        }
    }
}
