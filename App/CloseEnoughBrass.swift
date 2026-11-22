import SwiftUI
import UIKit
import T2PCore

/// #726 (Tyler, Nov 22: "Can you not see the Close Enough game on my website? It looks nothing like it."): Close
/// Enough's phone screens drawn as the Library game on tyleralocke.com draws itself, the brass instrument Tyler made
/// (in the website repo: scripts/library-fixes/close-enough/range.html, house.css and house.js, built over
/// vendor/builtbytl/public/downloads/close-enough.html). #707 had copied time2play.live's plain room page instead.
/// The near-black ground in a chamfered brass frame with a screw in each corner; "Close Enough" and the question in
/// serif; the engraved brass nameplate with two screws that reads the range; two tall grooved brass handles riding a
/// recessed brass channel, the plate glowing between them; the brass ruler with its numbers and the unit at each end;
/// the points (with the values it falls to as the range widens) and the clock on one line; the brass Lock button and
/// "Type exact numbers". At the answer, a brass needle drops onto the track and the result opens where the readout
/// was. The standings are a line of chips at the top, as the Library's teams are, and rows under the instrument.
/// The serif is the Library's own first choice, Iowan Old Style, which ships with iOS (so nothing to bundle or
/// license; Safari on an iPhone draws the Library game in it too). Native where it has to be: safe areas, haptics,
/// VoiceOver (each handle is adjustable), Dynamic Type up to xxxLarge, Reduce Motion (the glow stays still and the
/// needle doesn't drop), and the room code opens the room menu. The 3D board stays behind You → "3D Close Enough board".
enum Brass {
    // house.css :root (the House look), and the file's own colors for the result
    static let m0 = Color(hex: 0x0B0A08), m1 = Color(hex: 0x13110D), m2 = Color(hex: 0x1C1913), m3 = Color(hex: 0x29241A)
    static let ink = Color(hex: 0xF5ECD6), ink2 = Color(hex: 0xD2C5A6), ink3 = Color(hex: 0xB3A585)
    static let brass = Color(hex: 0xD7A64B), brassLit = Color(hex: 0xF3CF80)
    static let brassDim = Color(red: 215 / 255, green: 166 / 255, blue: 75 / 255).opacity(0.14)
    static let line = Color(hex: 0x3A3223)
    static let panel = Color(hex: 0x0F0D0A), panelLine = Color(hex: 0x3F3524), resultLine = Color(hex: 0x6B5228)
    static let mastLine = Color(hex: 0x4A3E27)
    static let tri = Color(hex: 0xF79D23)
    static let qInk = Color(hex: 0xF0E2C1), plateInk = Color(hex: 0x2A1803), actInk = Color(hex: 0x1A1D16)
    static let hit = Color(hex: 0x7BC47F), miss = Color(hex: 0xD97B6C), tight = Color(hex: 0x8FD4C4)
    static let hitText = Color(hex: 0x9FE0A3), missText = Color(hex: 0xEDA093), low = Color(hex: 0xF0A08F)
    static let ghost = Color(hex: 0xCBB489)

    static let brassHex: UInt32 = 0xD7A64B, litHex: UInt32 = 0xF3CF80, deepHex: UInt32 = 0x3A1200

    /// CSS color-mix(in srgb, a p%, b).
    static func mix(_ a: UInt32, _ p: Double, _ b: UInt32) -> Color {
        func c(_ h: UInt32, _ s: UInt32) -> Double { Double((h >> s) & 0xFF) / 255 }
        return Color(red: c(a, 16) * p + c(b, 16) * (1 - p), green: c(a, 8) * p + c(b, 8) * (1 - p), blue: c(a, 0) * p + c(b, 0) * (1 - p))
    }

    /// The reader's text size, capped at xxxLarge (the cap the tables use), applied to a size in points.
    static func scaled(_ size: CGFloat, _ style: Font.TextStyle) -> CGFloat {
        let now = UIApplication.shared.preferredContentSizeCategory
        let capped: UIContentSizeCategory = now > .extraExtraExtraLarge ? .extraExtraExtraLarge : now
        let traits = UITraitCollection(preferredContentSizeCategory: capped == .unspecified ? .large : capped)
        return UIFontMetrics(forTextStyle: uiStyle(style)).scaledValue(for: size, compatibleWith: traits)
    }

    private static func uiStyle(_ s: Font.TextStyle) -> UIFont.TextStyle {
        switch s {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .callout: return .callout
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        default: return .body
        }
    }

    /// The Library's serif: "Iowan Old Style", then New York if a phone ever lacks it. Iowan has a roman and a bold, so
    /// 600 and up draw bold, as Safari picks them.
    static func serifName(_ weight: Font.Weight) -> String {
        weight == .semibold || weight == .bold || weight == .heavy || weight == .black ? "IowanOldStyle-Bold" : "IowanOldStyle-Roman"
    }
    static let hasIowan = UIFont(name: "IowanOldStyle-Roman", size: 12) != nil
    /// For UI tests: which serif the screens are drawn in.
    static var serifInUse: String { hasIowan ? "Iowan Old Style" : "New York (Iowan Old Style missing)" }
    static func serifFixed(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        hasIowan ? .custom(serifName(weight), fixedSize: size) : .system(size: size, weight: weight, design: .serif)
    }
    /// Serif text that grows with the reader's text size.
    static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular, _ style: Font.TextStyle = .body) -> Font {
        serifFixed(scaled(size, style), weight)
    }
    /// The file's sans (system-ui on an iPhone) and mono.
    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular, _ style: Font.TextStyle = .body) -> Font {
        .system(size: scaled(size, style), weight: weight)
    }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular, _ style: Font.TextStyle = .caption) -> Font {
        .system(size: scaled(size, style), weight: weight, design: .monospaced)
    }

    /// The gold numbers, cut from brass.
    static let goldText = LinearGradient(stops: [.init(color: Color(hex: 0xF8E3AB), location: 0), .init(color: Color(hex: 0xE4BE72), location: 0.42),
                                                 .init(color: Color(hex: 0xB98A3E), location: 0.7), .init(color: Color(hex: 0xE8C780), location: 1)],
                                         startPoint: .top, endPoint: .bottom)

    /// The page: a warm light high in the middle, near-black toward the edges.
    static var background: some View {
        ZStack {
            m0
            RadialGradient(colors: [Color(hex: 0x15120D), m0], center: UnitPoint(x: 0.5, y: 0), startRadius: 0, endRadius: 700)
        }
        .ignoresSafeArea()
    }

    // ---- numbers, as house.js writes them ----
    static func decimals(_ q: CloseEnough.Question) -> Int {
        let s = q.step > 0 ? q.step : 1
        return s >= 1 ? 0 : min(6, Int((-log10(s) - 1e-9).rounded(.up)))
    }
    static func fmt(_ v: Double, _ q: CloseEnough.Question) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.locale = Locale(identifier: "en_US")
        f.maximumFractionDigits = decimals(q)
        // a year reads 1969, not 1,969 (as T2PCore's format)
        f.usesGroupingSeparator = !(q.unit.isEmpty && v >= 1000 && v <= 2100 && v.rounded() == v)
        return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }
    static func joinUnit(_ u: String) -> String { u.isEmpty ? "" : (u.hasPrefix("%") || u.hasPrefix("°")) ? u : " " + u }
    static func withUnit(_ v: Double, _ q: CloseEnough.Question) -> String { fmt(v, q) + joinUnit(q.unit) }
    /// "12 — 22 liters": the unit once, at the end (on both when it hugs the number, as % and ° do).
    static func rangeText(_ lo: Double, _ hi: Double, _ q: CloseEnough.Question) -> String {
        (q.unit.hasPrefix("%") || q.unit.hasPrefix("°")) ? withUnit(lo, q) + " — " + withUnit(hi, q)
            : fmt(lo, q) + " — " + fmt(hi, q) + joinUnit(q.unit)
    }
    /// The ruler's numbers: 12k, 1.5M.
    static func short(_ v: Double, _ q: CloseEnough.Question) -> String {
        let a = abs(v)
        func trim(_ x: Double, _ d: Int) -> String { let s = String(format: "%.\(d)f", x); return s.hasSuffix(".0") ? String(s.dropLast(2)) : s }
        if a >= 1e6 { return trim(v / 1e6, a.truncatingRemainder(dividingBy: 1e6) == 0 ? 0 : 1) + "M" }
        if a >= 1e4 { return trim(v / 1e3, a.truncatingRemainder(dividingBy: 1e3) == 0 ? 0 : 1) + "k" }
        return fmt(v, q)
    }
    static func niceStep(_ raw: Double) -> Double {
        guard raw > 0 else { return 1 }
        let p = pow(10, (log10(raw)).rounded(.down)), m = raw / p
        return (m <= 1 ? 1 : m <= 2 ? 2 : m <= 5 ? 5 : 10) * p
    }
}

