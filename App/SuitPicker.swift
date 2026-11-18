import SwiftUI
import T2PCore

/// Overdraft's suit chooser, painted like the cards (Tyler, Nov 18). Playing a Change Suit or a +4 raises four suit
/// medallions from your hand over a dimmed table: each suit's emblem from the cards in the cards' own colors, in a gold
/// rim, with its name in the game's serif and how many of it you hold. A tap flares the one you chose, drops the others,
/// and flies its emblem to the pile, where it lands in the suit's color; then the card goes down (a haptic tap and
/// the card sound come with it). Reduce Motion: plain fades. Used by both tables (3D and classic).

/// A wild waiting for its suit: the card, whether it's a jump-in, and whether its move has gone to the room yet.
struct WildPick: Equatable {
    let card: Overdraft.Card
    let jump: Bool
    var sent = false
    let token = UUID()
}

/// The suits' colors as the cards paint them (sampled from the card art's numbers: App/Art/<suit>_7.webp), light to
/// deep. The table's own palette (T2P.suit, the 3D scene) is the website's darker one; the medallions match the cards.
struct SuitPaint {
    let light: Color, mid: Color, deep: Color
    static func of(_ suit: String) -> SuitPaint {
        switch suit {
        case "ember": return SuitPaint(light: Color(hex: 0xFFA63D), mid: Color(hex: 0xF47F07), deep: Color(hex: 0xB04600))
        case "wave": return SuitPaint(light: Color(hex: 0x4FB0FF), mid: Color(hex: 0x017DE9), deep: Color(hex: 0x00489F))
        case "bolt": return SuitPaint(light: Color(hex: 0xC27BF2), mid: Color(hex: 0x9C37D7), deep: Color(hex: 0x5C1B90))
        case "leaf": return SuitPaint(light: Color(hex: 0x9BF58C), mid: Color(hex: 0x50E548), deep: Color(hex: 0x21922A))
        default: return SuitPaint(light: .white, mid: .gray, deep: .black)
        }
    }
}

/// A suit's emblem as the cards draw it in their corners: Ember's flame, Wave's curling crescent, Bolt's lightning,
/// Leaf's leaf with its rib. Drawn in a 24-point box and fitted to the frame, so it stays sharp at any size.
struct SuitEmblem: Shape {
    let suit: String

    func path(in rect: CGRect) -> Path {
        let (p, box) = Self.unit(suit)
        let s = min(rect.width / box.width, rect.height / box.height)
        let t = CGAffineTransform(translationX: rect.midX - box.midX * s, y: rect.midY - box.midY * s).scaledBy(x: s, y: s)
        return p.applying(t)
    }

