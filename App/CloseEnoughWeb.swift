import SwiftUI
import UIKit
import T2PCore

/// #707 (Tyler, Nov 21: "make Close Enough actually how it looks on the website"; "It looks nothing like the website
/// version"): Close Enough's phone screens drawn the way time2play.live draws them (static/live/closeenough-join.html
/// in the website repo): the same dark gradient, the "name · points" line and the code, the question, the scale with
/// its gold band and the answer's green line, Low and High each with a slider and a number box, what the range is
/// worth, the gold Lock in button, the result card, Standings with each range and its points, the reaction chips and
/// Leave. Native where it has to be: safe areas, haptics, VoiceOver, Dynamic Type up to xxxLarge, and the code opens
/// the room menu (invite, end the room, leave). The 3D board stays behind You → "3D Close Enough board".
enum Web {
    // the website's colors (:root in closeenough-join.html); the website has a dark look only
    static let bg1 = Color(hex: 0x17283A), bg2 = Color(hex: 0x0F1A24)
    static let ink = Color(hex: 0xF2F5F8), muted = Color(hex: 0xA9B7C4)
    static let line = Color(red: 242 / 255, green: 245 / 255, blue: 248 / 255).opacity(0.16)
    static let panel = Color(red: 10 / 255, green: 18 / 255, blue: 26 / 255).opacity(0.72)
    static let accent = Color(hex: 0xFFCF4A), accentInk = Color(hex: 0x1D1600)
    static let good = Color(hex: 0x7FD68B), miss = Color(hex: 0xFF9C86)

    /// The website's type: its sizes and weights in points, grown with the reader's text size like the text style
    /// given, up to xxxLarge (the cap the tables use). (A custom font name falling back to the system font kept the
    /// size but dropped the weight: the first Mac run's question read regular, the website's is 800.)
    static func font(_ size: CGFloat, _ weight: Font.Weight, _ style: Font.TextStyle = .body) -> Font {
        let now = UIApplication.shared.preferredContentSizeCategory
        let capped: UIContentSizeCategory = now > .extraExtraExtraLarge ? .extraExtraExtraLarge : now
        let traits = UITraitCollection(preferredContentSizeCategory: capped == .unspecified ? .large : capped)
        let scaled = UIFontMetrics(forTextStyle: uiStyle(style)).scaledValue(for: size, compatibleWith: traits)
        return .system(size: scaled, weight: weight)
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

    /// The page's background: a soft light high in the middle, darker toward the edges.
    static var background: some View {
        ZStack {
            bg2
            RadialGradient(colors: [bg1, bg2], center: UnitPoint(x: 0.5, y: 0.25), startRadius: 0, endRadius: 620)
        }
        .ignoresSafeArea()
    }

    /// A number as the website shows it in the standings: no unit, the step's decimals.
    static func bare(_ v: Double, _ q: CloseEnough.Question) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.locale = Locale(identifier: "en_US")
        f.maximumFractionDigits = q.step >= 1 ? 0 : min(6, Int((-log10(q.step) - 1e-9).rounded(.up)))
        return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }
}

/// `.btn.go`: the gold button.
struct WebGoButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Web.font(18, .heavy, .headline)).foregroundStyle(Web.accentInk)
            .frame(maxWidth: .infinity, minHeight: 52).padding(.horizontal, 14)
            .background(Web.accent, in: RoundedRectangle(cornerRadius: 16))
            .opacity(enabled ? (configuration.isPressed ? 0.85 : 1) : 0.35)
    }
}