/// A brass screw head (house.css --ce-screw).
struct BrassScrew: View {
    var size: CGFloat = 16
    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(stops: [.init(color: Color(hex: 0xFBE3A4), location: 0), .init(color: Color(hex: 0xC4923E), location: 0.55),
                                                 .init(color: Color(hex: 0x5C4317), location: 1)],
                                         center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.75))
            Circle().strokeBorder(Color(hex: 0x382809), lineWidth: max(0.6, size / 20))
            Capsule().fill(Color(hex: 0x382809)).frame(width: size * 0.62, height: max(1, size * 0.11)).rotationEffect(.degrees(-45))
            Capsule().fill(Color(hex: 0xFBE3A4).opacity(0.45)).frame(width: size * 0.62, height: max(0.5, size * 0.04))
                .offset(x: size * 0.03, y: size * 0.03).rotationEffect(.degrees(-45))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The chamfered panel's outline (house.css --ce-frame).
struct ChamferShape: InsettableShape {
    var cut: CGFloat
    var inset: CGFloat = 0
    func path(in r: CGRect) -> Path {
        let r = r.insetBy(dx: inset, dy: inset), c = max(0, cut - inset * 0.4)
        var p = Path()
        p.move(to: CGPoint(x: r.minX + c, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX - c, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + c)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c))
        p.addLine(to: CGPoint(x: r.maxX - c, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX + c, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - c)); p.addLine(to: CGPoint(x: r.minX, y: r.minY + c))
        p.closeSubpath()
        return p
    }
    func inset(by amount: CGFloat) -> ChamferShape { var s = self; s.inset += amount; return s }
}

/// The brass case the screen sits in: the chamfered frame, its inner gold rule and a screw in each corner.
struct BrassCase: View {
    var body: some View {
        ZStack {
            ChamferShape(cut: 14).fill(Color(hex: 0x120F0B))
            ChamferShape(cut: 14).strokeBorder(Color(hex: 0x8B6A2E), lineWidth: 1.5)
            ChamferShape(cut: 14, inset: 5.5).stroke(Brass.brass.opacity(0.3), lineWidth: 1)
            GeometryReader { g in
                let s: CGFloat = 11, i: CGFloat = 15 + s / 2
                ForEach(0..<4, id: \.self) { k in
                    BrassScrew(size: s).position(x: k % 2 == 0 ? i : g.size.width - i, y: k < 2 ? i : g.size.height - i)
                }
            }
        }
        .shadow(color: .black.opacity(0.6), radius: 30, y: 30)
        .accessibilityHidden(true)
    }
}

/// `.act`: the file's brass button (Next question, Play again); `ghost` is its outlined one.
struct BrassActButton: ButtonStyle {
    var ghost = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Brass.sans(16, .bold, .headline)).foregroundStyle(ghost ? Brass.ink : Brass.actInk)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 50).padding(.horizontal, 16)
            .background(ghost ? (configuration.isPressed ? Brass.m2 : Color.clear) : (configuration.isPressed ? Brass.brassLit : Brass.brass),
                        in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(ghost ? Brass.line : Brass.brass, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 9))
            .opacity(enabled ? 1 : 0.35)
    }
}

/// "Lock in this range": engraved brass.
struct BrassLockButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        let lit = configuration.isPressed
        configuration.label
            .font(Brass.serif(18, .bold, .headline)).tracking(0.7).foregroundStyle(Brass.plateInk)
            .shadow(color: Color(red: 1, green: 236 / 255, blue: 190 / 255).opacity(0.6), radius: 0, y: 1)
            .frame(maxWidth: .infinity, minHeight: 50).padding(.horizontal, 16)
            .background(
                LinearGradient(stops: [.init(color: Color(hex: lit ? 0xF8DEA0 : 0xF3D48E), location: 0), .init(color: Color(hex: lit ? 0xE2B660 : 0xD8A952), location: 0.36),
                                       .init(color: Color(hex: lit ? 0xBD8A36 : 0xB38030), location: 0.64), .init(color: Color(hex: lit ? 0xD8A44E : 0xCD9945), location: 1)],
                               startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(hex: 0x4A3209), lineWidth: 1))
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 8).fill(Color(red: 1, green: 246 / 255, blue: 218 / 255).opacity(0.85)).frame(height: 1).padding(.horizontal, 6).padding(.top, 1)
            }
            .shadow(color: .black.opacity(0.55), radius: 11, y: 8)
            .shadow(color: Color(red: 240 / 255, green: 190 / 255, blue: 100 / 255).opacity(0.14), radius: 12)
            .opacity(enabled ? 1 : 0.4)
    }
}

/// `.tbtn` (the masthead's small button) and the reaction chips.
struct BrassSmallButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Brass.sans(13, .semibold, .footnote)).foregroundStyle(configuration.isPressed ? Brass.ink : Brass.ink2)
            .padding(.horizontal, 12).frame(minHeight: 34)
            .background(Brass.m2, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Brass.line, lineWidth: 1))
            .frame(minHeight: 44).contentShape(Rectangle())
    }
}