    private static func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    /// The emblem in its 24-point box, and the part of the box it fills.
    static func unit(_ suit: String) -> (Path, CGRect) {
        switch suit {
        case "ember":
            var outer = Path()
            outer.move(to: pt(12, 2))
            outer.addCurve(to: pt(17, 11), control1: pt(13, 6), control2: pt(17, 7))
            outer.addCurve(to: pt(12, 16), control1: pt(17, 13.76), control2: pt(14.76, 16))
            outer.addCurve(to: pt(7, 11), control1: pt(9.24, 16), control2: pt(7, 13.76))
            outer.addCurve(to: pt(9, 7), control1: pt(7, 9), control2: pt(8, 8))
            outer.addCurve(to: pt(10.4, 9), control1: pt(9, 8.4), control2: pt(9.7, 9))
            outer.addCurve(to: pt(12, 2), control1: pt(11, 8), control2: pt(10.6, 5))
            outer.closeSubpath()
            var inner = Path()
            inner.move(to: pt(12.3, 8.9))
            inner.addCurve(to: pt(14.5, 13), control1: pt(12.8, 10.7), control2: pt(14.5, 11.4))
            inner.addCurve(to: pt(12, 14.9), control1: pt(14.5, 14.1), control2: pt(13.4, 14.9))
            inner.addCurve(to: pt(9.5, 12.9), control1: pt(10.6, 14.9), control2: pt(9.5, 14.1))
            inner.addCurve(to: pt(10.6, 10.9), control1: pt(9.5, 12), control2: pt(10, 11.4))
            inner.addCurve(to: pt(11.5, 12.1), control1: pt(10.7, 11.7), control2: pt(11.1, 12.1))
            inner.addCurve(to: pt(12.3, 8.9), control1: pt(11.9, 11.2), control2: pt(11.6, 10.1))
            inner.closeSubpath()
            return (outer.subtracting(inner), CGRect(x: 7, y: 2, width: 10, height: 14))
        case "wave":
            let outer = Path(ellipseIn: CGRect(x: 11.5 - 9.5, y: 12.5 - 9.5, width: 19, height: 19))
            let hole = Path(ellipseIn: CGRect(x: 14.6 - 6.4, y: 11.2 - 6.4, width: 12.8, height: 12.8))
            var curl = Path()
            curl.move(to: pt(13.6, 3.2))
            curl.addCurve(to: pt(17.4, 11.6), control1: pt(19.2, 3.6), control2: pt(20.6, 9.6))
            curl.addCurve(to: pt(14.3, 9.6), control1: pt(15.6, 12.7), control2: pt(13.6, 11.4))
            curl.addCurve(to: pt(16.2, 9.4), control1: pt(14.7, 8.6), control2: pt(15.9, 8.6))
            let curlShape = curl.strokedPath(StrokeStyle(lineWidth: 2.3, lineCap: .round, lineJoin: .round))
            return (outer.subtracting(hole).union(curlShape), CGRect(x: 2, y: 2.4, width: 19.4, height: 19.6))
        case "bolt":
            var p = Path()
            p.move(to: pt(13.4, 2)); p.addLine(to: pt(5, 13.2)); p.addLine(to: pt(9.9, 13.2)); p.addLine(to: pt(8.9, 22))
            p.addLine(to: pt(18, 10.4)); p.addLine(to: pt(12.8, 10.4)); p.closeSubpath()
            return (p, CGRect(x: 5, y: 2, width: 13, height: 20))
        default: // leaf
            var leaf = Path()
            leaf.move(to: pt(12, 1.5))
            leaf.addCurve(to: pt(12, 22.5), control1: pt(18.5, 6), control2: pt(19, 15.5))
            leaf.addCurve(to: pt(12, 1.5), control1: pt(5, 15.5), control2: pt(5.5, 6))
            leaf.closeSubpath()
            var rib = Path()
            rib.move(to: pt(12, 5.5)); rib.addLine(to: pt(12, 19.5))
            let ribShape = rib.strokedPath(StrokeStyle(lineWidth: 0.9, lineCap: .round))
            return (leaf.subtracting(ribShape), CGRect(x: 6.7, y: 1.5, width: 10.6, height: 21))
        }
    }
}

/// A suit's painted medallion: a gold rim, a card-dark face lit in the suit's color with the cards' arcane lines, four
/// small stars on the inner ring, and the emblem.
struct SuitMedallion: View {
    let suit: String
    let size: CGFloat
    /// 0...1: the flare when it's chosen.
    var glow: Double = 0
    /// 1: the whole medallion; toward 0, only the emblem is left (on its way to the pile).
    var rim: Double = 1