/// `.btn.ghost`: the outlined button (Leave, Change seats).
struct WebGhostButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Web.font(15, .heavy, .subheadline)).foregroundStyle(Web.ink)
            .frame(maxWidth: .infinity, minHeight: 44).padding(.horizontal, 14)
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Web.line, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 16))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// The question's scale: the track, your range's band (coral when it missed) and, at the answer, its green line.
struct WebScale: View {
    let q: CloseEnough.Question
    let lo: Double?; let hi: Double?
    var missed = false
    var answer: Double? = nil
    var landed = true
    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { g in
                let w = g.size.width
                let span = max(1, q.ceiling - q.floor)
                let x = { (v: Double) in CGFloat(min(1, max(0, (v - q.floor) / span))) * w }
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 3).fill(Web.line).frame(height: 6).offset(y: 14)
                    if let lo, let hi, hi >= lo {
                        RoundedRectangle(cornerRadius: 9).fill(missed ? Web.miss : Web.accent)
                            .frame(width: max(4, max(w * 0.01, x(hi) - x(lo))), height: 18).offset(x: x(lo), y: 8)
                    }
                    if let answer {
                        RoundedRectangle(cornerRadius: 2).fill(Web.good).frame(width: 3, height: 34)
                            .offset(x: x(answer) - 1.5, y: landed ? 0 : -20).opacity(landed ? 1 : 0)
                    }
                }
            }
            .frame(height: 34)
            HStack { Text(q.format(q.floor)); Spacer(); Text(q.format(q.ceiling)) }
                .font(Web.font(12, .semibold, .caption)).foregroundStyle(Web.muted)
        }
        .padding(.horizontal, 4).padding(.top, 6).padding(.bottom, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Scale from \(q.format(q.floor)) to \(q.format(q.ceiling))"
                            + (lo != nil && hi != nil ? "; your range \(q.formatRange(lo!, hi!))" : "")
                            + (answer.map { "; the answer \(q.format($0))" } ?? ""))
        .accessibilityIdentifier("ce-scale")
    }
}

/// The website's range slider: a gold fill to the gold knob. VoiceOver and the UI tests get a real slider.
struct WebSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let label: String
    let spoken: String
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, knob: CGFloat = 22
            let span = max(1e-9, range.upperBound - range.lowerBound)
            let f = CGFloat(min(1, max(0, (value - range.lowerBound) / span)))
            ZStack(alignment: .leading) {
                Capsule().fill(Color(hex: 0x3A3F45)).frame(height: 14)
                    .overlay(Capsule().strokeBorder(Color.black.opacity(0.35), lineWidth: 1))
                Capsule().fill(Web.accent).frame(width: max(knob, knob / 2 + f * (w - knob)), height: 14)
                Circle().fill(Web.accent).frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                    .offset(x: f * (w - knob))
            }
            .frame(height: 44)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { d in
                let t = Double(min(1, max(0, (d.location.x - knob / 2) / max(1, w - knob))))
                value = range.lowerBound + t * span
            })
        }
        .frame(height: 44)
        .accessibilityRepresentation {
            Slider(value: $value, in: range, step: step) { Text(label) }
                .accessibilityValue(spoken)
        }
    }
}

/// A Standings row (`.list .p`): face, name with (bot) and runs the room, the range and its points at the answer, a
/// tick while locked in, and the score. Yours has the gold ring; a winner's is green.
struct WebPlayerRow: View {
    let p: ScorePlayer
    let me: String
    let owner: String?
    var note: String = ""
    var tick = false
    var score: String
    var win = false
    var body: some View {
        HStack(spacing: 10) {
            FaceView(face: p.face, size: 30)
            (Text(RoomPlayer.stripBot(p.name)).font(Web.font(15, .semibold))
             + Text(p.bot != nil ? " (bot)" : p.left ? " (left)" : "").font(Web.font(13, .semibold, .footnote))
             + Text(owner == p.id ? " · runs the room" : "").font(Web.font(13, .semibold, .footnote))
             + Text(note.isEmpty ? "" : " " + note).font(Web.font(13, .semibold, .footnote)).foregroundColor(Web.muted))
                .foregroundStyle(Web.ink).lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if tick { Text("✓").font(Web.font(15, .heavy)).foregroundStyle(Web.good).accessibilityLabel("locked in") }
            Text(score).font(Web.font(15, .bold).monospacedDigit()).foregroundStyle(Web.ink)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 10).padding(.vertical, 8).frame(minHeight: 46)
        .background(Web.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(win ? Web.good : p.id == me ? Web.accent : Web.line, lineWidth: win || p.id == me ? 2 : 1))
        .accessibilityElement(children: .combine)
    }
}

