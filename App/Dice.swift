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

/// A die as a button that never greys out when it can't be tapped (someone else's roll, dice in the air): the dice say
/// what they mean themselves, dimmed only when they can't score.
struct DieButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.contentShape(Rectangle()) }
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

/// Who won and why, the final scores, and what next (#489): for the owner, Play again and Change seats; for everyone,
/// Back to Library.
struct GameOver: View {
    @ObservedObject var room: RoomModel
    @EnvironmentObject var app: AppModel
    let players: [ScorePlayer]
    let winners: [String]
    let me: String
    /// Why the game ended, in a sentence ("Ada reached 10,000, and everyone else had one last turn.").
    var reason: String? = nil
    var line: (ScorePlayer) -> String = { "\($0.score.formatted())" }
    /// A line under a player's name (Roll Call: the bonuses in their total).
    var detail: (ScorePlayer) -> String? = { _ in nil }
    var body: some View {
        let sorted = players.filter { !$0.left || $0.score > 0 }.sorted { $0.score > $1.score }
        let names = winners.compactMap { w in players.first { $0.id == w } }.map { $0.id == me ? "You" : RoomPlayer.stripBot($0.name) }
        ScrollView {
            VStack(spacing: 16) {
                if winners.count == 1, let w = players.first(where: { $0.id == winners[0] }) {
                    FaceView(face: w.face, size: 76).overlay(Circle().stroke(T2P.gold, lineWidth: 3).padding(-3))
                } else {
                    Image(systemName: winners.contains(me) ? "trophy.fill" : "flag.checkered").font(.system(size: 48)).foregroundStyle(T2P.gold).accessibilityHidden(true)
                }
                Text(winners.count > 1 ? "A shared win!" : winners.contains(me) ? "You win!" : "\(names.first ?? "Someone") wins!")
                    .font(.largeTitle.bold()).foregroundStyle(T2P.text).accessibilityIdentifier("game-over")
                if let r = reason {
                    Text(winners.count > 1 ? "\(r) \(names.joined(separator: " and ")) finished level." : r)
                        .foregroundStyle(T2P.muted).multilineTextAlignment(.center).accessibilityIdentifier("game-over-why")
                }
                VStack(spacing: 0) {
                    ForEach(sorted) { p in
                        HStack(spacing: 12) {
                            FaceView(face: p.face, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(p.id == me ? "You" : RoomPlayer.stripBot(p.name)).font(.headline).foregroundStyle(T2P.text)
                                    if p.bot != nil { Tag(text: "BOT") }
                                    if winners.contains(p.id) { Image(systemName: "crown.fill").foregroundStyle(T2P.gold) }
                                }
                                if let d = detail(p) { Text(d).font(.subheadline).foregroundStyle(T2P.muted) }
                            }
                            Spacer()
                            Text(line(p)).font(.title3.bold().monospacedDigit()).foregroundStyle(T2P.text)
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
                    Text("If \(room.ownerName ?? "the room’s owner") starts another game, you’ll be in it.").foregroundStyle(T2P.muted).multilineTextAlignment(.center)
                }
                Button("Back to Library") { room.leave(); app.closeRoom(); app.tab = .library }
                    .font(.headline).foregroundStyle(T2P.goldText).frame(minHeight: 44)
                    .accessibilityIdentifier("back-to-library")
            }
            .padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .onAppear { if winners.contains(me) { Haptics.yourTurn() } }
    }
}

/// One line of what just happened at a dice table (#489), with the dice it was about when there are some.
struct MomentLine: Identifiable, Equatable { let id = UUID(); let text: String; var dice: [Int] = [] }

/// What just happened (#489): the newest line bright, the two before it fainter, as Overdraft's table shows it.
struct MomentFeed: View {
    let lines: [MomentLine]
    let id: String
    @Environment(\.accessibilityReduceMotion) private var still
    var body: some View {
        VStack(spacing: 3) {
            ForEach(Array(lines.enumerated()), id: \.element.id) { i, l in
                HStack(spacing: 6) {
                    Text(l.text)
                        .font(i == 0 ? Font.subheadline.weight(.semibold) : Font.footnote)
                        .foregroundStyle(i == 0 ? T2P.text : T2P.muted.opacity(i == 1 ? 1 : 0.7))
                        .lineLimit(1).minimumScaleFactor(0.75)
                    if !l.dice.isEmpty {
                        HStack(spacing: 2) { ForEach(Array(l.dice.enumerated()), id: \.offset) { _, v in DieView(value: v, size: i == 0 ? 18 : 14) } }
                            .opacity(i == 0 ? 1 : 0.7)
                    }
                }
                .transition(still ? AnyTransition.opacity : AnyTransition.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(minHeight: lines.isEmpty ? 0 : 44, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lines.first.map { $0.dice.isEmpty ? $0.text : "\($0.text), with \($0.dice.map(String.init).joined(separator: ", "))" } ?? "")
        .accessibilityIdentifier(id)
    }

    /// Adds a line at the top, keeping three.
    static func add(_ text: String, dice: [Int] = [], to lines: inout [MomentLine], still: Bool) {
        withAnimation(still ? nil : Animation.easeOut(duration: 0.25)) {
            lines.insert(MomentLine(text: text, dice: dice), at: 0)
            if lines.count > 3 { lines.removeLast(lines.count - 3) }
        }
    }
}

/// A big moment over the table for a moment (#489): a bank, hot dice, the last round, a bonus. It never takes a tap.
struct BigMoment: Identifiable, Equatable { let id = UUID(); let icon: String; let word: String; let detail: String }

struct BigMomentCard: View {
    let m: BigMoment
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: m.icon).font(.title2.weight(.bold)).foregroundStyle(T2P.ink).accessibilityHidden(true)
            Text(m.word).font(.title.bold()).foregroundStyle(T2P.ink)
            Text(m.detail).font(.subheadline.weight(.semibold)).foregroundStyle(T2P.ink).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 26).padding(.vertical, 16)
        .frame(maxWidth: 340)
        .background(T2P.gold, in: RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(0.35), radius: 16)
        .padding(.horizontal, 24)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("big-moment")
    }

    /// Shows `m` over the table for about 1.6 seconds, said aloud to VoiceOver too.
    static func show(_ m: BigMoment, in slot: Binding<BigMoment?>, still: Bool) {
        withAnimation(still ? Animation.easeInOut(duration: 0.2) : Animation.spring(duration: 0.3)) { slot.wrappedValue = m }
        UIAccessibility.post(notification: .announcement, argument: "\(m.word). \(m.detail)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            if slot.wrappedValue?.id == m.id { withAnimation(.easeOut(duration: 0.3)) { slot.wrappedValue = nil } }
        }
    }
}

/// Hot Dice (#401): the website's Farkle Live, with no big screen, against Penny, June and Rex.
/// #488: a roll tumbles, lands and stays on screen; the dice that can score are marked; a Farkle shows its dice, then
/// why nothing scored, before the turn moves on. Everyone at the table sees each roll land, bots' too.
/// #489: a line of what just happened (dice set aside, a bank, a Farkle, a turn the room finished), a bank, hot dice
/// and the last round said big for a moment, who's up next, a tap that ends a Farkle's hold, and the end of the game
/// saying why it ended.
struct HotDiceView: View {
    @ObservedObject var room: RoomModel
    @Environment(\.horizontalSizeClass) private var hsize
    @Environment(\.accessibilityReduceMotion) private var still
    let view: HotDice.View
    var onLeave: () -> Void
    /// #521: the 3D dice arena (You → "3D dice (preview)"); off draws the flat dice as before.
    var arena = false
    @StateObject private var arenaStage = DiceArenaStage()
    @State private var celebrate: HotDice.Highlight?
    /// A Farkle stays up about as long as the room holds it (2.4 s), even if the next turn's view comes sooner; a tap
    /// clears it early.
    @State private var farkle: HotDice.Turn?
    @State private var feed: [MomentLine] = []
    @State private var big: BigMoment?

    private var me: String { view.common.meId }
    private var t: HotDice.Turn? { view.turn }
    /// The turn the panel draws: the room's, or the Farkle still being shown while the next player gets ready.
    private var shown: HotDice.Turn? {
        if let f = farkle, let t, t.state == "start" || (t.n == f.n && t.state == "farkle") { return f }
        // #521: the 3D dice show a Farkle for its full hold after they land, even if the next player has started
        // rolling (the tray catches up a moment later); your own roll always takes over at once
        if arena, let f = farkle, !(mine && t?.state != "start") { return f }
        return t
    }
    private var mine: Bool { view.common.yourTurn }
    private func name(_ id: String?) -> String { id == me ? "You" : view.player(id).map { RoomPlayer.stripBot($0.name) } ?? "Someone" }

    var body: some View {
        VStack(spacing: 0) {
            TableTopBar(game: room.game, code: room.code, line: topLine, onLeave: onLeave, owner: room.isOwner, room: room)
            if view.common.phase == "done" {
                GameOver(room: room, players: view.players, winners: view.common.winners ?? [], me: me, reason: endReason)
            } else {
                ScoreStrip(players: view.players, turn: t?.id, owner: view.common.owner, me: me) { p in
                    !view.board || p.on ? (p.strikes > 0 ? "\(p.strikes) Farkle\(p.strikes == 1 ? "" : "s")" : nil) : "not on the board"
                }
                .padding(.vertical, 8)
                Text(targetLine).font(.footnote).foregroundStyle(view.finalBy != nil ? T2P.goldText : T2P.muted)
                    .multilineTextAlignment(.center).padding(.horizontal, 16).accessibilityIdentifier("hd-target")
                MomentFeed(lines: feed, id: "hd-feed").padding(.top, 6)
                if arena {
                    arenaPanel.padding(.vertical, 4)
                } else {
                    Spacer(minLength: 6)
                    turnPanel
                    Spacer(minLength: 6)
                }
                buttons
                ReactionBar(room: room)
            }
        }
        .overlay { if let c = celebrate { Celebration(h: c).onTapGesture { celebrate = nil } } }
        .overlay { if let b = big, celebrate == nil { BigMomentCard(m: b).transition(still ? AnyTransition.opacity : AnyTransition.scale.combined(with: .opacity)) } }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)   // a table, like Overdraft's: words to the largest standard size
        .onChange(of: view) { old, new in changed(from: old, to: new) }
        .onChange(of: t?.hl?.seq) { _, s in if !arena, s != nil { celebrateRoll() } }
        .onChange(of: arenaStage.landed) { _, key in
            // #521: what a roll means waits for its dice to land
            guard arena, let key, let t = shown, key == "\(t.n).\(t.seq)" else { return }
            if t.state == "farkle" {
                if t.id == me { Haptics.nope() }
                // the hold starts when the Farkle can be seen
                let k = "\(t.n):\(t.seq)"
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.4 + (t.three ? 1.5 : 0)) {
                    if let f = farkle, "\(f.n):\(f.seq)" == k { farkle = nil }
                }
            }
            celebrateRoll()
        }
        .onChange(of: mine) { _, m in if m { Haptics.yourTurn() } }
        .onChange(of: t?.state) { was, s in
            // your dice land: a light tap, or the warning buzz for a Farkle (the 3D dice tap when they hit the felt)
            if !arena && mine && was == "rolling" && s != "rolling" { s == "farkle" ? Haptics.nope() : Haptics.play() }
        }
        .onChange(of: t.map { $0.state == "farkle" ? "\($0.n):\($0.seq)" : "" }) { _, key in
            guard let key, !key.isEmpty, let t else { return }
            farkle = t
            // the 3D dice hold it from when they land (above); this is their backstop if they never do
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4 + (t.three ? 1.5 : 0) + (arena ? 6 : 0)) {
                if let f = farkle, "\(f.n):\(f.seq)" == key { farkle = nil }
            }
        }
        .onAppear { arenaStage.onFirstHit = { Haptics.play() } }
        .onChange(of: t?.state) { _, s in   // the next roll is up (with the 3D dice, only yours cuts a Farkle short)
            if s != "start" && s != "farkle" && (!arena || mine) { farkle = nil }
        }
    }

    /// A big roll of yours (three of a kind and up) said big for a moment.
    private func celebrateRoll() {
        guard mine, let h = t?.hl, h.tier >= 2 else { return }
        celebrate = h; Haptics.yourTurn()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { if celebrate == h { celebrate = nil } }
    }

    /// #521: the shown roll's dice are down (always, for the flat dice): until then the 3D arena keeps what it means
    /// (the Farkle, the status) back.
    private var settled: Bool {
        guard arena, let t = shown, t.state == "choose" || t.state == "farkle" else { return true }
        return arenaStage.landed == "\(t.n).\(t.seq)"
    }

    private var topLine: String {
        if view.common.phase == "done" { return "GAME OVER" }
        if view.finalBy != nil { return "LAST ROUND" }
        return mine ? "YOUR TURN" : "\(name(t?.id).uppercased())’S TURN"
    }

    /// The target, and who's up after this turn (in the last round, only those still to have their last turn).
    private var targetLine: String {
        let next = upNext.map { "Up next: \($0 == me ? "you" : name($0))" }
        if let by = view.finalBy {
            return ["Last round: \(name(by)) reached \(view.target.formatted())", next].compactMap { $0 }.joined(separator: " · ")
        }
        return ["First to \(view.target.formatted()) wins", next].compactMap { $0 }.joined(separator: " · ")
    }

    private var upNext: String? {
        guard let t else { return nil }
        let order = view.players.filter { $0.seated && !$0.left }
        guard order.count > 1, let i = order.firstIndex(where: { $0.id == t.id }) else { return nil }
        let id = order[(i + 1) % order.count].id
        return view.finalBy == id ? nil : id   // who reached the target has had their last turn
    }

    private var endReason: String? {
        guard let by = view.finalBy else { return nil }
        return "\(name(by)) reached \(view.target.formatted()), and everyone else had one last turn."
    }

    // MARK: what just happened (#489)

    private func changed(from old: HotDice.View, to new: HotDice.View) {
        if old.common.phase != "playing" && new.common.phase == "playing" { feed = []; big = nil; farkle = nil }   // a new game
        let moments = HotDice.moments(from: old, to: new)
        for m in moments { if let w = words(m) { MomentFeed.add(w, to: &feed, still: still) } }
        if let b = moments.last(where: \.isBig), let f = flash(b) { BigMomentCard.show(f, in: $big, still: still) }
    }

    private func words(_ m: HotDice.Moment) -> String? {
        switch m {
        case let .kept(who, combo, points):
            return combo.isEmpty ? "\(name(who)) kept +\(points.formatted())" : "\(name(who)) kept \(combo.lowercased()): +\(points.formatted())"
        case let .hot(who): return who == me ? "Hot dice! You roll all six again" : "Hot dice! \(name(who)) rolls all six again"
        case let .banked(who, points, total):
            return "\(name(who)) banked \(points.formatted()) · \(who == me ? "you have" : "now") \(total.formatted())"
        case let .farkled(who, lost): return lost > 0 ? "\(name(who)) Farkled and lost \(lost.formatted())" : "\(name(who)) Farkled"
        case let .threeFarkles(who, penalty):
            return penalty > 0 ? "\(name(who)): three Farkles in a row, −\(penalty.formatted())" : "\(name(who)): three Farkles in a row"
        case let .timedOut(who): return who == me ? "Out of time: the room is finishing your turn" : "\(name(who)) ran out of time: the room is finishing the turn"
        case let .missed(who): return who == me ? "Your turn ran out" : "\(name(who))’s turn ran out"
        case let .left(who): return "\(name(who)) left the game"
        case let .lastRound(by): return "\(name(by)) reached \(view.target.formatted()): last round"
        }
    }

    private func flash(_ m: HotDice.Moment) -> BigMoment? {
        switch m {
        case let .banked(who, points, total):
            if who == me { Haptics.yourTurn() }
            return BigMoment(icon: "tray.and.arrow.down.fill", word: "Banked +\(points.formatted())",
                             detail: who == me ? "You have \(total.formatted())" : "\(name(who)) has \(total.formatted())")
        case let .hot(who):
            return BigMoment(icon: "flame.fill", word: "Hot dice!", detail: who == me ? "Roll all six again" : "\(name(who)) rolls all six again")
        case let .lastRound(by):
            Haptics.select()
            return BigMoment(icon: "flag.checkered", word: "Last round",
                             detail: "\(name(by)) reached \(view.target.formatted()). Everyone else gets one more turn.")
        default: return nil   // a Farkle has its own banner, under its dice
        }
    }

    /// A Farkle's hold can end early (#489): the player who Farkled taps it, or the room's owner for a bot's.
    private var canSkipFarkle: Bool {
        guard view.farkleSkip, let t, t.state == "farkle" else { return false }
        return t.id == me ? !view.common.held : (t.bot && room.isOwner)
    }

    private func skipFarkle() {
        if canSkipFarkle { room.move("next"); Haptics.select(); farkle = nil }
        else if t?.state != "farkle" { farkle = nil }   // the room has moved on: the tap clears what this phone still holds
    }

    private var status: String {
        guard let t = shown else { return "" }
        let theirs = t.id != me
        if !settled { return theirs ? "\(name(t.id)) is rolling…" : "Rolling…" }
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
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("dice-status")
                dice(t)
                if farkled {
                    let w = farkleWords(t)
                    VStack(spacing: 4) {
                        Text(w.title).font(.title.bold()).foregroundStyle(T2P.ember)
                        Text(w.line).font(.subheadline.weight(.semibold)).foregroundStyle(T2P.text)
                        Text(HotDice.farkleWhy(dice: t.live.count)).font(.subheadline).foregroundStyle(T2P.muted).multilineTextAlignment(.center)
                        if canSkipFarkle {
                            Text("Tap to go on").font(.caption.weight(.bold)).foregroundStyle(T2P.goldText).padding(.top, 4)
                        }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(T2P.ember.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
                    .modifier(AfterTheDice())
                    .id("farkle-\(t.n)-\(t.seq)")
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("farkle-banner")
                    .accessibilityHint(canSkipFarkle ? "Double-tap to go on" : "")
                    .accessibilityAction { skipFarkle() }
                    .onTapGesture { skipFarkle() }
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
                .buttonStyle(DieButtonStyle())
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

    // MARK: the 3D arena (#521)

    private var arenaState: ArenaState {
        ArenaState.hotDice(shown, scoringFaces: shown.flatMap { scoring($0) }, mine: shown?.id == me)
    }

    @ViewBuilder private var arenaPanel: some View {
        if let t = shown {
            let farkled = t.state == "farkle" && settled
            VStack(spacing: 6) {
                // the turn's points and what to do, or (in the same place, so the tray never moves) a Farkle and why
                Group {
                    if farkled {
                        arenaFarkle(t)
                    } else {
                        VStack(spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text((t.pts + (t.state == "choose" ? t.selPts : 0)).formatted())
                                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                                    .foregroundStyle(T2P.text).contentTransition(.numericText())
                                Text("this turn").font(.subheadline.weight(.semibold)).foregroundStyle(T2P.muted)
                            }
                            Text(status).font(.headline).foregroundStyle(T2P.text).multilineTextAlignment(.center).padding(.horizontal, 16)
                                .lineLimit(2).minimumScaleFactor(0.8)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("dice-status")
                    }
                }
                .frame(minHeight: 104)
                DiceArenaView(stage: arenaStage, state: arenaState, button: { arenaButton($0, t) }, onTap: { id in
                    if arenaTappable(t) { room.move("tap", ["die": .number(Double(id))]); Haptics.select() }
                })
                .frame(maxWidth: 760)
                .frame(minHeight: 250, maxHeight: .infinity)
                keepLine(t).frame(minHeight: 24)
            }
        } else {
            Text("Waiting for the first roll").foregroundStyle(T2P.muted).frame(maxHeight: .infinity)
        }
    }

    private func arenaTappable(_ t: HotDice.Turn) -> Bool {
        mine && t.state == "choose" && !view.common.held && t.id == self.t?.id && self.t?.state == "choose" && settled
    }

    private func arenaButton(_ d: ArenaDie, _ t: HotDice.Turn) -> ArenaDieButton? {
        if case .keep(_, true) = d.place {
            return ArenaDieButton(id: "kept-\(d.id)", label: "Set aside, showing \(d.face ?? 0)", value: "", enabled: false, button: false)
        }
        guard t.live.contains(d.id) else { return nil }
        let sel = t.sel.contains(d.id)
        let air = t.state == "rolling" || d.face == nil || !settled
        let canScore = scoring(t).map { s in d.face.map { s.contains($0) } ?? false }
        return ArenaDieButton(id: "die-\(d.id)", label: air ? "Die, rolling" : "Die showing \(d.face!)",
                              value: sel ? "kept" : canScore == true ? "scores" : canScore == false ? "doesn’t score" : "",
                              enabled: arenaTappable(t))
    }

    /// Under the keep row: what's set aside and what you're keeping.
    @ViewBuilder private func keepLine(_ t: HotDice.Turn) -> some View {
        let parts: [String] = [
            !t.kept.isEmpty && t.state != "farkle" ? "Set aside +\(t.pts.formatted())" : nil,
            mine && t.state == "choose" && !t.sel.isEmpty
                ? (t.selPts > 0 ? "\(t.selName.isEmpty ? "Keeping" : t.selName) +\(t.selPts.formatted())" : "Those don’t score together") : nil,
        ].compactMap { $0 }
        Text(parts.joined(separator: " · "))
            .font(.footnote.weight(.semibold)).foregroundStyle(T2P.gold)
            .opacity(parts.isEmpty ? 0 : 1)
            .accessibilityIdentifier("keep-line")
    }

    /// The Farkle over the 3D tray: what was lost and why nothing scored, where the turn's points were.
    private func arenaFarkle(_ t: HotDice.Turn) -> some View {
        let w = farkleWords(t)
        return VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(w.title).font(.title2.bold()).foregroundStyle(T2P.ember)
                Text(w.line).font(.subheadline.weight(.semibold)).foregroundStyle(T2P.text)
            }
            Text(HotDice.farkleWhy(dice: t.live.count)).font(.subheadline).foregroundStyle(T2P.muted).multilineTextAlignment(.center)
                .lineLimit(2).minimumScaleFactor(0.8)
            if canSkipFarkle {
                Text("Tap to go on").font(.caption.weight(.bold)).foregroundStyle(T2P.goldText).padding(.top, 2)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 8)
        .background(T2P.ember.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .modifier(AfterTheDice())
        .id("farkle-\(t.n)-\(t.seq)")
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("farkle-banner")
        .accessibilityHint(canSkipFarkle ? "Double-tap to go on" : "")
        .accessibilityAction { skipFarkle() }
        .onTapGesture { skipFarkle() }
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
