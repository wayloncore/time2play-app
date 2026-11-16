import SwiftUI
import T2PCore

/// A die with pips, drawn (ivory, like the website's Hot Dice).
struct DieView: View {
    let value: Int?
    var size: CGFloat = 54
    var selected = false
    var dimmed = false
    var held = false
    /// A blank face: the dice are in the air (with Reduce Motion on, they don't tumble; the faces just appear).
    var blank = false
    /// #488: this die can score (a thin gold ring), or it came up in a Farkle (an ember ring).
    var scores = false
    var farkled = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                .fill(Color(hex: 0xF6EEDB))
                .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
            if let v = value { pips(v) } else if !blank {
                Image(systemName: "questionmark").font(.system(size: size * 0.4, weight: .bold)).foregroundStyle(Color(hex: 0x6B5A40))
            }
        }
        .frame(width: size, height: size)
        .overlay(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous).stroke(ring, lineWidth: selected || held || farkled ? 4 : 2.5).padding(-2))
        .opacity(dimmed ? 0.45 : 1)
        .offset(y: selected ? -6 : 0)
        .animation(.spring(duration: 0.25), value: selected)
    }

    private var ring: Color {
        if selected || held { return T2P.gold }
        if farkled { return T2P.ember }
        return scores ? T2P.gold.opacity(0.7) : .clear
    }

    private func pips(_ v: Int) -> some View {
        let spots: [(CGFloat, CGFloat)] = {
            let a: CGFloat = 0.27, b: CGFloat = 0.5, c: CGFloat = 0.73
            switch v {
            case 1: return [(b, b)]
            case 2: return [(a, a), (c, c)]
            case 3: return [(a, a), (b, b), (c, c)]
            case 4: return [(a, a), (c, a), (a, c), (c, c)]
            case 5: return [(a, a), (c, a), (b, b), (a, c), (c, c)]
            default: return [(a, a), (c, a), (a, b), (c, b), (a, c), (c, c)]
            }
        }()
        return ZStack {
            ForEach(Array(spots.enumerated()), id: \.offset) { _, p in
                Circle().fill(v == 1 ? Color(hex: 0xB0302A) : Color(hex: 0x231A10))
                    .frame(width: size * 0.17, height: size * 0.17)
                    .position(x: p.0 * size, y: p.1 * size)
            }
        }
        .frame(width: size, height: size)
    }
}

/// A die in the air (#488): its face flicks and it wobbles until the room says where it landed. Short, by design:
/// the room reveals a roll about a second after it's thrown.
struct TumblingDie: View {
    var size: CGFloat
    var seed: Int
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.08)) { ctx in
            let k = Int(ctx.date.timeIntervalSinceReferenceDate / 0.08)
            let h = (k &* 1_103_515_245 &+ seed &* 12_345) & 0x7fff_ffff
            DieView(value: 1 + h % 6, size: size)
                .rotationEffect(.degrees(Double((h >> 4) % 36) - 18))
                .offset(x: CGFloat((h >> 9) % 7) - 3, y: CGFloat((h >> 13) % 9) - 6)
        }
    }
}

/// How a die arrives (#488): a small drop and settle, and a shake when it's a Farkle. Reduce Motion: it just appears.
struct Landing: ViewModifier {
    var shake = false
    @Environment(\.accessibilityReduceMotion) private var still
    @State private var down = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(down || still ? 1 : 1.18)
            .rotationEffect(.degrees(down || still ? 0 : 10))
            .modifier(Shake(progress: shake && down && !still ? 1 : 0))
            .onAppear { withAnimation(.spring(duration: 0.35, bounce: 0.45)) { down = true } }
    }
}

/// A side-to-side shake, three times across, as the website shakes a Farkle's dice.
struct Shake: GeometryEffect {
    var progress: CGFloat
    var animatableData: CGFloat { get { progress } set { progress = newValue } }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: sin(progress * .pi * 6) * 6 * (1 - progress * 0.5), y: 0))
    }
}

/// Shows its content a beat after it appears: the dice first, then what they mean (#488).
struct AfterTheDice: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var still
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .opacity(on ? 1 : 0)
            .onAppear { withAnimation(.easeIn(duration: 0.25).delay(still ? 0 : 0.4)) { on = true } }
    }
}