/// The reaction chips (`.react`).
struct WebReactions: View {
    @ObservedObject var room: RoomModel
    var body: some View {
        WebFlow(spacing: 8) {
            ForEach(Reaction.allCases) { r in
                Button(r.words) { room.react(r); Haptics.select() }
                    .font(Web.font(14, .bold, .subheadline)).foregroundStyle(Web.ink)
                    .padding(.horizontal, 14).frame(minHeight: 40)
                    .overlay(Capsule().strokeBorder(Web.line, lineWidth: 1)).contentShape(Capsule())
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

/// The website's game screen: the question, your range, the answer and the standings.
struct CloseEnoughWebGame: View {
    @ObservedObject var room: RoomModel
    let view: CloseEnough.View
    let q: CloseEnough.Question
    var onLeave: () -> Void
    @Binding var lo: Double
    @Binding var hi: Double
    let landed: Bool
    @Environment(\.gameDialogs) private var dialogs
    /// read so a text-size change redraws the screen (Web.font reads the size itself)
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                top
                HStack {
                    Text("Question \(q.n) of \(q.of)".uppercased()).font(Web.font(13, .bold, .footnote)).tracking(0.8)
                        .foregroundStyle(Web.muted).accessibilityIdentifier("ce-number")
                    Spacer()
                    if asking, let e = q.endsAt { WebClock(endsAt: e) }
                }
                .frame(minHeight: 30)
                Group {
                    Text(q.q).font(Web.font(22, .heavy, .title2)).foregroundStyle(Web.ink).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("ce-question")
                    if !q.note.isEmpty { Text(q.note).font(Web.font(14, .semibold, .subheadline)).foregroundStyle(Web.muted) }
                }
                .id(q.n)
                .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.move(edge: .trailing).combined(with: .opacity))
                scale
                if asking {
                    if view.lockedIn || !view.common.seated { lockedBox } else { askBox }
                } else {
                    revealBox
                }
                Text("Standings".uppercased()).font(Web.font(12, .bold, .caption)).tracking(1.4).foregroundStyle(Web.muted)
                    .padding(.top, 6)
                VStack(spacing: 6) {
                    ForEach(view.players.sorted { $0.score > $1.score }) { p in
                        WebPlayerRow(p: p, me: me, owner: view.common.hostless ? view.common.owner : nil, note: rangeNote(p),
                                     tick: asking && p.lockedIn, score: "\(p.score)")
                    }
                }
                .animation(reduceMotion ? nil : .spring(duration: 0.5), value: view.players.map(\.score))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("ce-standings")
                WebReactions(room: room)
                Button("Leave", action: onLeave).buttonStyle(WebGhostButton()).padding(.top, 4)
                    .accessibilityIdentifier("leave")
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 18)
            .frame(maxWidth: 480).frame(maxWidth: .infinity)
            .animation(reduceMotion ? nil : .spring(duration: 0.4), value: q.n)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { syncText() }
        .onChange(of: lo) { _, _ in if !typing { syncText() } }
        .onChange(of: hi) { _, _ in if !typing { syncText() } }
        .onChange(of: q.n) { _, _ in syncText() }
    }

    /// `.top`: your name and points, and the room's code (which opens the room menu).
    private var top: some View {
        HStack(spacing: 10) {
            Text("\(view.common.meName) · \(view.me?.score ?? 0) points").font(Web.font(16, .bold, .headline)).foregroundStyle(Web.ink)
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("ce-who")
            Button(action: showMenu) {
                Text(room.offline ? "PRACTICE" : room.code).font(Web.font(13, .heavy, .footnote)).tracking(1.8).foregroundStyle(Web.ink)
                    .padding(.horizontal, 10).frame(minHeight: 30)
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Web.line, lineWidth: 1))
                    .frame(minHeight: 44).contentShape(Rectangle())
            }
            .accessibilityLabel(room.offline ? "Practice room menu" : "Room \(room.code) menu")
            .accessibilityIdentifier("room-menu")
        }
    }

    private func showMenu() {
        guard let dialogs else { return }
        let r = room
        dialogs.show(.roomMenu(room: r, reactions: false, onEnd: { dialogs.show(.endRoom(end: { r.send(Out.close) })) }, onLeave: onLeave))
    }

    @ViewBuilder private var scale: some View {
        if asking {
            if view.lockedIn { WebScale(q: q, lo: view.answerLo, hi: view.answerHi) }
            else if view.common.seated { WebScale(q: q, lo: lo, hi: hi) }
            else { WebScale(q: q, lo: nil, hi: nil) }
        } else {
            WebScale(q: q, lo: mine?.lo, hi: mine?.hi, missed: mine?.verdict == "miss", answer: q.answer, landed: landed)
        }
    }

    /// `#askBox`: Low and High, what it's worth, and Lock in.
    private var askBox: some View {
        VStack(spacing: 10) {
            pick("Low", value: $lo, text: $loText) { if hi < $0 { hi = $0 } }
            pick("High", value: $hi, text: $hiText) { if lo > $0 { lo = $0 } }
            (Text("From \(q.format(lo)) to \(q.format(hi)) · worth ")
             + Text("\(q.worth(lo: lo, hi: hi, maxPoints: view.maxPoints))").foregroundColor(Web.accent)
             + Text(" points if it holds the answer"))
                .font(Web.font(15, .bold, .subheadline)).foregroundStyle(Web.ink).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("ce-worth")
            Button("Lock in this range") {
                typing = false
                room.move("range", ["lo": .number(lo), "hi": .number(hi)]); Haptics.play()
            }
            .buttonStyle(WebGoButton()).disabled(hi < lo)
            .accessibilityIdentifier("lock-in")
        }
    }

    /// `.pick`: the label, the slider and the number box.
    private func pick(_ label: String, value: Binding<Double>, text: Binding<String>, then: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 10) {
            Text(label).font(Web.font(14, .bold, .subheadline)).foregroundStyle(Web.muted).frame(width: 52, alignment: .leading)
                .accessibilityHidden(true)
            WebSlider(value: Binding(get: { value.wrappedValue }, set: { value.wrappedValue = q.snap($0); then(value.wrappedValue) }),
                      range: q.floor...max(q.ceiling, q.floor + 1), step: q.step > 0 ? q.step : 1, label: label, spoken: q.format(value.wrappedValue))
                .accessibilityIdentifier("ce-\(label.lowercased())")
            TextField("", text: text)
                .keyboardType(.decimalPad).focused($typing)
                .font(Web.font(17, .bold, .body).monospacedDigit()).foregroundStyle(Web.ink)
                .padding(.horizontal, 10).frame(width: 108).frame(minHeight: 44)
                .background(Web.panel, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Web.line, lineWidth: 2))
                .onChange(of: text.wrappedValue) { _, t in
                    guard typing, let v = Double(t.replacingOccurrences(of: ",", with: "")) else { return }
                    value.wrappedValue = min(q.ceiling, max(q.floor, v)); then(value.wrappedValue)
                }
                .accessibilityLabel("\(label), type a number")
                .accessibilityIdentifier("ce-\(label.lowercased())-number")
        }
    }

    private func syncText() { loText = Web.bare(lo, q); hiText = Web.bare(hi, q) }

    /// `.locked`: what you locked in and who's still thinking.
    private var lockedBox: some View {
        let waiting = view.players.filter { !$0.left && !$0.lockedIn && $0.id != me && ($0.bot != nil || $0.connected) }.map { RoomPlayer.stripBot($0.name) }
        let line = !view.common.seated ? "A game is on. You’ll play in the next one."
            : "Locked in: \(q.format(view.answerLo ?? 0)) to \(q.format(view.answerHi ?? 0)). " + (waiting.isEmpty ? "" : "Waiting for \(waiting.joined(separator: ", ")).")
        return Text(line).font(Web.font(16, .bold, .body)).foregroundStyle(Web.ink).multilineTextAlignment(.center)
            .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity).padding(14)
            .background(Web.panel, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Web.line, lineWidth: 1))
            .accessibilityIdentifier("ce-locked")
    }

    /// `#revealBox`: the answer, the verdict and why, then Next (the room's owner) and when it goes on by itself.
    private var revealBox: some View {
        let verdict = mine?.verdict ?? "none", points = mine?.points ?? 0
        let rlo = mine?.lo, rhi = mine?.hi
        let vd = Self.verdicts[verdict] ?? Self.verdicts["none"]!
        let border: Color = verdict == "tight" ? Web.good : verdict == "hit" ? Web.accent : Web.miss
        return VStack(spacing: 12) {
            VStack(spacing: 6) {
                Text(q.answer.map { q.format($0) } ?? "").font(Web.font(28, .heavy, .title)).foregroundStyle(Web.ink)
                    .frame(maxWidth: .infinity).accessibilityIdentifier("ce-answer")
                Text(vd.0 + (points > 0 ? " +\(points)" : "")).font(Web.font(18, .heavy, .headline)).foregroundStyle(Web.ink)
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                    .accessibilityIdentifier("ce-verdict")
                Text((rlo != nil && rhi != nil ? "Your range: \(q.format(rlo!)) to \(q.format(rhi!)). " : "") + vd.1)
                    .font(Web.font(14, .semibold, .subheadline)).foregroundStyle(Web.muted).lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                if let why = q.why, !why.isEmpty {
                    (Text("Why: ").foregroundColor(Web.ink).fontWeight(.heavy) + Text(why))
                        .font(Web.font(14, .semibold, .subheadline)).foregroundStyle(Web.muted).lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .background(Web.panel, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(border, lineWidth: 1))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("ce-result")
            if room.isOwner {
                Button(q.n < q.of ? "Next question" : "See the standings") { room.move("next"); Haptics.select() }
                    .buttonStyle(WebGoButton()).accessibilityIdentifier("ce-next")
            }
            if let e = q.endsAt {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let left = max(0, Int((e / 1000 - ctx.date.timeIntervalSince1970).rounded(.up)))
                    Text(left == 0 ? " " : room.isOwner ? "Or it goes on by itself in \(left)s." : q.n < q.of ? "Next question in \(left)s." : "The standings in \(left)s.")
                        .font(Web.font(13, .semibold, .footnote).monospacedDigit()).foregroundStyle(Web.muted)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("ce-next-in")
                }
            }
        }
    }

    /// At the answer, each player's range and points ("52–68 · +12", "no range").
    private func rangeNote(_ p: ScorePlayer) -> String {
        guard !asking, let x = q.results[p.id] else { return "" }
        guard let a = x.lo, let b = x.hi else { return "no range" }
        return "\(Web.bare(a, q))–\(Web.bare(b, q))" + (x.points > 0 ? " · +\(x.points)" : " · 0")
    }
}