/// The engraved nameplate: the range, live, and under it "YOUR RANGE", or at the answer "Answer: 9 liters".
struct BrassNameplate: View {
    let range: String
    let line: String
    var empty = false
    var revealed = false
    var lineId = "ce-plate-line"
    var body: some View {
        let nf: CGFloat = 27
        VStack(spacing: revealed ? 0 : 2) {
            Text(range)
                .accessibilityIdentifier("ce-range")
                .font(empty ? Brass.serifFixed(nf * 0.62, .regular).italic() : Brass.serifFixed(nf, .bold))
                .monospacedDigit()
            Text(revealed ? line : line.uppercased())
                .font(Brass.serifFixed(revealed ? nf * 0.56 : nf * 0.36, .bold)).tracking(revealed ? 0.2 : nf * 0.36 * 0.16)
                .opacity(revealed ? 1 : 0.75)
                .accessibilityIdentifier(lineId)
        }
        .lineLimit(1).minimumScaleFactor(0.45)
        .foregroundStyle(Brass.plateInk)
        .shadow(color: Color(red: 1, green: 236 / 255, blue: 190 / 255).opacity(0.55), radius: 0, y: 1)
        .padding(.horizontal, 36)
        .frame(maxWidth: .infinity).frame(height: nf * 2.3 + 12)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(LinearGradient(stops: [
                .init(color: Brass.mix(Brass.litHex, 0.8, 0xFFFFFF), location: 0),
                .init(color: Brass.mix(Brass.brassHex, 0.7, Brass.litHex), location: 0.3),
                .init(color: Brass.brass, location: 0.58),
                .init(color: Brass.mix(Brass.brassHex, 0.8, 0x000000), location: 1)], startPoint: .top, endPoint: .bottom)))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color(red: 60 / 255, green: 36 / 255, blue: 4 / 255).opacity(0.32), lineWidth: 1).padding(.horizontal, 28).padding(.vertical, 5))
        .overlay(alignment: .top) { Rectangle().fill(Color(red: 1, green: 246 / 255, blue: 218 / 255).opacity(0.85)).frame(height: 1).padding(.horizontal, 8) }
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Brass.mix(Brass.brassHex, 0.32, 0x000000), lineWidth: 1))
        .overlay(HStack { BrassScrew(size: 12); Spacer(); BrassScrew(size: 12) }.padding(.horizontal, 11))
        .shadow(color: .black.opacity(0.55), radius: 13, y: 10)
        .shadow(color: Brass.brassLit.opacity(0.16), radius: 17)
        .accessibilityElement(children: .contain)
    }
}

/// One brass handle: grooved at the top, a screw head near the bottom.
struct BrassKnob: View {
    let w: CGFloat, h: CGFloat
    var dim = false
    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 8).fill(LinearGradient(stops: [
                .init(color: Brass.mix(Brass.brassHex, 0.42, 0), location: 0), .init(color: Brass.mix(Brass.brassHex, 0.82, 0), location: 0.14),
                .init(color: Brass.mix(Brass.brassHex, 0.7, 0xFFFFFF), location: 0.4), .init(color: Brass.brass, location: 0.62),
                .init(color: Brass.mix(Brass.brassHex, 0.38, 0), location: 1)], startPoint: .leading, endPoint: .trailing))
            // the grooves
            HStack(spacing: 0) {
                ForEach(0..<max(1, Int((w * 0.52) / 4.6)), id: \.self) { _ in
                    HStack(spacing: 0) {
                        Rectangle().fill(Color(red: 38 / 255, green: 22 / 255, blue: 3 / 255).opacity(0.7)).frame(width: 1.5)
                        Rectangle().fill(Color(red: 1, green: 236 / 255, blue: 190 / 255).opacity(0.42)).frame(width: 1.1)
                        Color.clear.frame(width: 2)
                    }
                }
            }
            .frame(width: w * 0.52, height: h * 0.38, alignment: .center).clipped()
            .mask(LinearGradient(stops: [.init(color: .black, location: 0.7), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
            .padding(.top, h * 0.08)
            // the screw
            ZStack {
                Circle().fill(RadialGradient(stops: [.init(color: Brass.mix(Brass.litHex, 0.6, 0xFFFFFF), location: 0), .init(color: Brass.brass, location: 0.5),
                                                     .init(color: Brass.mix(Brass.brassHex, 0.4, 0), location: 1)],
                                             center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: h * 0.12))
                Rectangle().fill(Color(red: 38 / 255, green: 22 / 255, blue: 3 / 255).opacity(0.75)).frame(width: h * 0.157, height: max(1, h * 0.016)).rotationEffect(.degrees(45))
                Rectangle().fill(Color(red: 38 / 255, green: 22 / 255, blue: 3 / 255).opacity(0.75)).frame(width: h * 0.157, height: max(1, h * 0.016)).rotationEffect(.degrees(-45))
                Circle().strokeBorder(Color(red: 38 / 255, green: 22 / 255, blue: 3 / 255).opacity(0.45), lineWidth: 1)
            }
            .frame(width: h * 0.157, height: h * 0.157).clipShape(Circle())
            .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, h * 0.093)
        }
        .frame(width: w, height: h)
        .overlay(alignment: .top) { Rectangle().fill(Color(red: 1, green: 244 / 255, blue: 214 / 255).opacity(0.6)).frame(height: 1).padding(.horizontal, 4) }
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Brass.mix(Brass.brassHex, 0.28, 0), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.62), radius: 11, y: 10)
        .saturation(dim ? 0.7 : 1).brightness(dim ? -0.12 : 0)
    }
}

/// The instrument: the channel, the glowing plate between the handles, the needle at the answer, the two handles, and
/// the ruler with the unit at each end. Drag either handle; drag the plate to move both; press the track to bring the
/// nearer handle there. Every value snaps to the question's step, and the range never turns inside out (house.js).
struct BrassInstrument: View {
    let q: CloseEnough.Question
    @Binding var lo: Double
    @Binding var hi: Double
    var enabled = true
    var answer: Double? = nil
    var verdict: String? = nil       // "miss" greys the plate; a hit glows brighter
    var landed = true
    var kh: CGFloat = 96
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grab: Grab?
    @State private var breathe = false

    private enum Grab { case lo, hi, both(start: Double, lo: Double, hi: Double), free(pivot: Double) }

