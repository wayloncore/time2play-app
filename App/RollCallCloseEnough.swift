import SwiftUI
import T2PCore

/// Yacht Dice (Roll Call in the code and the room): five dice, three rolls, thirteen boxes; against Pip, Rosa and
/// Viktor or friends. The room scores every box.
/// #488: every roll (yours, a friend's or a bot's) tumbles and lands before the boxes it can go in show.
/// #489: a line of what just happened (each box scored, with its dice, and a bonus earned), a Yacht or a bonus said big
/// for a moment, who's up next, How to play, and the end of the game saying why it ended.
/// Nov 20 (Tyler, 11:12 AM): laid out like a classic scorecard app, in the game's painted felt and gold. The scorecard
/// takes the screen (Upper on the left, Lower on the right, the totals and the bonus's progress under them), the five
/// dice sit locked in one row at the bottom with Roll under them. No table and no arena throw: each die not held
/// tumbles in its own place and lands flat, one face up; held dice stay still. The 3D dice setting doesn't apply here
/// (10,000 keeps its arena). Reduce Motion: the new faces fade in.
struct RollCallView: View {
    @ObservedObject var room: RoomModel
    @Environment(\.accessibilityReduceMotion) private var still
    let view: RollCall.View
    var onLeave: () -> Void
    @Environment(\.horizontalSizeClass) private var hsize
    /// The roll in the air (its RollCall.View.rollKey) and when it started, and the last roll seen, so a view arriving
    /// mid-turn doesn't tumble.
    @State private var tumbling: String?
    @State private var tumbleStart = Date()
    @State private var seen: String?
    @State private var appeared = false
    @State private var feed: [MomentLine] = []
    @State private var big: BigMoment?

    private var me: String { view.common.meId }
    private var mine: Bool { view.common.yourTurn }
    private var wide: Bool { hsize == .regular }
    private func name(_ id: String?) -> String {
        id == me ? "You" : view.players.first { $0.id == id }.map { RoomPlayer.stripBot($0.name) } ?? "Someone"
    }