    var body: some View {
        let p = SuitPaint.of(suit), d = size
        ZStack {
            ZStack {
                Circle().fill(Painted.rimRing)
                Circle().fill(Color(hex: 0x0D0A10)).padding(d * 0.05)
                Circle()
                    .fill(RadialGradient(colors: [p.mid.opacity(0.55), p.deep.opacity(0.3), Color(hex: 0x140F18)],
                                         center: .center, startRadius: 0, endRadius: d * 0.44))
                    .padding(d * 0.065)
                CardLines(opacity: 0.22).clipShape(Circle()).padding(d * 0.065)
                Circle().strokeBorder(Painted.rim, lineWidth: max(1, d * 0.01)).padding(d * 0.095)
                ForEach(0..<4, id: \.self) { i in
                    CardStar().fill(Painted.goldLight)
                        .frame(width: d * 0.075, height: d * 0.075)
                        .offset(y: -d * 0.405)
                        .rotationEffect(.degrees(Double(i) * 90))
                }
                Ellipse()
                    .fill(LinearGradient(colors: [.white.opacity(0.17), .clear], startPoint: .top, endPoint: .bottom))
                    .frame(width: d * 0.68, height: d * 0.34)
                    .offset(y: -d * 0.24)
            }
            .opacity(rim)
            SuitEmblem(suit: suit)
                .fill(LinearGradient(colors: [p.light, p.mid, p.deep], startPoint: .top, endPoint: .bottom))
                .overlay(SuitEmblem(suit: suit).stroke(p.light.opacity(0.75), lineWidth: max(0.8, d * 0.008)))
                .frame(width: d * 0.5, height: d * 0.5)
                .shadow(color: p.mid.opacity(0.85 + 0.15 * glow), radius: d * CGFloat(0.05 + 0.08 * glow))
                .shadow(color: .black.opacity(0.55 * rim), radius: d * 0.015, y: d * 0.012)
        }
        .frame(width: d, height: d)
        .shadow(color: p.mid.opacity((0.3 + 0.55 * glow) * max(rim, glow)), radius: d * CGFloat(0.07 + 0.18 * glow))
        .shadow(color: .black.opacity(0.5 * rim), radius: d * 0.06, y: d * 0.04)
        .accessibilityHidden(true)
    }
}

/// UI tests' stills of the chooser (-t2p-pick-still): the chooser stops at fixed moments, one after another, and a
/// small test-only button (pick-next) moves it to the next: partway up, settled, Ember's flare, Wave's emblem in flight,
/// Leaf's landing on the pile. Nothing is sent. -t2p-reduce-motion turns motion off.
enum SuitPickerStill {
    struct Frame { let rise: Double; let go: Double; let suit: String? }
    static let frames: [Frame] = [
        Frame(rise: 0.42, go: 0, suit: nil), Frame(rise: 1, go: 0, suit: nil),
        Frame(rise: 1, go: 0.18, suit: "ember"), Frame(rise: 1, go: 0.55, suit: "wave"), Frame(rise: 1, go: 0.9, suit: "leaf"),
    ]
    static let on = ProcessInfo.processInfo.arguments.contains("-t2p-pick-still")
    static var reduceMotion: Bool { ProcessInfo.processInfo.arguments.contains("-t2p-reduce-motion") }
}

struct SuitPicker: View {
    let hand: [Overdraft.Card]
    var wild4 = false
    /// The pile's middle, in global (screen) points: where the emblem lands. Nil: a little above the middle.
    let pile: CGPoint?
    /// A jump-in goes to the room at the tap (the first jump to reach the room plays); a turn's play goes when the
    /// emblem lands.
    var sendAtTap = false
    let onPick: (String) -> Void
    let onDone: () -> Void

    @State private var rise = 0.0
    @State private var go = 0.0
    @State private var picked: String?
    @State private var centers: [String: CGPoint] = [:]
    @State private var origin: CGPoint = .zero
    @State private var stillFrame = 0
    @Environment(\.accessibilityReduceMotion) private var systemReduce
    @Environment(\.horizontalSizeClass) private var hsize
    private var reduced: Bool { systemReduce || SuitPickerStill.reduceMotion }

    private static func clamp(_ v: Double) -> Double { min(1, max(0, v)) }