    private var kw: CGFloat { kh * 0.346 }
    private var res: CGFloat { kh * 0.21 }
    private var ph: CGFloat { kh * 0.577 }
    private var rh: CGFloat { kh * 0.346 }
    private var margin: CGFloat { kw / 2 + 4 }
    private var span: Double { max(1e-9, q.ceiling - q.floor) }
    private func frac(_ v: Double) -> CGFloat { CGFloat(min(1, max(0, (v - q.floor) / span))) }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { g in
                let W = max(1, g.size.width - 2 * margin)
                let x = { (v: Double) in margin + frac(v) * W }
                ZStack(alignment: .topLeading) {
                    rail.frame(width: g.size.width, height: rh).offset(y: res + kh - rh + 4)
                    plate.frame(width: max(0, x(hi) - x(lo)), height: ph).offset(x: x(lo), y: res + 6)
                    if let answer { needle.offset(x: x(answer) - 3, y: landed ? res - 12 : res - 60).opacity(landed ? 1 : 0) }
                    knob("lo", lo, lowLabel).offset(x: x(lo) - kw / 2, y: res).zIndex(frac(lo) > 0.5 ? 5 : 4)
                    knob("hi", hi, highLabel).offset(x: x(hi) - kw / 2, y: res).zIndex(frac(lo) > 0.5 ? 4 : 5)
                }
                .frame(width: g.size.width, height: res + kh + 8, alignment: .topLeading)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { d in drag(d, W) }.onEnded { _ in grab = nil })
            }
            .frame(height: res + kh + 8)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("ce-track")
            BrassRuler(q: q).frame(height: 50).padding(.horizontal, margin).padding(.top, 4)
            HStack { Text(Brass.withUnit(q.floor, q)); Spacer(); Text(Brass.withUnit(q.ceiling, q)) }
                .font(Brass.serifFixed(15)).foregroundStyle(Brass.mix(Brass.litHex, 0.45, 0xD2C5A6))
                .lineLimit(1).minimumScaleFactor(0.7)
                .padding(.horizontal, max(0, kw / 2 - 20)).padding(.top, 2)
                .accessibilityHidden(true)
        }
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { breathe = true } }
    }

    private var lowLabel: String { "Low end of your range" }
    private var highLabel: String { "High end of your range" }

    private var rail: some View {
        ZStack {
            Capsule().fill(LinearGradient(stops: [
                .init(color: Brass.mix(Brass.brassHex, 0.72, 0), location: 0), .init(color: Brass.mix(Brass.brassHex, 0.46, 0), location: 0.22),
                .init(color: Brass.mix(Brass.brassHex, 0.28, 0), location: 0.55), .init(color: Brass.mix(Brass.brassHex, 0.40, 0), location: 0.84),
                .init(color: Brass.mix(Brass.brassHex, 0.64, 0), location: 1)], startPoint: .top, endPoint: .bottom))
                .overlay(alignment: .top) { Capsule().fill(Brass.brassLit.opacity(0.55)).frame(height: 1).padding(.horizontal, rh / 2) }
            Capsule().fill(LinearGradient(stops: [
                .init(color: Color(hex: 0x040302), location: 0), .init(color: Brass.mix(Brass.brassHex, 0.10, 0x050403), location: 0.55),
                .init(color: Brass.mix(Brass.brassHex, 0.18, 0x0A0805), location: 1)], startPoint: .top, endPoint: .bottom))
                .overlay(Capsule().stroke(Color.black.opacity(0.9), lineWidth: 2).blur(radius: 2).clipShape(Capsule()).offset(y: 1.5))
                .padding(.vertical, rh * 0.19).padding(.horizontal, rh * 0.26)
        }
        .shadow(color: .black.opacity(0.6), radius: 4, y: 3)
    }

    @ViewBuilder private var plate: some View {
        let missed = verdict == "miss", hit = answer != nil && !missed
        let glow = reduceMotion || answer != nil ? 1.0 : (breathe ? 1.0 : 0.72)
        RoundedRectangle(cornerRadius: 6)
            .fill(LinearGradient(stops: [
                .init(color: Brass.mix(Brass.brassHex, 0.56, Brass.deepHex), location: 0), .init(color: Brass.mix(Brass.brassHex, 0.36, Brass.deepHex), location: 0.16),
                .init(color: Brass.mix(Brass.brassHex, 0.27, Brass.deepHex), location: 0.56), .init(color: Brass.mix(Brass.brassHex, 0.42, Brass.deepHex), location: 1)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 6).fill(RadialGradient(colors: [Brass.brassLit.opacity(0.22), .clear], center: .center, startRadius: 0, endRadius: ph)))
            .overlay(alignment: .bottom) { LinearGradient(colors: [.clear, Brass.tri.opacity(0.5)], startPoint: .top, endPoint: .bottom).frame(height: ph * 0.3).clipShape(RoundedRectangle(cornerRadius: 6)) }
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Brass.brassLit, lineWidth: 1))
            // the glow breathes; only the glow is animated, so the plate's size and place never are (the first Mac run's
            // plate drifted when the whole plate carried the repeating animation)
            .animation(reduceMotion || answer != nil ? nil : .easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { plate in
                plate
                    .shadow(color: missed ? .clear : Brass.brassLit.opacity((hit ? 0.6 : 0.42) * glow), radius: hit ? 23 : 17)
                    .shadow(color: missed ? .clear : Brass.brassLit.opacity((hit ? 0.75 : 0.6) * glow), radius: hit ? 5 : 3.5)
            }
            .saturation(missed ? 0.45 : 1).brightness(missed ? -0.18 : 0)
            .allowsHitTesting(false)
    }

    private var needle: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 3).fill(LinearGradient(colors: [Brass.mix(Brass.brassHex, 0.45, 0), Brass.mix(Brass.litHex, 0.75, 0xFFFFFF), Brass.mix(Brass.brassHex, 0.5, 0)],
                                                                   startPoint: .leading, endPoint: .trailing))
                .frame(width: 6, height: kh + 26)
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.black.opacity(0.55), lineWidth: 1))
            Circle().fill(RadialGradient(stops: [.init(color: Brass.mix(Brass.litHex, 0.5, 0xFFFFFF), location: 0), .init(color: Brass.brassLit, location: 0.3),
                                                 .init(color: Brass.brass, location: 0.62), .init(color: Brass.mix(Brass.brassHex, 0.4, 0), location: 1)],
                                         center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 14))
                .frame(width: 20, height: 20).overlay(Circle().strokeBorder(Color.black.opacity(0.6), lineWidth: 1)).offset(y: -9)
            BrassTriangle().fill(Brass.mix(Brass.litHex, 0.8, 0xFFFFFF)).frame(width: 12, height: 13).offset(y: kh + 26)
        }
        .frame(width: 6, alignment: .top)
        .shadow(color: Brass.brassLit.opacity(0.55), radius: 7)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func knob(_ which: String, _ v: Double, _ label: String) -> some View {
        BrassKnob(w: kw, h: kh, dim: !enabled)
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityValue(Brass.withUnit(v, q))
            .accessibilityAdjustableAction { dir in
                guard enabled else { return }
                let s = q.step > 0 ? q.step : 1
                set(which, v + (dir == .increment ? s : -s))
            }
            .accessibilityIdentifier(which == "lo" ? "ce-low" : "ce-high")
            .allowsHitTesting(false)
    }

    private func value(_ x: CGFloat, _ W: CGFloat) -> Double { q.floor + Double(min(1, max(0, (x - margin) / W))) * span }

    private func set(_ which: String, _ v: Double) {
        let s = q.snap(v)
        if which == "lo" { lo = min(s, hi) } else { hi = max(s, lo) }
    }

    private func drag(_ d: DragGesture.Value, _ W: CGFloat) {
        guard enabled else { return }
        let x = value(d.location.x, W)
        if grab == nil {
            let at = d.startLocation.x, xl = margin + frac(lo) * W, xh = margin + frac(hi) * W
            let onLo = abs(at - xl) <= kw / 2 + 2, onHi = abs(at - xh) <= kw / 2 + 2
            if lo == hi { grab = .free(pivot: lo) }
            else if onLo && onHi { grab = at < (xl + xh) / 2 ? .lo : .hi }   // nearly touching: each takes its own side
            else if onLo { grab = .lo }
            else if onHi { grab = .hi }
            else if at > xl && at < xh && d.startLocation.y > res && d.startLocation.y < res + kh { grab = .both(start: value(at, W), lo: lo, hi: hi) }
            else {
                let near = abs(x - lo) <= abs(x - hi) ? "lo" : "hi"
                grab = near == "lo" ? .lo : .hi
                Haptics.select()
            }
        }
        guard let g = grab else { return }
        switch g {
        case .lo: set("lo", x)
        case .hi: set("hi", x)
        case .free(let p):
            if q.snap(x) != p { grab = x < p ? .lo : .hi; set(x < p ? "lo" : "hi", x) }
        case .both(let start, let l0, let h0):
            let width = h0 - l0
            var nl = q.snap(l0 + (x - start))
            nl = min(max(q.floor, nl), q.ceiling - width)
            lo = q.snap(nl); hi = q.snap(nl + width)
        }
    }
}