    var body: some View {
        VStack(spacing: 0) {
            TableTopBar(game: room.game, code: room.code, line: topLine, onLeave: onLeave, owner: room.isOwner, room: room)
            if view.common.phase == "done" {
                GameOver(room: room, players: view.players, winners: view.common.winners ?? [], me: me, reason: endReason, detail: bonusLine)
            } else {
                ScoreStrip(players: view.players, turn: view.turn?.id, owner: view.common.owner, me: me, compact: true)
                    .padding(.vertical, 4)
                VStack(spacing: 1) {
                    Text(turnLine).font(.subheadline.weight(.semibold)).foregroundStyle(T2P.text).multilineTextAlignment(.center)
                        .lineLimit(2).minimumScaleFactor(0.85).accessibilityIdentifier("rollcall-turn")
                    if let n = upNext { Text("Up next: \(n)").font(.caption).foregroundStyle(T2P.muted) }
                }
                .padding(.horizontal, 16)
                MomentFeed(lines: Array(feed.prefix(1)), id: "rollcall-last").padding(.top, 2)
                // on an iPad the card stops growing (rows about 75 points), centered above the dice
                scorecard
                    .padding(.horizontal, 10).padding(.top, 6)
                    .frame(maxWidth: 760, maxHeight: wide ? CGFloat(660) : CGFloat.infinity).frame(maxWidth: .infinity)
                    .frame(maxHeight: .infinity)
                tray
                    .padding(.horizontal, 10).padding(.top, 8)
                    .frame(maxWidth: 760).frame(maxWidth: .infinity)
                ReactionBar(room: room)
            }
        }
        .overlay { if let b = big { BigMomentCard(m: b).transition(still ? AnyTransition.opacity : AnyTransition.scale.combined(with: .opacity)) } }
        .onChange(of: view) { old, new in changed(from: old, to: new) }
        .onChange(of: mine) { _, m in if m { Haptics.yourTurn() } }
        .onAppear {
            seen = view.rollKey; appeared = true
            // a table opened mid-game: the last box scored, so the screen doesn't start blank
            if feed.isEmpty, let l = view.last { feed = [MomentLine(text: scoredWords(l.id, l.key, l.points, l.extra), dice: l.dice)] }
        }
        .onChange(of: view.rollKey) { _, key in
            guard let key, key != seen else { return }
            seen = key
            // Reduce Motion: no tumble; the new faces fade in (die(_:)). The dice's sound comes from the room (Feel).
            if still { if mine { Haptics.play() }; return }
            tumbling = key
            tumbleStart = Date()
            if YachtTumble.frozenAt != nil { return }   // a screenshot stopped mid-tumble
            let dur = YachtTumble.duration(mine: mine)
            if mine {
                // a light tick as the dice turn over, then the landing's tap and sound
                for f in [0.3, 0.58] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + dur * f) { if tumbling == key { Haptics.select() } }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + dur) {
                if tumbling == key { tumbling = nil; Feel.landed(mine: mine) }
            }
        }
    }

    // MARK: what just happened (#489)

    private func changed(from old: RollCall.View, to new: RollCall.View) {
        if old.common.phase != "playing" && new.common.phase == "playing" { feed = []; big = nil }   // a new game
        let moments = RollCall.moments(from: old, to: new)
        // a bonus first, then the box it came with, so the newest line is the box and its dice
        for m in moments { if case let .upperBonus(who, points) = m { MomentFeed.add("\(name(who)) earned the upper bonus: +\(points)", to: &feed, still: still) } }
        for m in moments {
            guard case let .scored(who, box, points, extra, dice) = m else { continue }
            MomentFeed.add(scoredWords(who, box, points, extra), dice: dice, to: &feed, still: still)
        }
        if let f = flash(moments) { BigMomentCard.show(f, in: $big, still: still) }
    }

    private func scoredWords(_ who: String, _ box: String, _ points: Int, _ extra: Int) -> String {
        "\(name(who)) scored \(points) in \(RollCall.boxName(box))" + (extra > 0 ? ", +\(extra) for another Yacht" : "")
    }

    /// A Yacht (five of a kind) and the upper bonus, said big for a moment.
    private func flash(_ moments: [RollCall.Moment]) -> BigMoment? {
        for m in moments {
            if case let .scored(who, box, points, extra, _) = m, extra > 0 || (box == "five" && points > 0) {
                if who == me { Haptics.yourTurn() }
                return BigMoment(icon: "star.circle.fill", word: extra > 0 ? "Yacht again!" : "Yacht!",
                                 detail: "\(name(who)): five of a kind, +\(points + extra)")
            }
        }
        for m in moments {
            if case let .upperBonus(who, points) = m {
                return BigMoment(icon: "star.fill", word: "Upper bonus +\(points)", detail: "\(name(who)) reached \(RollCall.upperBonusAt) in Ones to Sixes")
            }
        }
        return nil
    }

    private var upNext: String? {
        guard let t = view.turn else { return nil }
        let order = view.players.filter { $0.seated && !$0.left }
        guard order.count > 1, let i = order.firstIndex(where: { $0.id == t.id }) else { return nil }
        let id = order[(i + 1) % order.count].id
        return id == me ? "you" : name(id)
    }

    private var endReason: String {
        view.quick ? "All \(view.rounds) rounds of the quick game are played." : "All \(view.rounds) rounds are played: every box is filled."
    }

    /// Under a name on the winner screen: the bonuses in their total.
    private func bonusLine(_ p: ScorePlayer) -> String? {
        let b = view.bonus(p)
        let parts = [b > 0 ? "upper bonus +\(b)" : nil, p.extra > 0 ? "Yacht bonus +\(p.extra)" : nil].compactMap { $0 }
        return parts.isEmpty ? nil : "Includes " + parts.joined(separator: " and ")
    }

    private var topLine: String {
        if view.common.phase == "done" { return "GAME OVER" }
        return "ROUND \(view.round) OF \(view.rounds)"
    }

    private var turnLine: String {
        guard let t = view.turn else { return "" }
        if view.common.held { return "A bot is playing your seat" }
        if rolling { return mine ? "Rolling…" : "\(name(t.id)) is rolling…" }
        if mine { return t.rolls == 0 ? "Your turn: roll the dice" : t.rolls < RollCall.maxRolls ? "Your turn · roll \(t.rolls) of 3 · hold, roll or score" : "Your turn: pick a box" }
        return t.rolls == 0 ? "\(name(t.id))’s turn" : "\(name(t.id))’s turn · roll \(t.rolls) of 3"
    }

    /// The dice are in the air: each tumbling in its own place. A roll that has just arrived counts from the start,
    /// so its faces never show for a frame before the tumble.
    private var rolling: Bool { tumbling != nil || arriving }
    private var arriving: Bool { appeared && !still && view.rollKey != nil && view.rollKey != seen }

    private var canHold: Bool { mine && (view.turn?.rolls ?? 0) > 0 && (view.turn?.rolls ?? 0) < RollCall.maxRolls && !rolling }

    // MARK: the dice

    /// The bottom of the screen: the five dice locked in one row on the felt, Roll under them.
    private var tray: some View {
        VStack(spacing: 8) {
            diceRow.padding(.top, 16)
            if mine { rollButton.padding(.horizontal, 14) }
        }
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(YachtFeltPanel(corner: 18))
    }

    private var diceRow: some View {
        let size: CGFloat = wide ? 92 : 56
        return HStack(spacing: wide ? 26 : 10) {
            ForEach(0..<5, id: \.self) { i in die(i, size) }
        }
    }

    /// One die in its place: still, tumbling, or held (glowing, HOLD under it). Tap to hold or let go.
    private func die(_ i: Int, _ size: CGFloat) -> some View {
        let t = view.turn
        let shown = view.diceShown
        let held = shown && (t.map { i < $0.held.count && $0.held[i] } ?? false)
        let face: Int? = shown ? t.flatMap { i < $0.dice.count ? $0.dice[i] : nil } : nil
        let air = rolling && !held
        // a die that isn't held is a new view with each roll (so it settles, or with Reduce Motion fades in); a held
        // die keeps its view while its face stays
        let key = held ? "\(i)-held-\(face ?? 0)" : "\(i)-\(view.rollKey ?? "unrolled")"
        return Button { if canHold { room.move("hold", ["die": .number(Double(i))]); Feel.kept() } } label: {
            VStack(spacing: 6) {
                ZStack {
                    if air {
                        YachtTumble(size: size, seed: i, start: tumbleStart, duration: YachtTumble.duration(mine: mine))
                    } else {
                        YachtDie(value: face, size: size, held: held)
                            .opacity(shown ? 1 : 0.6)
                            .modifier(YachtSettle(on: shown && !held))
                            .id(key)
                            .transition(.opacity)
                    }
                }
                .frame(width: size, height: size)
                .animation(still ? Animation.easeOut(duration: 0.2) : nil, value: key)
                HoldTag(on: held)
            }
            .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(DieButtonStyle()).disabled(!canHold)
        .accessibilityLabel(air ? "Die, rolling" : face.map { "Die showing \($0)" } ?? "Die, not rolled yet")
        .accessibilityValue(held ? "held" : "")
        .accessibilityIdentifier("rc-die-\(i)")
    }

    private var rollButton: some View {
        let rolls = view.turn?.rolls ?? 0
        let allHeld = view.turn?.held.allSatisfy { $0 } ?? false
        return Button { room.move("roll"); Haptics.play() } label: {
            Text(rolls == 0 ? "Roll" : rolls >= RollCall.maxRolls ? "Pick a box to score" : "Roll again (\(RollCall.maxRolls - rolls) left)")
        }
        .buttonStyle(PaintedButtonStyle(kind: .gold))
        .disabled(rolls >= RollCall.maxRolls || (rolls > 0 && allHeld) || view.common.held || rolling)
        .accessibilityIdentifier("rc-roll")
    }

    // MARK: the scorecard

    /// Your scorecard: Upper and Lower side by side, each box showing what this roll would score there (tap one to
    /// take it), your filled boxes in gold, and the bonus's progress and the totals at the foot.
    private var scorecard: some View {
        let p = view.me
        let allowed = Set(mine && !rolling ? view.options?.allowed ?? [] : [])
        let upper = Array(RollCall.boxes.prefix(6)), lower = Array(RollCall.boxes.dropFirst(6))
        let upperSum = upper.compactMap { p?.scores[$0.key] }.reduce(0, +)
        let lowerSum = lower.compactMap { p?.scores[$0.key] }.reduce(0, +)
        let bonus = p.map { view.bonus($0) } ?? 0
        let tip: String? = {
            guard let o = view.options, mine, !rolling, !o.instruction.isEmpty, o.instruction != "Choose one open box" else { return nil }
            return o.instruction
        }()
        return VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(p.map { RoomPlayer.stripBot($0.name) } ?? "You").font(Painted.display(wide ? 22 : 18, .bold))
                    .foregroundStyle(Painted.titleGold).lineLimit(1)
                Spacer()
                Text(tip ?? (allowed.isEmpty ? "Your scorecard" : "Tap a box to score")).font(.caption.weight(.semibold))
                    .foregroundStyle(allowed.isEmpty ? Painted.paperDim : Painted.goldLight)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 14).padding(.top, 9).padding(.bottom, 2)
            GeometryReader { g in
                let rowH = max(30, (g.size.height - 24) / 7)
                ScrollView(showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(spacing: 0) {
                            colHead("UPPER")
                            ForEach(upper, id: \.key) { b in row(b.key, b.name, p?.scores[b.key], allowed, rowH) }
                            bonusBox(bonus, rowH)
                        }
                        VStack(spacing: 0) {
                            colHead("LOWER")
                            ForEach(lower, id: \.key) { b in row(b.key, b.name, p?.scores[b.key], allowed, rowH) }
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            footer(upperSum: upperSum, lowerSum: lowerSum, bonus: bonus, total: p?.score ?? 0, upperDone: upper.allSatisfy { p?.scores[$0.key] != nil })
        }
        .background(YachtFeltPanel(corner: 16))
    }

    private func colHead(_ t: String) -> some View {
        Text(t).font(.caption2.weight(.heavy)).tracking(1.5).foregroundStyle(Painted.gold.opacity(0.9))
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6).frame(height: 24)
            .accessibilityHidden(true)
    }

    private var boxWidth: CGFloat { wide ? 84 : 50 }
    private var rowFont: Font { wide ? Font.title3.weight(.semibold) : Font.callout.weight(.semibold) }
    /// A box's height in a row this tall: most of the row, never a tall slab on an iPad.
    private func boxHeight(_ h: CGFloat) -> CGFloat { wide ? min(56, h - 12) : max(24, h - 6) }
    private var boxFont: Font { Painted.display(wide ? 22 : 17, .bold).monospacedDigit() }

    /// One box: open and takeable this roll (a gold plaque with its points), filled (gold on the felt), or open.
    @ViewBuilder private func row(_ key: String, _ name: String, _ filled: Int?, _ allowed: Set<String>, _ h: CGFloat) -> some View {
        let open = filled == nil && allowed.contains(key)
        let pts = view.options?.scores[key] ?? 0
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Group {
            if open {
                Button { room.move("score", ["key": .string(key)]); Haptics.play() } label: {
                    HStack(spacing: 6) {
                        Text(name).font(rowFont).foregroundStyle(Painted.paper).lineLimit(1).minimumScaleFactor(0.7)
                        Spacer(minLength: 2)
                        Text("\(pts)").font(boxFont)
                            .foregroundStyle(pts > 0 ? Color(hex: 0x2A1A05) : Painted.goldLight)
                            .frame(width: boxWidth, height: boxHeight(h))
                            .background(shape.fill(pts > 0 ? AnyShapeStyle(YachtFeltPanel.goldFill) : AnyShapeStyle(Color.white.opacity(0.07))))
                            .overlay(shape.strokeBorder(Painted.rim, lineWidth: 1.5))
                            .shadow(color: Painted.gold.opacity(pts > 0 ? 0.55 : 0.15), radius: 6)
                    }
                    .padding(.horizontal, 6).frame(height: h).contentShape(Rectangle())
                }
                .buttonStyle(ScoreBoxStyle())
                .accessibilityLabel("Score \(pts) in \(name)")
                .accessibilityIdentifier("box-\(key)")
            } else {
                HStack(spacing: 6) {
                    Text(name).font(rowFont).foregroundStyle(filled == nil ? Painted.paperDim : Painted.paper)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 2)
                    Text(filled.map { "\($0)" } ?? "").font(boxFont).foregroundStyle(Painted.titleGold)
                        .frame(width: boxWidth, height: boxHeight(h))
                        .background(shape.fill(Color.black.opacity(0.28)))
                        .overlay(shape.strokeBorder(Painted.gold.opacity(filled == nil ? 0.2 : 0.45), lineWidth: 1))
                }
                .padding(.horizontal, 6).frame(height: h)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(name): \(filled.map { "\($0)" } ?? "open")")
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Painted.gold.opacity(0.12)).frame(height: 1) }
    }

    /// The upper bonus's own box, under Sixes: 35 once it's earned.
    private func bonusBox(_ bonus: Int, _ h: CGFloat) -> some View {
        HStack(spacing: 6) {
            Text("Bonus").font(rowFont.italic()).foregroundStyle(bonus > 0 ? Painted.paper : Painted.paperDim)
            Spacer(minLength: 2)
            Text(bonus > 0 ? "\(bonus)" : "").font(boxFont).foregroundStyle(Painted.titleGold)
                .frame(width: boxWidth, height: boxHeight(h))
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.18)))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Painted.gold.opacity(bonus > 0 ? 0.45 : 0.15), style: StrokeStyle(lineWidth: 1, dash: bonus > 0 ? [] : [3, 3])))
        }
        .padding(.horizontal, 6).frame(height: h)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bonus > 0 ? "Upper bonus: \(bonus)" : "Upper bonus: not yet")
    }

    /// The foot of the card: the upper bonus's progress ("15 so far, need 63"), then Upper, Lower and the total.
    private func footer(upperSum: Int, lowerSum: Int, bonus: Int, total: Int, upperDone: Bool) -> some View {
        let need = RollCall.upperBonusAt
        let progress = bonus > 0 ? "Upper bonus earned: +\(bonus)"
            : upperDone ? "No upper bonus: \(upperSum) of \(need)"
            : "Upper bonus: \(upperSum) so far, need \(need)"
        return VStack(spacing: 5) {
            HStack(spacing: 10) {
                Text(progress).font(.caption.weight(.semibold)).foregroundStyle(bonus > 0 ? Painted.goldLight : Painted.paperDim)
                    .lineLimit(1).minimumScaleFactor(0.75)
                    .accessibilityIdentifier("rc-bonus-progress")
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.black.opacity(0.4))
                        Capsule().fill(Painted.rim).frame(width: g.size.width * CGFloat(min(1, Double(upperSum) / Double(need))))
                    }
                }
                .frame(height: 6)
                .accessibilityHidden(true)
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                subtotal("UPPER", upperSum + bonus)
                subtotal("LOWER", lowerSum)
                Spacer(minLength: 4)
                Text("TOTAL").font(.caption.weight(.heavy)).tracking(2).foregroundStyle(Painted.gold)
                Text("\(total)").font(Painted.display(wide ? 32 : 26, .bold).monospacedDigit()).foregroundStyle(Painted.goldHi)
            }
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, 14).padding(.top, 7).padding(.bottom, 8)
        .background(Color.black.opacity(0.22))
        .overlay(alignment: .top) { Rectangle().fill(Painted.gold.opacity(0.35)).frame(height: 1) }
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16, style: .continuous))
    }

    private func subtotal(_ label: String, _ value: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label).font(.caption2.weight(.heavy)).tracking(1.2).foregroundStyle(Painted.paperDim)
            Text("\(value)").font(Painted.display(wide ? 20 : 17, .bold).monospacedDigit()).foregroundStyle(Painted.paper)
        }
    }
}