/// `.clock`: the countdown in its box, gold in the last ten seconds.
struct WebClock: View {
    let endsAt: Double
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let left = max(0, Int((endsAt / 1000 - ctx.date.timeIntervalSince1970).rounded(.up)))
            let low = left <= 10
            Text(String(format: "%d:%02d", left / 60, left % 60)).font(Web.font(15, .heavy, .subheadline).monospacedDigit())
                .tracking(0.6).foregroundStyle(low ? Web.accentInk : Web.ink)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(low ? Web.accent : .clear, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(low ? Web.accent : Web.line, lineWidth: 1))
                .accessibilityLabel("\(left) seconds left")
        }
    }
}

/// The website's end of the game (`#done`): Game over, who won, everyone's points and how often their range held the
/// answer, then Play again and Change seats (the owner) or who starts the next one. Back to Library is the app's own.
struct CloseEnoughWebOver: View {
    @ObservedObject var room: RoomModel
    @Environment(\.dynamicTypeSize) private var textSize
    @EnvironmentObject var app: AppModel
    let view: CloseEnough.View
    var body: some View {
        let me = view.common.meId
        let winners = view.common.winners ?? []
        let names = winners.compactMap { w in view.players.first { $0.id == w } }.map { RoomPlayer.stripBot($0.name) }
        let title = winners.contains(me) ? (winners.count > 1 ? "A shared win!" : "You win!") : names.count > 1 ? "A shared win!" : names.first.map { "\($0) wins!" } ?? "Game over"
        ScrollView {
            VStack(spacing: 12) {
                Text("Game over".uppercased()).font(Web.font(12, .bold, .caption)).tracking(1.4).foregroundStyle(Web.muted).padding(.top, 6)
                Text(title).font(Web.font(30, .heavy, .largeTitle)).foregroundStyle(Web.ink).multilineTextAlignment(.center)
                    .accessibilityIdentifier("game-over")
                VStack(spacing: 6) {
                    ForEach(view.players.filter { !$0.left || $0.score > 0 }.sorted { $0.score > $1.score }) { p in
                        WebPlayerRow(p: p, me: me, owner: view.common.hostless ? view.common.owner : nil,
                                     note: "\(p.hits) of \(p.hits + p.misses) in range", score: "\(p.score)", win: winners.contains(p.id))
                    }
                }
                Text(room.isOwner ? "Play again with everyone here, or change seats first."
                     : view.common.hostless ? "If \(room.ownerName ?? "the room’s owner") starts another game, you’ll be in it." : "")
                    .font(Web.font(13, .semibold, .footnote)).foregroundStyle(Web.muted).multilineTextAlignment(.center)
                if room.isOwner {
                    Button("Play again") { room.send(Out.again); room.send(Out.deal); Haptics.play() }.buttonStyle(WebGoButton())
                        .accessibilityIdentifier("play-again")
                    Button("Change seats") { room.send(Out.again) }.buttonStyle(WebGhostButton())
                }
                WebReactions(room: room)
                Button("Back to Library") { room.leave(); app.closeRoom(); app.tab = .library }
                    .buttonStyle(WebGhostButton()).padding(.top, 4)
                    .accessibilityIdentifier("back-to-library")
                TipLine()   // #598
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 18)
            .frame(maxWidth: 480).frame(maxWidth: .infinity)
        }
        .onAppear { if winners.contains(me) { Haptics.yourTurn() } }
    }
}