struct BrassTriangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(); p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY)); p.closeSubpath(); return p
    }
}

/// The ruler: brass ticks, serif numbers on the majors (never crowding the ends, which are always numbered).
struct BrassRuler: View {
    let q: CloseEnough.Question
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, H = size.height
            let span = max(1e-9, q.ceiling - q.floor)
            let fs = (H * 0.333).rounded(), tMaj = (H * 0.278).rounded(), tMin = (H * 0.13).rounded(), ty = (H * 0.778).rounded(), clear: CGFloat = 44
            let want = Double(max(3, min(10, Int(w / 90))))
            var major = Brass.niceStep(span / want)
            var guardN = 0
            while span / major > want + 0.001 && guardN < 50 { major = Brass.niceStep(major * 1.01); guardN += 1 }
            let mm = major / pow(10, (log10(major) + 1e-9).rounded(.down))
            let minor = major / (mm.rounded() == 2 ? 4 : 5)
            let minorC = Brass.mix(Brass.brassHex, 0.62, 0x0B0A08), majC = Brass.brass
            let textC = Brass.mix(Brass.litHex, 0.62, 0xF5ECD6)
            var base = Path(); base.move(to: CGPoint(x: 0, y: 0.5)); base.addLine(to: CGPoint(x: w, y: 0.5))
            ctx.stroke(base, with: .color(majC.opacity(0.55)), lineWidth: 1)
            var labels: [(v: Double, x: CGFloat)] = []
            let first = (q.floor / minor - 1e-9).rounded(.up) * minor
            var n = 0
            while n < 400 {
                let v = first + Double(n) * minor
                if v > q.ceiling + minor * 1e-6 { break }
                let x = CGFloat((v - q.floor) / span) * w
                let isMaj = abs(v / major - (v / major).rounded()) < 1e-6
                var p = Path(); p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: isMaj ? tMaj : tMin))
                ctx.stroke(p, with: .color(isMaj ? majC : minorC), lineWidth: isMaj ? 2 : 1)
                let atEnd = v <= q.floor + 1e-9 || v >= q.ceiling - 1e-9
                if isMaj && (atEnd || (x > clear && w - x > clear)) { labels.append((v, x)) }
                n += 1
            }
            if abs(q.ceiling / major - (q.ceiling / major).rounded()) > 1e-6 {
                var p = Path(); p.move(to: CGPoint(x: w, y: 0)); p.addLine(to: CGPoint(x: w, y: tMaj))
                ctx.stroke(p, with: .color(majC), lineWidth: 2)
                labels.append((q.ceiling, w))
            }
            for l in labels {
                let ax: CGFloat = l.v <= q.floor + 1e-9 ? 0 : l.v >= q.ceiling - 1e-9 ? 1 : 0.5
                let t = Text(Brass.short(l.v, q)).font(Brass.serifFixed(fs, .medium)).foregroundColor(textC)
                ctx.draw(t, at: CGPoint(x: l.x, y: ty), anchor: UnitPoint(x: ax, y: 0.8))
            }
        }
        .accessibilityHidden(true)
    }
}

/// One line: the points this range is worth (and what it falls to as it widens), a brass divider, the clock.
struct BrassDials: View {
    let points: Int?
    let endsAt: Double?
    let note: (Int) -> String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let big = Brass.scaled(44, .largeTitle)
        HStack(alignment: .center, spacing: 14) {
            HStack(alignment: .center, spacing: 8) {
                Text(points.map { "\($0)" } ?? "—").font(Brass.serifFixed(big, .semibold)).monospacedDigit()
                    .foregroundStyle(Brass.goldText)
                    .contentTransition(reduceMotion ? .identity : .numericText(value: Double(points ?? 0)))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: points)
                Text("pts").font(Brass.serifFixed(big * 0.4, .semibold)).foregroundStyle(Brass.goldText).padding(.top, big * 0.12)
                BrassTriangle().fill(Brass.tri).frame(width: big * 0.2, height: big * 0.13).padding(.top, big * 0.14)
                    .shadow(color: Brass.tri.opacity(0.6), radius: 4)
                VStack(alignment: .leading, spacing: 0) {
                    Text(ghost(1)).opacity(0.55)
                    Text(ghost(2)).opacity(0.34)
                }
                .font(Brass.serifFixed(max(13.6, big * 0.19), .semibold)).monospacedDigit().foregroundStyle(Brass.ghost)
                .lineLimit(1).fixedSize()
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .shadow(color: .black.opacity(0.6), radius: 0, y: 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(points.map { "Worth \($0) \($0 == 1 ? "point" : "points") if it holds the answer, and fewer as it widens." } ?? "Worth: set a range first.")
            .accessibilityIdentifier("ce-worth")
            if let endsAt {
                Rectangle().fill(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: Brass.brass.opacity(0.6), location: 0.16),
                                                        .init(color: Brass.brass.opacity(0.6), location: 0.84), .init(color: .clear, location: 1)],
                                                startPoint: .top, endPoint: .bottom))
                    .frame(width: 1, height: big * 0.95)
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let left = max(0, Int((endsAt / 1000 - ctx.date.timeIntervalSince1970).rounded(.up)))
                    VStack(spacing: 2) {
                        Text(String(format: "%02d:%02d", left / 60, left % 60)).font(Brass.serifFixed(big, .semibold)).monospacedDigit()
                            .foregroundStyle(left <= 10 ? AnyShapeStyle(Brass.low) : AnyShapeStyle(Brass.goldText))
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Text(note(left)).font(Brass.sans(13, .regular, .caption)).foregroundStyle(Brass.ink3).lineLimit(1)
                    }
                    .fixedSize()
                    .shadow(color: .black.opacity(0.6), radius: 0, y: 2)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(left) seconds left. \(note(left))")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, 10).padding(.bottom, 6)
        .overlay(alignment: .top) { Rectangle().fill(Brass.brass.opacity(0.4)).frame(height: 1) }
    }
    private func ghost(_ i: Int) -> String { guard let p = points, p >= i else { return " " }; return "\(p - i) pts" }
}