// MARK: Yacht Dice's painted pieces (Nov 20)

/// The felt the scorecard and the dice sit on: deep green, lit from the top, in a gold frame.
struct YachtFeltPanel: View {
    var corner: CGFloat = 18
    static var goldFill: LinearGradient {
        LinearGradient(colors: [Color(hex: 0xF8DB94), Painted.gold, Color(hex: 0xB9832C)], startPoint: .top, endPoint: .bottom)
    }
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        ZStack {
            shape.fill(RadialGradient(colors: [Color(hex: 0x2C6B50), Color(hex: 0x1B4836), Color(hex: 0x0F2A1F)],
                                      center: .top, startRadius: 10, endRadius: 560))
            CardLines(opacity: 0.06).clipShape(shape)
            RoundedRectangle(cornerRadius: max(4, corner - 5), style: .continuous)
                .strokeBorder(Painted.gold.opacity(0.28), lineWidth: 0.75)
                .padding(5)
        }
        .overlay(shape.strokeBorder(Painted.rim, lineWidth: 2))
        .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
        .accessibilityHidden(true)
    }
}

/// A score box pressed: a little smaller and brighter.
struct ScoreBoxStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? 0.08 : 0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// #725 (Tyler, Nov 22: "The HOLD word is worse under the held dice. Make the bottom white and gold, and the border"):
/// a held die reads as lit, not darkened. No gunmetal or dark brown anywhere in the held gold (#724 had gunmetal).
enum HoldGold {
    /// -t2p-725-before: build 91's gunmetal look (#724), for the side-by-side still only.
    static let before = ProcessInfo.processInfo.arguments.contains("-t2p-725-before")
    /// The HOLD pill's own gold: a deeper, rich gold under the white letters, so they read (white on it is 3.7:1 at
    /// the top and 4.9:1 at the bottom; the soft dark shadow under the letters carries the rest).
    static let pillTop = Color(hex: 0xB07A24)
    static let pillBottom = Color(hex: 0x9A6519)
    static var rim: LinearGradient {
        before
            ? LinearGradient(colors: [Painted.goldLight, Painted.goldMid, Color(hex: 0x4A5058), Painted.gold, Painted.goldHi, Painted.goldMid],
                             startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(colors: [Painted.goldHi, Painted.goldLight, Painted.gold, Painted.goldLight, Painted.goldHi, Painted.gold],
                             startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// HOLD under a held die: a small gold plaque with white letters and a bright gold edge (room kept for it under
/// every die, so nothing moves).
struct HoldTag: View {
    let on: Bool
    var body: some View {
        if HoldGold.before {
            Text("HOLD").font(.system(size: 10, weight: .heavy)).tracking(1.2)
                .foregroundStyle(on ? Color(hex: 0x353A40) : Color.clear)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Capsule().fill(on ? AnyShapeStyle(HoldGold.rim) : AnyShapeStyle(Color.clear)))
                .accessibilityHidden(true)
        } else {
            Text("HOLD").font(.system(size: 10, weight: .heavy)).tracking(1.2)
                .foregroundStyle(on ? Color.white : Color.clear)
                .shadow(color: .black.opacity(on ? 0.55 : 0), radius: 1, y: 0.5)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background {
                    if on {
                        Capsule().fill(LinearGradient(colors: [HoldGold.pillTop, HoldGold.pillBottom], startPoint: .top, endPoint: .bottom))
                            .overlay(Capsule().strokeBorder(LinearGradient(colors: [Painted.goldHi, Painted.goldLight],
                                                                           startPoint: .top, endPoint: .bottom), lineWidth: 1))
                    }
                }
                .accessibilityHidden(true)
        }
    }
}

/// A painted die: an ivory body with a darker edge, its face lit from the top left, pips pressed into it (the 1 in
/// garnet, as the website's dice). Held: a gold ring and glow. No face yet: the cards' gold star, faint.
struct YachtDie: View {
    let value: Int?
    var size: CGFloat = 56
    var held = false

    var body: some View {
        let r = size * 0.21
        let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
        ZStack {
            shape.fill(LinearGradient(colors: [Color(hex: 0xF1E6CC), Color(hex: 0xC4AD82), Color(hex: 0x977D52)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: r * 0.8, style: .continuous)
                .fill(RadialGradient(colors: [Color(hex: 0xFFFEF8), Color(hex: 0xF6EDD8), Color(hex: 0xE3D3B1)],
                                     center: UnitPoint(x: 0.3, y: 0.25), startRadius: 0, endRadius: size * 0.95))
                .padding(size * 0.06)
                .offset(x: -size * 0.012, y: -size * 0.018)
            RoundedRectangle(cornerRadius: r * 0.8, style: .continuous)
                .stroke(Color.white.opacity(0.75), lineWidth: max(0.6, size * 0.014))
                .padding(size * 0.065)
                .offset(x: -size * 0.012, y: -size * 0.018)
                .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center))
            if let v = value {
                YachtPips(value: v, size: size).offset(x: -size * 0.012, y: -size * 0.018)
            } else {
                CardStar().fill(Painted.goldMid.opacity(0.5)).frame(width: size * 0.32, height: size * 0.32)
            }
        }
        .frame(width: size, height: size)
        .compositingGroup()
        .shadow(color: .black.opacity(0.5), radius: size * 0.05, x: size * 0.02, y: size * 0.06)
        .overlay {
            if held {
                RoundedRectangle(cornerRadius: r + 4, style: .continuous).strokeBorder(HoldGold.rim, lineWidth: 3).padding(-4)
                if !HoldGold.before {
                    // #725: a white highlight on the ring's inner edge, so the held die reads as lit
                    RoundedRectangle(cornerRadius: r + 2, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.85), lineWidth: 1).padding(-2)
                }
            }
        }
        .shadow(color: Painted.gold.opacity(held ? 0.8 : 0), radius: held ? 10 : 0)
    }
}

/// A die's pips, each a dark hollow with its lower edge catching the light.
struct YachtPips: View {
    let value: Int
    let size: CGFloat
    var body: some View {
        let spots: [(CGFloat, CGFloat)] = {
            let a: CGFloat = 0.27, b: CGFloat = 0.5, c: CGFloat = 0.73
            switch value {
            case 1: return [(b, b)]
            case 2: return [(a, a), (c, c)]
            case 3: return [(a, a), (b, b), (c, c)]
            case 4: return [(a, a), (c, a), (a, c), (c, c)]
            case 5: return [(a, a), (c, a), (b, b), (a, c), (c, c)]
            default: return [(a, a), (c, a), (a, b), (c, b), (a, c), (c, c)]
            }
        }()
        let d = size * (value == 1 ? 0.22 : 0.165)
        let colors = value == 1 ? [Color(hex: 0x5E100C), Color(hex: 0xB0302A)] : [Color(hex: 0x0B0705), Color(hex: 0x35271C)]
        return ZStack {
            ForEach(Array(spots.enumerated()), id: \.offset) { _, p in
                ZStack {
                    Circle().fill(RadialGradient(colors: colors, center: UnitPoint(x: 0.42, y: 0.36), startRadius: 0, endRadius: d * 0.62))
                    Circle().stroke(Color.white.opacity(0.6), lineWidth: max(0.5, d * 0.09))
                        .mask(LinearGradient(colors: [.clear, .white], startPoint: .center, endPoint: .bottom))
                }
                .frame(width: d, height: d)
                .position(x: p.0 * size, y: p.1 * size)
            }
        }
        .frame(width: size, height: size)
    }
}

/// A die tumbling in its own place: it hops a little, spins and turns over (a new face each turn), slowing, and comes
/// down flat. The screen swaps in the landed die when it's done.
struct YachtTumble: View {
    var size: CGFloat
    var seed: Int
    var start: Date
    var duration: Double
    /// Still mode (screenshots): the tumble stopped this far through (0 to 1).
    static var frozenAt: Double?
    static func duration(mine: Bool) -> Double { mine ? 0.75 : 0.6 }

    var body: some View {
        TimelineView(.animation) { ctx in
            let p = Self.frozenAt ?? min(1, max(0, ctx.date.timeIntervalSince(start) / max(0.1, duration)))
            let slow = 1 - pow(1 - p, 3)
            let dir: Double = seed % 2 == 0 ? 1 : -1
            let k = Int(p * 9)
            let h = (k &* 1_103_515_245 &+ (seed + 1) &* 12_345) & 0x7fff_ffff
            let hop = CGFloat(sin(p * .pi))
            YachtDie(value: 1 + h % 6, size: size)
                .rotation3DEffect(.degrees(sin(p * .pi * 4.5) * 55 * (1 - p)), axis: (x: 1, y: CGFloat(dir * 0.7), z: 0), perspective: 0.6)
                .rotationEffect(.degrees((1 - slow) * 420 * dir))
                .scaleEffect(1 + 0.12 * hop)
                .offset(y: -size * 0.11 * hop)
        }
        .accessibilityHidden(true)
    }
}

/// A die as it lands: a touch big, then down with a small bounce. Reduce Motion: it just appears.
struct YachtSettle: ViewModifier {
    var on: Bool
    @Environment(\.accessibilityReduceMotion) private var still
    @State private var down = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(on && !still && !down ? 1.1 : 1)
            .onAppear {
                guard on && !still else { return }
                withAnimation(.spring(duration: 0.3, bounce: 0.5)) { down = true }
            }
    }
}

/// The website's Roll Call notepad and tray colors (src/live/rollcall's game page: paper, pen, pencil, felt, wood).
enum RCPaper {
    static let paper = Color(hex: 0xF6F0DF)
    static let ink = Color(hex: 0x14243A)
    static let pen = Color(hex: 0x1D3A8A)
    static let pencil = Color(hex: 0x5F676D)
    static let rule = Color(hex: 0xB8C7D3)
    static let band = Color(hex: 0xA83A32)
    static let accent = Color(hex: 0x8A5A08)
    static let chip = Color(hex: 0xF2C14E).opacity(0.35)
    static let wood = Color(hex: 0x5A3A22)
    static let feltGradient = LinearGradient(colors: [Color(hex: 0x2B7357), Color(hex: 0x15412E)], startPoint: .top, endPoint: .bottom)
    static func colHead(_ t: String) -> some View {
        Text(t).font(.caption2.weight(.heavy)).tracking(1.5).foregroundStyle(pencil)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8).frame(height: 24)
            .accessibilityHidden(true)
    }
}

// Close Enough moved to CloseEnoughView.swift (#489).