/// A scores strip: everyone at the table, whose turn it is, and each score.
struct ScoreStrip: View {
    @ScaledMetric(relativeTo: .headline) private var face: CGFloat = 44
    let players: [ScorePlayer]
    let turn: String?
    let owner: String?
    let me: String
    var detail: (ScorePlayer) -> String? = { _ in nil }
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(players.filter { !$0.left }) { p in
                    VStack(spacing: 4) {
                        FaceView(face: p.face, size: face, dimmed: !p.connected && p.bot == nil)
                            .overlay(Circle().stroke(turn == p.id ? T2P.gold : .clear, lineWidth: 3).padding(-3))
                        HStack(spacing: 3) {
                            Text(p.id == me ? "You" : RoomPlayer.stripBot(p.name)).font(.caption.weight(.semibold)).foregroundStyle(T2P.text).lineLimit(1)
                            if p.id == owner { Image(systemName: "crown.fill").font(.system(size: 9)).foregroundStyle(T2P.gold) }
                        }
                        Text(p.score.formatted()).font(.headline.monospacedDigit()).foregroundStyle(T2P.text)
                        if let d = detail(p) { Text(d).font(.caption2).foregroundStyle(T2P.muted).lineLimit(1) }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .frame(minWidth: 84)
                    .background(Color.primary.opacity(turn == p.id ? 0.12 : 0.05), in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(p.id == me ? "You" : RoomPlayer.stripBot(p.name))\(p.bot != nil ? ", bot" : ""), \(p.score) points\(turn == p.id ? ", their turn" : "")\(detail(p).map { ", \($0)" } ?? "")")
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

/// Who won, the final scores, and for the owner, Play again and Change seats.
struct GameOver: View {
    @ObservedObject var room: RoomModel
    let players: [ScorePlayer]
    let winners: [String]
    let me: String
    var line: (ScorePlayer) -> String = { "\($0.score.formatted())" }
    var body: some View {
        let sorted = players.filter { !$0.left || $0.score > 0 }.sorted { $0.score > $1.score }
        let names = winners.compactMap { w in players.first { $0.id == w } }.map { $0.id == me ? "You" : RoomPlayer.stripBot($0.name) }
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: winners.contains(me) ? "trophy.fill" : "flag.checkered").font(.system(size: 48)).foregroundStyle(T2P.gold).accessibilityHidden(true)
                Text(winners.count > 1 ? "A shared win!" : winners.contains(me) ? "You win!" : "\(names.first ?? "Someone") wins!")
                    .font(.largeTitle.bold()).foregroundStyle(T2P.text).accessibilityIdentifier("game-over")
                VStack(spacing: 0) {
                    ForEach(sorted) { p in
                        HStack(spacing: 12) {
                            FaceView(face: p.face, size: 40)
                            Text(p.id == me ? "You" : RoomPlayer.stripBot(p.name)).font(.headline).foregroundStyle(T2P.text)
                            if winners.contains(p.id) { Image(systemName: "crown.fill").foregroundStyle(T2P.gold) }
                            Spacer()
                            Text(line(p)).font(.headline.monospacedDigit()).foregroundStyle(T2P.text)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .accessibilityElement(children: .combine)
                    }
                }
                .background(T2P.panel, in: RoundedRectangle(cornerRadius: 18))
                if room.isOwner {
                    Button("Play again") { room.send(Out.again); room.send(Out.deal); Haptics.play() }.buttonStyle(GoldButtonStyle())
                        .accessibilityIdentifier("play-again")
                    Button("Change seats") { room.send(Out.again) }.buttonStyle(QuietButtonStyle())
                } else {
                    Text("Waiting for \(room.ownerName ?? "the room’s owner") to start another.").foregroundStyle(T2P.muted)
                }
            }
            .padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
    }
}

/// Hot Dice (#401): the website's Farkle Live, with no big screen, against Penny, June and Rex.
/// #488: a roll tumbles, lands and stays on screen; the dice that can score are marked; a Farkle shows its dice, then
/// why nothing scored, before the turn moves on. Everyone at the table sees each roll land, bots' too.
struct HotDiceView: View {
    @ObservedObject var room: RoomModel
    @Environment(\.horizontalSizeClass) private var hsize
    @Environment(\.accessibilityReduceMotion) private var still
    let view: HotDice.View
    var onLeave: () -> Void
    @State private var celebrate: HotDice.Highlight?
    /// A Farkle stays up about as long as the room holds it (2.4 s), even if the next turn's view comes sooner; a tap
    /// clears it early.
    @State private var farkle: HotDice.Turn?

    private var me: String { view.common.meId }
    private var t: HotDice.Turn? { view.turn }
    /// The turn the panel draws: the room's, or the Farkle still being shown while the next player gets ready.
    private var shown: HotDice.Turn? {
        if let f = farkle, let t, t.state == "start" || (t.n == f.n && t.state == "farkle") { return f }
        return t
    }
    private var mine: Bool { view.common.yourTurn }
    private func name(_ id: String?) -> String { id == me ? "You" : view.player(id).map { RoomPlayer.stripBot($0.name) } ?? "Someone" }

    var body: some View {
        VStack(spacing: 0) {
            TableTopBar(game: room.game, code: room.code, line: topLine, onLeave: onLeave, owner: room.isOwner, room: room)
            if view.common.phase == "done" {
                GameOver(room: room, players: view.players, winners: view.common.winners ?? [], me: me)
            } else {
                ScoreStrip(players: view.players, turn: t?.id, owner: view.common.owner, me: me) { p in
                    !view.board || p.on ? (p.strikes > 0 ? "\(p.strikes) Farkle\(p.strikes == 1 ? "" : "s")" : nil) : "not on the board"
                }
                .padding(.vertical, 8)
                Text(targetLine).font(.footnote).foregroundStyle(T2P.muted)
                Spacer(minLength: 6)
                turnPanel
                Spacer(minLength: 6)
                buttons
                ReactionBar(room: room)
            }
        }
        .overlay { if let c = celebrate { Celebration(h: c).onTapGesture { celebrate = nil } } }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)   // a table, like Overdraft's: words to the largest standard size
        .onChange(of: t?.hl?.seq) { _, s in
            if mine, let h = t?.hl, s != nil, h.tier >= 2 {
                celebrate = h; Haptics.yourTurn()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { if celebrate == h { celebrate = nil } }
            }
        }
        .onChange(of: mine) { _, m in if m { Haptics.yourTurn() } }
        .onChange(of: t?.state) { was, s in
            // your dice land: a light tap, or the warning buzz for a Farkle
            if mine && was == "rolling" && s != "rolling" { s == "farkle" ? Haptics.nope() : Haptics.play() }
        }
        .onChange(of: t.map { $0.state == "farkle" ? "\($0.n):\($0.seq)" : "" }) { _, key in
            guard let key, !key.isEmpty, let t else { return }
            farkle = t
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4 + (t.three ? 1.5 : 0)) {
                if let f = farkle, "\(f.n):\(f.seq)" == key { farkle = nil }
            }
        }
        .onChange(of: t?.state) { _, s in if s != "start" && s != "farkle" { farkle = nil } }   // the next roll is up
    }

    private var topLine: String {
        if view.common.phase == "done" { return "GAME OVER" }
        if view.finalBy != nil { return "LAST ROUND" }
        return mine ? "YOUR TURN" : "\(name(t?.id).uppercased())’S TURN"
    }

    private var targetLine: String {
        if let by = view.finalBy { return "\(name(by)) reached \(view.target.formatted()): everyone else gets one last turn" }
        return [view.lastLine, "\(view.target.formatted()) wins"].compactMap { $0 }.joined(separator: " · ")
    }

    private var status: String {
        guard let t = shown else { return "" }
        let theirs = t.id != me
        if t.state == "farkle" { return theirs ? "\(name(t.id))’s roll" : "Your roll" }
        if view.common.held { return "A bot is playing your seat until your next turn" }
        if t.auto { return "Out of time: the room is finishing this turn" }
        switch t.state {
        case "start": return mine ? "Roll all six to start your turn" : "\(name(t.id)) is about to roll"
        case "rolling": return view.common.hostless ? (theirs ? "\(name(t.id)) is rolling…" : "Rolling…") : "Watch the big screen"
        case "hot": return mine ? "Hot dice! Roll all six again, or bank" : "Hot dice for \(name(t.id))!"
        default:
            if !mine { return t.selPts > 0 ? "\(name(t.id)) is keeping \(t.selName.isEmpty ? "dice" : t.selName)" : "\(name(t.id)) is choosing" }
            if !t.note.isEmpty && t.sel.isEmpty { return t.note }
            if t.sel.isEmpty { return "Tap the dice you want to keep" }
            let total = t.pts + t.selPts
            if t.need > 0 && total < t.need { return "You need \(t.need) to get on the board" }
            return "Bank it for \(total.formatted()), or roll \(rollCount) dice"
        }
    }

    /// The Farkle line, under its dice: what was lost, then why nothing scored.
    private func farkleWords(_ t: HotDice.Turn) -> (title: String, line: String) {
        let who = t.id == me ? "" : " for \(name(t.id))"
        if t.three { return ("Three Farkles\(who)!", t.penalty > 0 ? "−\(t.penalty.formatted()) points" : "No points to lose") }
        return ("Farkle\(who)!", t.lost > 0 ? "\(t.lost.formatted()) lost" : "Nothing scores")
    }

    private var rollCount: Int {
        guard let t else { return 6 }
        if t.state == "choose" { let n = t.live.count - t.sel.count; return n <= 0 ? 6 : n }
        return 6
    }
    private var canRoll: Bool {
        guard mine, let t else { return false }
        return t.state == "start" || t.state == "hot" || (t.state == "choose" && !t.sel.isEmpty && t.selPts > 0)
    }
    private var canBank: Bool {
        guard mine, let t else { return false }
        if t.state == "hot" { return t.pts >= t.need }
        return t.state == "choose" && t.selPts > 0 && t.pts + t.selPts >= t.need
    }

    /// The faces in this roll that can score, by the website's own scoring (its phone dims the rest the same way).
    private func scoring(_ t: HotDice.Turn) -> Set<Int>? {
        guard t.state == "choose" else { return nil }
        let values = t.live.compactMap { t.value($0) }
        guard values.count == t.live.count else { return nil }
        return room.rules?.scoringFaces(values, ones: view.ones)
    }

    @ViewBuilder private var turnPanel: some View {
        if let t = shown {
            let farkled = t.state == "farkle"
            VStack(spacing: 14) {
                VStack(spacing: 2) {
                    Text("This turn").font(.subheadline.weight(.semibold)).foregroundStyle(T2P.muted)
                    Text((farkled ? 0 : t.pts + (t.state == "choose" ? t.selPts : 0)).formatted()).font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(farkled ? T2P.ember : T2P.text).contentTransition(.numericText())
                    Text(status).font(.headline).foregroundStyle(T2P.text).multilineTextAlignment(.center)
                        .accessibilityIdentifier("dice-status")
                }
                .accessibilityElement(children: .combine)
                dice(t)
                if farkled {
                    let w = farkleWords(t)
                    VStack(spacing: 4) {
                        Text(w.title).font(.title.bold()).foregroundStyle(T2P.ember)
                        Text(w.line).font(.subheadline.weight(.semibold)).foregroundStyle(T2P.text)
                        Text(HotDice.farkleWhy(dice: t.live.count)).font(.subheadline).foregroundStyle(T2P.muted).multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(T2P.ember.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
                    .modifier(AfterTheDice())
                    .id("farkle-\(t.n)-\(t.seq)")
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("farkle-banner")
                    .onTapGesture { if self.t?.state != "farkle" { farkle = nil } }   // the room has moved on: a tap clears it
                }
                if mine && t.state == "choose" && !t.sel.isEmpty {
                    Text(t.selPts > 0 ? "\(t.selName.isEmpty ? "Kept" : t.selName) · +\(t.selPts.formatted())" : "Those don’t score together")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(T2P.gold)
                }
                if !t.kept.isEmpty && !farkled {
                    VStack(spacing: 6) {
                        Text("Set aside: +\(t.pts.formatted())").font(.footnote.weight(.semibold)).foregroundStyle(T2P.muted)
                        HStack(spacing: 6) { ForEach(t.kept, id: \.self) { k in DieView(value: t.value(k), size: 30, held: true) } }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Set aside \(t.kept.compactMap { t.value($0) }.map(String.init).joined(separator: ", ")), worth \(t.pts)")
                }
            }
        } else {
            Text("Waiting for the first roll").foregroundStyle(T2P.muted)
        }
    }

    /// The live dice: in the air, landed (the ones that can score marked), or a Farkle's.
    private func dice(_ t: HotDice.Turn) -> some View {
        let live = t.dice.filter { t.live.contains($0.id) }
        let size: CGFloat = hsize == .regular ? 96 : 64
        let scores = scoring(t)
        let tappable = mine && t.state == "choose" && !view.common.held && t.id == self.t?.id && self.t?.state == "choose"
        return LazyVGrid(columns: Array(repeating: GridItem(.fixed(hsize == .regular ? 104 : 70), spacing: 14), count: min(3, max(1, live.count))), spacing: 10) {
            ForEach(live) { d in
                let sel = t.sel.contains(d.id)
                let canScore = scores.map { s in d.v.map { s.contains($0) } ?? false }
                Button { if tappable { room.move("tap", ["die": .number(Double(d.id))]); Haptics.select() } } label: {
                    VStack(spacing: 3) {
                        if t.state == "rolling" || d.v == nil {
                            if view.common.hostless && !still { TumblingDie(size: size, seed: d.id) } else { DieView(value: nil, size: size, blank: true) }
                        } else {
                            DieView(value: d.v, size: size, selected: sel, dimmed: canScore == false && !sel, scores: canScore == true && !sel,
                                    farkled: t.state == "farkle")
                                .modifier(Landing(shake: t.state == "farkle"))
                        }
                        Text(canScore == true && !sel ? "SCORES" : " ").font(.caption2.weight(.bold)).foregroundStyle(T2P.gold)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!tappable)
                .accessibilityLabel(t.state == "rolling" || d.v == nil ? "Die, rolling" : "Die showing \(d.v!)")
                .accessibilityValue(sel ? "kept" : canScore == true ? "scores" : canScore == false ? "doesn’t score" : "")
                .accessibilityAddTraits(sel ? .isSelected : [])
                .accessibilityIdentifier("die-\(d.id)")
            }
        }
        .id("roll-\(t.n)-\(t.seq)")
        .padding(.horizontal, 24)
    }

    @ViewBuilder private var buttons: some View {
        if mine {
            HStack(spacing: 12) {
                Button { room.move("roll"); Haptics.play() } label: {
                    VStack(spacing: 0) { Text("Roll"); Text("\(rollCount) dice").font(.caption) }
                }
                .buttonStyle(GoldButtonStyle()).disabled(!canRoll).accessibilityIdentifier("roll")
                Button { room.move("bank"); Haptics.yourTurn() } label: {
                    VStack(spacing: 0) { Text("Bank"); Text("+\(((t?.pts ?? 0) + (t?.state == "choose" ? t?.selPts ?? 0 : 0)).formatted())").font(.caption) }
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(QuietButtonStyle()).disabled(!canBank).accessibilityIdentifier("bank")
            }
            .padding(.horizontal, 20)
        }
    }
}

struct Celebration: View {
    let h: HotDice.Highlight
    var body: some View {
        VStack(spacing: 6) {
            Text(h.name).font(.largeTitle.bold()).foregroundStyle(T2P.ink)
            Text("+\(h.points.formatted())").font(.title.bold()).foregroundStyle(T2P.ink)
        }
        .padding(.horizontal, 32).padding(.vertical, 20)
        .background(T2P.gold, in: RoundedRectangle(cornerRadius: 24))
        .shadow(radius: 20)
        .transition(.scale.combined(with: .opacity))
        .accessibilityElement(children: .combine)
    }
}