/// A row in the standings (`.brow`): face, name and what they did, the score in serif brass. Yours is lit.
struct BrassRow: View {
    let p: ScorePlayer
    let me: String
    let owner: String?
    var note: String = ""
    var tick = false
    var win = false
    var body: some View {
        HStack(spacing: 12) {
            FaceView(face: p.face, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                (Text(p.id == me ? "You" : RoomPlayer.stripBot(p.name)).font(Brass.sans(15, .semibold))
                 + Text(p.bot != nil ? " (bot)" : p.left ? " (left)" : "").font(Brass.sans(13, .regular, .footnote)).foregroundColor(Brass.ink3)
                 + Text(owner == p.id ? " · runs the room" : "").font(Brass.sans(13, .regular, .footnote)).foregroundColor(Brass.ink3))
                    .foregroundStyle(Brass.ink).lineLimit(1)
                if !note.isEmpty { Text(note).font(Brass.sans(13, .regular, .footnote)).foregroundStyle(Brass.ink2).lineLimit(2) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if tick { Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Brass.hit).accessibilityLabel("locked in") }
            if win { Text("🎯").accessibilityLabel("won") }
            Text("\(p.score)").font(Brass.serif(21, .semibold, .title3)).monospacedDigit().foregroundStyle(Brass.brassLit)
                .contentTransition(.numericText(value: Double(p.score)))
        }
        .padding(.horizontal, 14).padding(.vertical, 9).frame(minHeight: 50)
        .background(Brass.panel, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(win || p.id == me ? Brass.brass : Brass.panelLine, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// The standings as one line of chips (the Library's teams): face and points, yours lit.
struct BrassChips: View {
    let players: [ScorePlayer]
    let me: String
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(players) { p in
                    HStack(spacing: 5) {
                        FaceView(face: p.face, size: 22)
                        Text("\(p.score)").font(Brass.serif(17, .semibold, .headline)).monospacedDigit().foregroundStyle(Brass.ink)
                            .contentTransition(.numericText(value: Double(p.score)))
                        if p.lockedIn { Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(Brass.hit) }
                    }
                    .padding(.leading, 5).padding(.trailing, 10).frame(minHeight: 32)
                    .background(Brass.panel, in: Capsule())
                    .overlay(Capsule().strokeBorder(p.id == me ? Brass.brass : Brass.panelLine, lineWidth: 1))
                    .shadow(color: p.id == me ? Color(red: 240 / 255, green: 190 / 255, blue: 100 / 255).opacity(0.25) : .clear, radius: 7)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(p.id == me ? "You" : RoomPlayer.stripBot(p.name)): \(p.score) points\(p.lockedIn ? ", locked in" : "")")
                }
            }
            .padding(.horizontal, 2).padding(.vertical, 6)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityIdentifier("ce-chips")
    }
}

/// The reaction chips, in the masthead button's brass.
struct BrassReactions: View {
    @ObservedObject var room: RoomModel
    var body: some View {
        WebFlow(spacing: 8) {
            ForEach(Reaction.allCases) { r in
                Button(r.words) { room.react(r); Haptics.select() }
                    .buttonStyle(BrassSmallButton())
                    .accessibilityLabel("Send \(r.words)")
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Chips that wrap onto more lines, centered, like the website's flex rows.
struct WebFlow: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal.width ?? .infinity, subviews)
        let h = rows.map(\.h).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? rows.map(\.w).max() ?? 0, height: h)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(bounds.width, subviews) {
            var x = bounds.minX + (bounds.width - row.w) / 2
            for i in row.items {
                let s = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y + (row.h - s.height) / 2), proposal: ProposedViewSize(s))
                x += s.width + spacing
            }
            y += row.h + spacing
        }
    }
    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> [(items: [Int], w: CGFloat, h: CGFloat)] {
        var rows: [(items: [Int], w: CGFloat, h: CGFloat)] = []
        var cur: (items: [Int], w: CGFloat, h: CGFloat) = ([], 0, 0)
        for (i, v) in subviews.enumerated() {
            let s = v.sizeThatFits(.unspecified)
            let add = cur.items.isEmpty ? s.width : cur.w + spacing + s.width
            if add > width && !cur.items.isEmpty { rows.append(cur); cur = ([i], s.width, s.height) }
            else { cur = (cur.items + [i], add, max(cur.h, s.height)) }
        }
        if !cur.items.isEmpty { rows.append(cur) }
        return rows
    }
}

/// The masthead: "Close Enough" in serif, the room's code as the file's chip (it opens the room menu), and Leave.
struct BrassMast: View {
    @ObservedObject var room: RoomModel
    var onLeave: () -> Void
    @Environment(\.gameDialogs) private var dialogs
    var body: some View {
        HStack(spacing: 10) {
            (Text("Close ").foregroundColor(Brass.ink) + Text("Enough").foregroundColor(Brass.brass).font(Brass.serif(23, .semibold, .title3)))
                .font(Brass.serif(23, .regular, .title3)).lineLimit(1).minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            Button(action: showMenu) {
                Text(room.offline ? "PRACTICE" : room.code).font(Brass.mono(11, .regular, .caption)).tracking(1.3).foregroundStyle(Brass.brass)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Brass.brassDim, in: RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Brass.brass.opacity(0.3), lineWidth: 1))
                    .frame(minHeight: 44).contentShape(Rectangle())
            }
            .accessibilityLabel(room.offline ? "Practice room menu" : "Room \(room.code) menu")
            .accessibilityIdentifier("room-menu")
            Spacer(minLength: 4)
            Button("Leave", action: onLeave).buttonStyle(BrassSmallButton()).accessibilityIdentifier("leave")
        }
    }
    private func showMenu() {
        guard let dialogs else { return }
        let r = room
        dialogs.show(.roomMenu(room: r, reactions: false, onEnd: { dialogs.show(.endRoom(end: { r.send(Out.close) })) }, onLeave: onLeave))
    }
}

/// The screen inside its brass case: the case stays put, the content scrolls inside it.
struct BrassCased<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        ZStack {
            Brass.background
            BrassCase().padding(.horizontal, 6).padding(.vertical, 4)
            ScrollView { content().padding(.horizontal, 22).padding(.top, 14).padding(.bottom, 24).frame(maxWidth: 520).frame(maxWidth: .infinity) }
                .scrollDismissesKeyboard(.interactively)
                .clipShape(ChamferShape(cut: 14, inset: 6))
                .padding(.horizontal, 6).padding(.vertical, 4)
        }
        .overlay(alignment: .topLeading) {
            // for UI tests: which serif the screens are drawn in
            Text(Brass.serifInUse).font(.system(size: 2)).opacity(0.02).accessibilityIdentifier("ce-serif").allowsHitTesting(false)
        }
    }
}

/// The game screen: masthead, the standings' chips, the question, the instrument, then the readout and Lock (or the
/// result), then the standings with each range and the reactions.
struct CloseEnoughBrassGame: View {
    @ObservedObject var room: RoomModel
    let view: CloseEnough.View
    let q: CloseEnough.Question
    var onLeave: () -> Void
    @Binding var lo: Double
    @Binding var hi: Double
    let landed: Bool
    /// read so a text-size change redraws the screen (Brass's fonts read the size themselves)
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var typeOpen = false
    @State private var loText = ""
    @State private var hiText = ""
    @FocusState private var typing: Bool

    private var me: String { view.common.meId }
    private var asking: Bool { q.stage == "ask" }
    private var mine: CloseEnough.Result? { q.results[me] }

    private static let verdicts: [String: (String, String)] = [
        "tight": ("Tight, and right.", "You committed to a small window and the answer was in it."),
        "hit": ("Inside, comfortably.", "Wide enough to be safe, which is why it is worth less."),
        "miss": ("Outside the range.", "No points. A range that misses scores nothing however narrow it was."),
        "none": ("No range locked in.", "No points this time."),
    ]