    var body: some View {
        GeometryReader { g in
            let d = medallionSize(g.size)
            let target = pile.map { CGPoint(x: $0.x - origin.x, y: $0.y - origin.y) } ?? CGPoint(x: g.size.width / 2, y: g.size.height * 0.36)
            ZStack {
                dim
                VStack(spacing: hsize == .regular ? 18 : 12) {
                    header
                    grid(d, target: target)
                    Button("Back") { cancel() }
                        .buttonStyle(PaintedButtonStyle(kind: .quiet))
                        .frame(maxWidth: 240)
                        .opacity(chromeOpacity)
                        .disabled(picked != nil)
                        .accessibilityIdentifier("suit-back")
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                landing(d, at: target)
                if SuitPickerStill.on {
                    Button { showStill(stillFrame + 1) } label: {
                        Color.white.opacity(0.03).frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .position(x: 24, y: g.size.height - 24)
                    .accessibilityLabel("Next still")
                    .accessibilityIdentifier("pick-next")
                }
            }
            .frame(width: g.size.width, height: g.size.height)
        }
        .onGeometryChange(for: CGPoint.self) { $0.frame(in: .global).origin } action: { origin = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("suit-picker")
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { cancel() }
        .onAppear(perform: appeared)
    }

    private func medallionSize(_ s: CGSize) -> CGFloat {
        let regular = hsize == .regular
        let byWidth = (s.width - 40 - (regular ? 28 : 18)) / 2
        let byHeight = (s.height - (regular ? 300 : 250)) / 2 - (regular ? 50 : 44)
        return max(92, min(regular ? 178 : 142, byWidth, byHeight))
    }

    private var chromeOpacity: Double {
        Self.clamp((rise - 0.25) / 0.5) * (1 - Self.clamp(go / 0.2))
    }

    private var dim: some View {
        let shown = min(1, rise) * (1 - Self.clamp((go - 0.55) / 0.4))
        let tint = picked.map { SuitPaint.of($0).mid } ?? .clear
        return ZStack {
            Color(hex: 0x07050A).opacity(0.72)
            RadialGradient(colors: [tint.opacity(0.22 * Self.clamp(go / 0.3)), .clear], center: .center, startRadius: 20, endRadius: 420)
        }
        .opacity(shown)
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { cancel() }
        .accessibilityHidden(true)
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("NAME THE SUIT")
                .font(Painted.display(hsize == .regular ? 26 : 22)).tracking(2.4)
                .foregroundStyle(Painted.titleGold)
                .shadow(color: .black.opacity(0.8), radius: 4)
                .accessibilityAddTraits(.isHeader)
            PaintedDivider()
            Text(wild4 ? "Then the pile passes to the next player." : "Play goes on in the suit you name.")
                .font(.subheadline).foregroundStyle(Painted.paperDim)
                .shadow(color: .black.opacity(0.8), radius: 3)
                .multilineTextAlignment(.center)
        }
        .opacity(chromeOpacity)
    }

    private func grid(_ d: CGFloat, target: CGPoint) -> some View {
        let gap: CGFloat = hsize == .regular ? 28 : 18
        // the Change Suit card's own layout: Ember and Wave on top, Bolt and Leaf below
        return VStack(spacing: gap * 0.6) {
            ForEach([0, 2], id: \.self) { row in
                HStack(spacing: gap) {
                    ForEach([row, row + 1], id: \.self) { i in cell(i, d, target: target) }
                }
            }
        }
    }

    private func cell(_ i: Int, _ d: CGFloat, target: CGPoint) -> some View {
        let s = Overdraft.suits[i]
        // the cells' middles are measured on screen; the pile, made local the same way
        let c = centers[s].map { CGPoint(x: $0.x - origin.x, y: $0.y - origin.y) } ?? target
        let n = hand.filter { $0.suit == s && !$0.isWild }.count
        return MedallionSlot(suit: s, index: i, size: d, count: n,
                             chosen: picked.map { $0 == s },
                             flight: CGSize(width: target.x - c.x, height: target.y - c.y),
                             reduced: reduced, rise: rise, go: go) { pick(s) }
            .frame(width: d + 12, height: d + d * 0.2 + 30, alignment: .top)
            .onGeometryChange(for: CGPoint.self) { p in
                let f = p.frame(in: .global)
                return CGPoint(x: f.midX, y: f.minY + d / 2)
            } action: { centers[s] = $0 }
            .zIndex(picked == s ? 2 : 0)
    }

    /// Where the emblem lands: a ring of the suit's color opening out over the pile.
    @ViewBuilder private func landing(_ d: CGFloat, at target: CGPoint) -> some View {
        if let s = picked, !reduced {
            let l = Self.clamp((go - 0.8) / 0.2)
            let p = SuitPaint.of(s)
            ZStack {
                Circle().fill(RadialGradient(colors: [p.light.opacity(0.75), p.mid.opacity(0.35), .clear], center: .center, startRadius: 0, endRadius: d * 0.5))
                    .frame(width: d, height: d)
                    .scaleEffect(0.5 + 0.9 * l)
                    .opacity(l < 1 ? (l > 0 ? 1 - l * 0.7 : 0) : 0)
                Circle().stroke(p.mid, lineWidth: 4)
                    .frame(width: d * 0.6, height: d * 0.6)
                    .scaleEffect(0.6 + 1.4 * l)
                    .opacity(l > 0 ? 1 - l : 0)
            }
            .position(target)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func appeared() {
        if SuitPickerStill.on { showStill(0); return }
        Haptics.select()
        withAnimation(reduced ? Animation.easeOut(duration: 0.2) : Animation.spring(duration: 0.6, bounce: 0.3)) { rise = 1 }
        UIAccessibility.post(notification: .screenChanged, argument: "Name the suit")
    }

    private func showStill(_ i: Int) {
        let f = SuitPickerStill.frames[min(i, SuitPickerStill.frames.count - 1)]
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { stillFrame = i; rise = f.rise; go = f.go; picked = f.suit }
    }

    private func pick(_ s: String) {
        guard picked == nil, !SuitPickerStill.on else { return }
        picked = s
        Haptics.select()
        if reduced {
            onPick(s)
            withAnimation(.easeOut(duration: 0.22)) { go = 1 } completion: { onDone() }
            return
        }
        if sendAtTap { onPick(s) }
        withAnimation(.linear(duration: 0.85)) { go = 1 } completion: {
            if sendAtTap { Haptics.play() } else { onPick(s) }
            onDone()
        }
    }

    private func cancel() {
        guard picked == nil, !SuitPickerStill.on else { return }
        Haptics.select()
        onDone()
    }
}

/// One medallion in the chooser, moved by the chooser's two clocks: `rise` (0 to 1 as they come up, one after
/// another) and `go` (0 to 1 after a tap: the flare, the others falling, the flight to the pile).
private struct MedallionSlot: View, Animatable {
    let suit: String
    let index: Int
    let size: CGFloat
    let count: Int
    /// nil: nothing chosen yet; true: this one was chosen; false: another was.
    let chosen: Bool?
    /// From this medallion's middle to the pile.
    let flight: CGSize
    let reduced: Bool
    var rise: Double
    var go: Double
    let tap: () -> Void

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(rise, go) }
        set { rise = newValue.first; go = newValue.second }
    }

    private struct Motion { var x = 0.0, y = 0.0, scale = 1.0, turn = 0.0, opacity = 1.0, glow = 0.0, rim = 1.0, label = 1.0, burst = 0.0 }

    private static func clamp(_ v: Double) -> Double { min(1, max(0, v)) }

    private var motion: Motion {
        var m = Motion()
        let side: Double = index % 2 == 0 ? -1 : 1
        if reduced {
            m.opacity = Self.clamp(rise) * (1 - Self.clamp(go))
            m.label = m.opacity
            return m
        }
        // the rise: up from your hand, one after another, turning straight as they arrive
        // each one's own 0...1 (the first starts first), plus the spring's overshoot past 1 for all of them alike
        let r = min(1, max(0, (rise - 0.09 * Double(index)) / 0.73)) + max(0, rise - 1)
        m.y = (1 - r) * 280
        m.scale = 0.45 + 0.55 * r
        m.turn = (1 - r) * 16 * side
        m.opacity = min(1, r * 1.8)
        m.label = Self.clamp(r * 1.6 - 0.4)
        guard let chosen else { return m }
        if chosen {
            let f = Self.clamp(go / 0.22), e = 1 - (1 - f) * (1 - f)
            let t = Self.clamp((go - 0.2) / 0.62), p = t * t * (3 - 2 * t)
            m.glow = e
            m.burst = Self.clamp(go / 0.4)
            // over the top and down onto the pile
            let cx = Double(flight.width) * 0.5, cy = Double(flight.height) * 0.5 - 110
            m.x += 2 * (1 - p) * p * cx + p * p * Double(flight.width)
            m.y += 2 * (1 - p) * p * cy + p * p * Double(flight.height)
            let land = Self.clamp((go - 0.82) / 0.18)
            m.scale = (1 + 0.16 * e) * (1 - 0.66 * p) * (1 + 0.5 * land)
            m.rim = 1 - Self.clamp((go - 0.35) / 0.3)
            m.label = 1 - Self.clamp((go - 0.1) / 0.15)
            m.opacity = 1 - land
        } else {
            let q = Self.clamp(go / 0.42)
            m.y += 240 * q * q
            m.x += 40 * side * q
            m.turn += 22 * side * q
            m.scale *= 1 - 0.18 * q
            m.opacity *= 1 - q
            m.label *= 1 - q
        }
        return m
    }

    var body: some View {
        let m = motion
        let name = Overdraft.suitNames[suit] ?? suit
        let p = SuitPaint.of(suit)
        return Button(action: tap) {
            VStack(spacing: 0) {
                SuitMedallion(suit: suit, size: size, glow: m.glow, rim: m.rim)
                    .overlay {
                        Circle().stroke(p.light, lineWidth: 3)
                            .scaleEffect(1 + 0.8 * m.burst)
                            .opacity(m.burst > 0 && m.burst < 1 ? 1 - m.burst : 0)
                    }
                VStack(spacing: 3) {
                    Text(name.uppercased())
                        .font(Painted.display(max(14, size * 0.12)))
                        .tracking(max(1.5, size * 0.018))
                        .foregroundStyle(Painted.paper)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .padding(.horizontal, 16).padding(.vertical, 5)
                        .background(Capsule().fill(LinearGradient(colors: [Color(hex: 0x2C2334), Color(hex: 0x15101B)], startPoint: .top, endPoint: .bottom)))
                        .overlay(Capsule().strokeBorder(Painted.rim, lineWidth: 1.2))
                        .shadow(color: .black.opacity(0.6), radius: 4, y: 2)
                    Text("\(count) in hand")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Painted.paperDim)
                        .shadow(color: .black.opacity(0.9), radius: 3)
                }
                .offset(y: -size * 0.1)
                .opacity(m.label)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(MedallionPress())
        .disabled(chosen != nil)
        .scaleEffect(m.scale)
        .rotationEffect(.degrees(m.turn))
        .offset(x: m.x, y: m.y)
        .opacity(m.opacity)
        .accessibilityLabel(name)
        .accessibilityValue("\(count) in hand")
        .accessibilityHint("Names \(name) as the suit to match")
        .accessibilityIdentifier("suit-\(suit)")
    }
}

/// A medallion under your finger lifts a little.
private struct MedallionPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 1.05 : 1)
            .brightness(configuration.isPressed ? 0.06 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