    var body: some View {
        GeometryReader { g in
            // the handle's height from the screen's, as house.css's phone rule: clamp(58px, 12.3vh, 104px)
            let kh = min(104, max(58, g.size.height * 0.123))
            BrassCased {
                VStack(spacing: 0) {
                    BrassMast(room: room, onLeave: onLeave)
                    BrassChips(players: view.players.filter { !$0.left || $0.score > 0 }, me: me)
                    Rectangle().fill(Brass.mastLine).frame(height: 1).padding(.top, 4)
                    question.padding(.top, 18).padding(.bottom, 16)
                    instrument(kh)
                    if asking { askLow } else { revealBox.padding(.top, 10) }
                    standings.padding(.top, 22)
                    BrassReactions(room: room).padding(.top, 14)
                }
                .animation(reduceMotion ? nil : .spring(duration: 0.4), value: q.n)
            }
        }
        .onAppear { syncText() }
        .onChange(of: lo) { _, _ in if !typing { syncText() } }
        .onChange(of: hi) { _, _ in if !typing { syncText() } }
        .onChange(of: q.n) { _, _ in syncText(); typeOpen = false }
    }

    private var question: some View {
        VStack(spacing: 8) {
            Text("Question \(q.n) of \(q.of)".uppercased()).font(Brass.mono(11, .regular, .caption)).tracking(1.5).foregroundStyle(Brass.brass)
                .accessibilityIdentifier("ce-number")
            Text(q.q).font(Brass.serif(22, .medium, .title2)).foregroundStyle(Brass.qInk).multilineTextAlignment(.center).lineSpacing(1)
                .shadow(color: .black.opacity(0.55), radius: 0, y: 2)
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("ce-question")
            if !q.note.isEmpty {
                Text(q.note).font(Brass.sans(16, .regular, .callout)).foregroundStyle(Brass.ink2).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .id(q.n)
        .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.move(edge: .trailing).combined(with: .opacity))
    }

    /// What the nameplate and the handles show: your range as you set it, the one you locked in, or at the answer the one
    /// the room scored.
    private var shown: (lo: Double, hi: Double)? {
        if !asking { if let a = mine?.lo, let b = mine?.hi { return (a, b) }; return nil }
        if view.lockedIn { return (view.answerLo ?? lo, view.answerHi ?? hi) }
        return view.common.seated ? (lo, hi) : nil
    }

    @ViewBuilder private func instrument(_ kh: CGFloat) -> some View {
        let s = shown
        let answerLine = q.answer.map { "Answer: " + Brass.withUnit($0, q) } ?? ""
        VStack(spacing: 14) {
            BrassNameplate(range: s.map { Brass.rangeText($0.lo, $0.hi, q) } ?? (asking ? "Watching this one" : "No range locked in"),
                           line: asking ? "Your range" : answerLine, empty: s == nil, revealed: !asking,
                           lineId: asking ? "ce-plate-line" : "ce-answer")
            if s != nil && asking && !view.lockedIn && view.common.seated {
                BrassInstrument(q: q, lo: $lo, hi: $hi, enabled: true, kh: kh)
            } else {
                // locked in, at the answer, or watching: the handles show the range and don't move
                BrassInstrument(q: q, lo: .constant(s?.lo ?? q.floor), hi: .constant(s?.hi ?? q.floor), enabled: false,
                                answer: asking ? nil : q.answer, verdict: asking ? nil : (mine?.verdict ?? "none"), landed: landed, kh: kh)
                    .opacity(s == nil && asking ? 0.6 : 1)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ce-scale")
    }

    private var worth: Int? {
        guard let s = shown else { return nil }
        return q.worth(lo: s.lo, hi: s.hi, maxPoints: view.maxPoints)
    }

    /// The readout and Lock (or what you locked in), and the typed numbers behind their link.
    @ViewBuilder private var askLow: some View {
        VStack(spacing: 12) {
            BrassDials(points: worth, endsAt: q.endsAt) { left in
                !view.common.seated ? "Watching" : view.lockedIn ? "Locked in" : left <= 0 ? "Time." : "Time left"
            }
            .padding(.top, 8)
            if view.lockedIn || !view.common.seated {
                lockedBox
            } else {
                if typeOpen { typed }
                Button("Lock in this range") {
                    typing = false
                    room.move("range", ["lo": .number(lo), "hi": .number(hi)]); Haptics.play()
                }
                .buttonStyle(BrassLockButton()).disabled(hi < lo)
                .accessibilityIdentifier("lock-in")
                Button { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { typeOpen.toggle() } } label: {
                    HStack(spacing: 6) {
                        Text(typeOpen ? "Hide exact numbers" : "Type exact numbers").underline(color: Brass.brass.opacity(0.55))
                        Image(systemName: typeOpen ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill").font(.system(size: 8))
                    }
                    .font(Brass.sans(15, .regular, .subheadline)).foregroundStyle(Brass.ink2)
                    .frame(minHeight: 44).contentShape(Rectangle())
                }
                .accessibilityIdentifier("ce-type")
            }
        }
    }

    /// "No lower than ... to ... No higher than": the typed numbers move the handles too.
    private var typed: some View {
        HStack(alignment: .bottom, spacing: 10) {
            field("No lower than", text: $loText, value: $lo, id: "ce-low-number") { if hi < $0 { hi = $0 } }
            Text("to").font(Brass.mono(13, .regular)).foregroundStyle(Brass.ink3).padding(.bottom, 14)
            field("No higher than", text: $hiText, value: $hi, id: "ce-high-number") { if lo > $0 { lo = $0 } }
        }
        .padding(14)
        .background(Brass.panel, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Brass.resultLine, lineWidth: 1))
        .transition(.opacity)
    }

    private func field(_ label: String, text: Binding<String>, value: Binding<Double>, id: String, then: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(Brass.mono(10, .regular)).tracking(1.2).foregroundStyle(Brass.ink3).lineLimit(1).minimumScaleFactor(0.7)
            TextField("", text: text)
                .keyboardType(.decimalPad).focused($typing)
                .font(Brass.mono(19, .regular, .body)).foregroundStyle(Brass.ink).multilineTextAlignment(.center)
                .frame(minHeight: 48)
                .background(Brass.m0, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Brass.line, lineWidth: 1))
                .onChange(of: text.wrappedValue) { _, t in
                    guard typing, let v = Double(t.replacingOccurrences(of: ",", with: "")) else { return }
                    value.wrappedValue = min(q.ceiling, max(q.floor, v)); then(value.wrappedValue)
                }
                .accessibilityLabel("\(label), type a number")
                .accessibilityIdentifier(id)
        }
        .frame(maxWidth: .infinity)
    }

    private func syncText() { loText = Brass.fmt(lo, q).replacingOccurrences(of: ",", with: ""); hiText = Brass.fmt(hi, q).replacingOccurrences(of: ",", with: "") }

    /// Locked in: what you locked in and who's still thinking.
    private var lockedBox: some View {
        let waiting = view.players.filter { !$0.left && $0.seated && !$0.lockedIn && $0.id != me && ($0.bot != nil || $0.connected) }.map { RoomPlayer.stripBot($0.name) }
        return VStack(spacing: 4) {
            Text(view.common.seated ? "Locked in" : "A game is on").font(Brass.serif(20, .semibold, .title3)).foregroundStyle(Brass.brassLit)
            Text(!view.common.seated ? "You’ll play in the next one."
                 : waiting.isEmpty ? "The answer’s coming." : "Waiting for \(waiting.joined(separator: ", ")).")
                .font(Brass.sans(15, .regular, .subheadline)).foregroundStyle(Brass.ink2).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity).padding(14)
        .background(Brass.panel, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Brass.resultLine, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("ce-locked")
    }

    /// The result (`.result`): the verdict and its points, your range, why, then Next (the room's owner) and when it goes
    /// on by itself.
    private var revealBox: some View {
        let verdict = mine?.verdict ?? "none", points = mine?.points ?? 0
        let vd = Self.verdicts[verdict] ?? Self.verdicts["none"]!
        let edge: Color = verdict == "tight" ? Brass.tight : verdict == "hit" ? Brass.hit : verdict == "miss" ? Brass.miss : Brass.ink3
        let head: Color = verdict == "miss" ? Brass.missText : verdict == "none" ? Brass.ink : Brass.hitText
        let missing = q.results.values.contains { $0.verdict == "none" }
        return VStack(alignment: .leading, spacing: 10) {
            Text(vd.0 + (points > 0 ? " +\(points)" : "")).font(Brass.serif(22, .semibold, .title2)).foregroundStyle(head)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("ce-verdict")
            Text((mine?.lo != nil && mine?.hi != nil ? "Your range: \(Brass.rangeText(mine!.lo!, mine!.hi!, q)). " : "") + vd.1)
                .font(Brass.sans(15, .regular, .subheadline)).foregroundStyle(Brass.ink2).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Text(missing ? "Not everyone locked in before the clock ran out." : "Everyone locked in.")
                .font(Brass.sans(13, .regular, .footnote)).foregroundStyle(Brass.ink3)
                .accessibilityIdentifier("ce-why-ended")
            if let why = q.why, !why.isEmpty {
                Rectangle().fill(Brass.line).frame(height: 1)
                (Text("Why: ").foregroundColor(Brass.ink).fontWeight(.bold) + Text(why))
                    .font(Brass.sans(15, .regular, .subheadline)).foregroundStyle(Brass.ink2).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if room.isOwner {
                Button(q.n < q.of ? "Next question" : "See the standings") { room.move("next"); Haptics.select() }
                    .buttonStyle(BrassActButton()).padding(.top, 4)
                    .accessibilityIdentifier("ce-next")
            }
            if let e = q.endsAt {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let left = max(0, Int((e / 1000 - ctx.date.timeIntervalSince1970).rounded(.up)))
                    Text(left == 0 ? " " : room.isOwner ? "Or it goes on by itself in \(left)s." : q.n < q.of ? "Next question in \(left)s." : "The standings in \(left)s.")
                        .font(Brass.sans(13, .regular, .footnote).monospacedDigit()).foregroundStyle(Brass.ink3)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("ce-next-in")
                }
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brass.panel, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Brass.resultLine, lineWidth: 1))
        .overlay(alignment: .leading) { UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 10).fill(edge).frame(width: 4) }
        .shadow(color: .black.opacity(0.65), radius: 17, y: -6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ce-result")
    }

    private var standings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Standings".uppercased()).font(Brass.mono(11, .regular, .caption)).tracking(1.5).foregroundStyle(Brass.ink3)
            ForEach(view.players.filter { !$0.left || $0.score > 0 }.sorted { $0.score > $1.score }) { p in
                BrassRow(p: p, me: me, owner: view.common.hostless ? view.common.owner : nil, note: rangeNote(p), tick: asking && p.lockedIn)
            }
        }
        .padding(.top, 16)
        .overlay(alignment: .top) { Rectangle().fill(Brass.line).frame(height: 1) }
        .animation(reduceMotion ? nil : .spring(duration: 0.5), value: view.players.map(\.score))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ce-standings")
    }

    /// At the answer, each player's range and points ("12 — 22 liters · +11", "no range").
    private func rangeNote(_ p: ScorePlayer) -> String {
        guard !asking, let x = q.results[p.id] else { return "" }
        guard let a = x.lo, let b = x.hi else { return "No range" }
        return Brass.rangeText(a, b, q) + (x.points > 0 ? " · +\(x.points)" : " · 0")
    }
}

/// The end of the game (the Library's end screen): the target, who won, the line about misses, each player's points and
/// how often their range held the answer, then Play again and Change seats (the owner) or who starts the next one.
struct CloseEnoughBrassOver: View {
    @ObservedObject var room: RoomModel
    @Environment(\.dynamicTypeSize) private var textSize
    @EnvironmentObject var app: AppModel
    let view: CloseEnough.View
    var onLeave: () -> Void = {}
    var body: some View {
        let me = view.common.meId
        let winners = view.common.winners ?? []
        let names = winners.compactMap { w in view.players.first { $0.id == w } }.map { RoomPlayer.stripBot($0.name) }
        let title = winners.contains(me) ? (winners.count > 1 ? "A shared win!" : "You win!") : names.count > 1 ? "A shared win!" : names.first.map { "\($0) wins!" } ?? "Game over"
        let misses = view.players.reduce(0) { $0 + $1.misses }
        BrassCased {
            VStack(spacing: 14) {
                BrassMast(room: room, onLeave: onLeave)
                Rectangle().fill(Brass.mastLine).frame(height: 1)
                Text("🎯").font(.system(size: 42)).padding(.top, 10).accessibilityHidden(true)
                Text("Game over".uppercased()).font(Brass.mono(11, .regular, .caption)).tracking(1.5).foregroundStyle(Brass.brass)
                Text(title).font(Brass.serif(32, .semibold, .largeTitle)).foregroundStyle(Brass.ink).multilineTextAlignment(.center)
                    .accessibilityIdentifier("game-over")
                Text(misses > 0 ? "\(misses) range\(misses == 1 ? "" : "s") missed entirely. Those are worth revisiting: a miss means someone was confident about something they had wrong, not that they guessed badly."
                     : "Every range held the answer. Now ask who could have gone narrower and chose not to.")
                    .font(Brass.sans(15, .regular, .subheadline)).foregroundStyle(Brass.ink2).multilineTextAlignment(.center).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 8) {
                    ForEach(view.players.filter { !$0.left || $0.score > 0 }.sorted { $0.score > $1.score }) { p in
                        BrassRow(p: p, me: me, owner: view.common.hostless ? view.common.owner : nil,
                                 note: "\(p.hits) inside, \(p.misses) outside", win: winners.contains(p.id))
                    }
                }
                Text(room.isOwner ? "Play again with everyone here, or change seats first."
                     : view.common.hostless ? "If \(room.ownerName ?? "the room’s owner") starts another game, you’ll be in it." : "")
                    .font(Brass.sans(13, .regular, .footnote)).foregroundStyle(Brass.ink3).multilineTextAlignment(.center)
                if room.isOwner {
                    Button("Play again") { room.send(Out.again); room.send(Out.deal); Haptics.play() }.buttonStyle(BrassActButton())
                        .accessibilityIdentifier("play-again")
                    Button("Change seats") { room.send(Out.again) }.buttonStyle(BrassActButton(ghost: true))
                }
                BrassReactions(room: room)
                Button("Back to Library") { room.leave(); app.closeRoom(); app.tab = .library }
                    .buttonStyle(BrassActButton(ghost: true)).padding(.top, 4)
                    .accessibilityIdentifier("back-to-library")
                TipLine()   // #598
            }
        }
        .onAppear { if winners.contains(me) { Haptics.yourTurn() } }
    }
}
