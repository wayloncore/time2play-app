import SwiftUI
import T2PCore

/// Roll Call: five dice, three rolls, thirteen boxes; against Pip, Rosa and Viktor or friends. The room scores every box.
/// #488: every roll (yours, a friend's or a bot's) tumbles and lands before the boxes it can go in show.
/// #489: a line of what just happened (each box scored, with its dice, and a bonus earned), a Roll Call or a bonus
/// said big for a moment, who's up next, How to play, and the end of the game saying why it ended.
struct RollCallView: View {
    @ObservedObject var room: RoomModel
    @Environment(\.accessibilityReduceMotion) private var still
    let view: RollCall.View
    var onLeave: () -> Void
    /// #521: the 3D dice arena (You → "3D dice (preview)"); off draws the flat dice as before.
    var arena = false
    @StateObject private var arenaStage = DiceArenaStage(tray: .row)
    @Environment(\.horizontalSizeClass) private var hsize
    /// The roll in the air (its RollCall.View.rollKey), and the last roll seen, so a view arriving mid-turn doesn't tumble.
    @State private var tumbling: String?
    @State private var seen: String?
    @State private var feed: [MomentLine] = []
    @State private var big: BigMoment?

    private var me: String { view.common.meId }
    private var mine: Bool { view.common.yourTurn }
    private func name(_ id: String?) -> String {
        id == me ? "You" : view.players.first { $0.id == id }.map { RoomPlayer.stripBot($0.name) } ?? "Someone"
    }

    var body: some View {
        VStack(spacing: 0) {
            TableTopBar(game: room.game, code: room.code, line: topLine, onLeave: onLeave, owner: room.isOwner, room: room)
            if view.common.phase == "done" {
                GameOver(room: room, players: view.players, winners: view.common.winners ?? [], me: me, reason: endReason, detail: bonusLine)
            } else {
                // #523: laid out like the website's Roll Call: the scorecard fills the screen, the dice wait at the bottom
                // in five places that never move, the Roll button under them
                ScoreStrip(players: view.players, turn: view.turn?.id, owner: view.common.owner, me: me, compact: true)
                    .padding(.vertical, 4)
                VStack(spacing: 1) {
                    Text(turnLine).font(.subheadline.weight(.semibold)).foregroundStyle(T2P.text).multilineTextAlignment(.center)
                        .lineLimit(2).minimumScaleFactor(0.85).accessibilityIdentifier("rollcall-turn")
                    if let n = upNext { Text("Up next: \(n)").font(.caption).foregroundStyle(T2P.muted) }
                }
                .padding(.horizontal, 16)
                MomentFeed(lines: Array(feed.prefix(1)), id: "rollcall-last").padding(.top, 2)
                scorecard
                    .padding(.horizontal, 10).padding(.top, 6)
                    .frame(maxWidth: 760).frame(maxWidth: .infinity)
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
            arenaStage.onFirstHit = { Haptics.play() }
            seen = view.rollKey
            // a table opened mid-game: the last box scored, so the screen doesn't start blank
            if feed.isEmpty, let l = view.last { feed = [MomentLine(text: scoredWords(l.id, l.key, l.points, l.extra), dice: l.dice)] }
        }
        .onChange(of: view.rollKey) { _, key in
            guard let key, key != seen else { return }
            seen = key
            if arena { return }   // the 3D dice tap as they land
            if still { if mine { Haptics.play() }; return }
            tumbling = key
            DispatchQueue.main.asyncAfter(deadline: .now() + (mine ? 0.6 : 0.45)) {
                if tumbling == key { tumbling = nil; if mine { Haptics.play() } }
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
        "\(name(who)) scored \(points) in \(RollCall.boxName(box))" + (extra > 0 ? ", +\(extra) for another Roll Call" : "")
    }

    /// A Roll Call (five of a kind) and the upper bonus, said big for a moment.
    private func flash(_ moments: [RollCall.Moment]) -> BigMoment? {
        for m in moments {
            if case let .scored(who, box, points, extra, _) = m, extra > 0 || (box == "five" && points > 0) {
                if who == me { Haptics.yourTurn() }
                return BigMoment(icon: "star.circle.fill", word: extra > 0 ? "Roll Call again!" : "Roll Call!",
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
        let parts = [b > 0 ? "upper bonus +\(b)" : nil, p.extra > 0 ? "Roll Call bonus +\(p.extra)" : nil].compactMap { $0 }
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
        if mine { return t.rolls == 0 ? "Your turn: roll the dice" : t.rolls < RollCall.maxRolls ? "Your turn · roll \(t.rolls) of 3: hold dice, roll again or pick a box" : "Your turn: pick a box" }
        return t.rolls == 0 ? "\(name(t.id))’s turn" : "\(name(t.id))’s turn · roll \(t.rolls) of 3"
    }

    /// The dice are in the air: the flat dice's short tumble, or (#521) the 3D roll until every die has landed.
    private var rolling: Bool {
        if arena { return view.rollKey != nil && arenaStage.landed != view.rollKey }
        return tumbling != nil
    }

    private var canHold: Bool { mine && (view.turn?.rolls ?? 0) > 0 && (view.turn?.rolls ?? 0) < RollCall.maxRolls && !rolling }

    /// The bottom of the screen (#523): the five dice in their places (3D or flat) and the Roll button.
    @ViewBuilder private var tray: some View {
        if arena {
            VStack(spacing: 8) {
                dice
                if mine { rollButton }
            }
        } else {
            VStack(spacing: 10) {
                dice.padding(.top, 14)
                if mine { rollButton.padding(.horizontal, 12) }
            }
            .padding(.bottom, mine ? 12 : 14)
            .frame(maxWidth: .infinity)
            .background(RCPaper.feltGradient, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(RCPaper.wood, lineWidth: 6))
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }

    @ViewBuilder private var dice: some View {
        if arena, let t = view.turn {
            DiceArenaView(stage: arenaStage, state: ArenaState.rollCall(view), button: { d in
                let i = d.id, held = i < t.held.count && t.held[i]
                return ArenaDieButton(id: "rc-die-\(i)",
                                      label: !view.diceShown ? "Die, not rolled yet" : rolling && !held ? "Die, rolling" : "Die showing \(i < t.dice.count ? t.dice[i] : 0)",
                                      value: held ? "held" : "", enabled: canHold, tag: held && view.diceShown ? "HOLD" : nil)
            }, onTap: { i in
                if canHold { room.move("hold", ["die": .number(Double(i))]); Haptics.select() }
            })
            .frame(height: hsize == .regular ? 250 : 170)
        } else if let t = view.turn {
            let size: CGFloat = hsize == .regular ? 84 : 54
            HStack(spacing: hsize == .regular ? 24 : 12) {
                ForEach(0..<5, id: \.self) { i in
                    let held = i < t.held.count && t.held[i]
                    let canHold = mine && t.rolls > 0 && t.rolls < RollCall.maxRolls
                    let air = tumbling != nil && !held
                    Button { if canHold { room.move("hold", ["die": .number(Double(i))]); Haptics.select() } } label: {
                        VStack(spacing: 3) {
                            Text(held ? "HOLD" : " ").font(.caption2.weight(.heavy)).tracking(1).foregroundStyle(T2P.gold)
                            if air {
                                TumblingDie(size: size, seed: i)
                            } else if held || !view.diceShown {
                                DieView(value: view.diceShown && i < t.dice.count ? t.dice[i] : nil, size: size, held: held, blank: !view.diceShown)
                                    .opacity(view.diceShown ? 1 : 0.55)
                            } else {
                                DieView(value: i < t.dice.count ? t.dice[i] : nil, size: size).modifier(Landing())
                            }
                        }
                    }
                    .buttonStyle(DieButtonStyle()).disabled(!canHold || tumbling != nil)
                    .accessibilityLabel(air ? "Die, rolling" : view.diceShown && i < t.dice.count ? "Die showing \(t.dice[i])" : "Die, not rolled yet")
                    .accessibilityValue(held ? "held" : "")
                    .accessibilityIdentifier("rc-die-\(i)")
                }
            }
            .id(view.rollKey ?? "unrolled")
        }
    }

    private var rollButton: some View {
        let rolls = view.turn?.rolls ?? 0
        let allHeld = view.turn?.held.allSatisfy { $0 } ?? false
        return Button { room.move("roll"); Haptics.play() } label: {
            Text(rolls == 0 ? "Roll" : "Roll again (\(RollCall.maxRolls - rolls) left)")
        }
        .buttonStyle(GoldButtonStyle())
        .disabled(rolls >= RollCall.maxRolls || (rolls > 0 && allHeld) || view.common.held || rolling)
        .accessibilityIdentifier("rc-roll")
    }

    /// Your scorecard (#523), the website's notepad: Upper and Lower side by side, the boxes this roll can go in as
    /// "+points" chips, the upper bonus's progress, and the score at the foot.
    private var scorecard: some View {
        let mePlayer = view.me
        let allowed = Set(mine && !rolling ? view.options?.allowed ?? [] : [])
        let upper = Array(RollCall.boxes.prefix(6)), lower = Array(RollCall.boxes.dropFirst(6))
        let upperSum = upper.compactMap { mePlayer?.scores[$0.key] }.reduce(0, +)
        let bonus = mePlayer.map { view.bonus($0) } ?? 0
        let tip: String? = {
            guard let o = view.options, mine, !rolling, !o.instruction.isEmpty, o.instruction != "Choose one open box" else { return nil }
            return o.instruction
        }()
        return VStack(spacing: 0) {
            Rectangle().fill(RCPaper.band).frame(height: 10)
            HStack(alignment: .firstTextBaseline) {
                Text(mePlayer.map { RoomPlayer.stripBot($0.name) } ?? "You").font(.system(.title3, design: .serif).weight(.bold))
                    .foregroundStyle(RCPaper.ink).lineLimit(1)
                Spacer()
                Text(tip ?? "Your scorecard").font(.caption.weight(.semibold)).foregroundStyle(tip == nil ? RCPaper.pencil : RCPaper.accent)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 4)
            Rectangle().fill(RCPaper.ink).frame(height: 2).padding(.horizontal, 10)
            GeometryReader { g in
                let rowH = max(34, (g.size.height - 26) / 7)
                ScrollView(showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(spacing: 0) {
                            RCPaper.colHead("UPPER")
                            ForEach(upper, id: \.key) { b in box(b.key, b.name, mePlayer?.scores[b.key], allowed, rowH) }
                            HStack {
                                Text("Bonus (\(min(upperSum, RollCall.upperBonusAt))/\(RollCall.upperBonusAt))").font(.caption.weight(.semibold))
                                    .foregroundStyle(RCPaper.pencil)
                                Spacer()
                                Text(bonus > 0 ? "\(bonus)" : "–").font(.callout.monospacedDigit().weight(.bold))
                                    .foregroundStyle(bonus > 0 ? RCPaper.pen : RCPaper.pencil)
                            }
                            .padding(.horizontal, 8).frame(height: rowH)
                            .accessibilityElement(children: .combine)
                        }
                        VStack(spacing: 0) {
                            RCPaper.colHead("LOWER")
                            ForEach(lower, id: \.key) { b in box(b.key, b.name, mePlayer?.scores[b.key], allowed, rowH) }
                        }
                    }
                    .padding(.horizontal, 10)
                }
            }
            Rectangle().fill(RCPaper.ink).frame(height: 1).padding(.horizontal, 10)
            Rectangle().fill(RCPaper.ink).frame(height: 1).padding(.horizontal, 10).padding(.top, 2)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("SCORE").font(.caption.weight(.heavy)).tracking(2).foregroundStyle(RCPaper.pencil)
                Text("\(mePlayer?.score ?? 0)").font(.system(.title, design: .serif).weight(.bold).monospacedDigit()).foregroundStyle(RCPaper.ink)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
        .background(RCPaper.paper, in: RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
        .environment(\.colorScheme, .light)
    }

    /// One box on the scorecard: filled (in pen), a "+points" chip you can tap, or a dash.
    @ViewBuilder private func box(_ key: String, _ name: String, _ filled: Int?, _ allowed: Set<String>, _ h: CGFloat) -> some View {
        let open = filled == nil && allowed.contains(key)
        let pts = view.options?.scores[key] ?? 0
        Group {
            if open {
                Button { room.move("score", ["key": .string(key)]); Haptics.play() } label: {
                    HStack {
                        Text(name).font(.callout.weight(.semibold)).foregroundStyle(RCPaper.ink).lineLimit(1).minimumScaleFactor(0.75)
                        Spacer(minLength: 4)
                        Text("+\(pts)").font(.callout.monospacedDigit().weight(.bold)).foregroundStyle(RCPaper.ink)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(pts > 0 ? RCPaper.chip : .clear, in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(RCPaper.ink.opacity(0.75), lineWidth: 1.5))
                    }
                    .padding(.horizontal, 8).frame(height: h).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Score \(pts) in \(name)")
                .accessibilityIdentifier("box-\(key)")
            } else {
                HStack {
                    Text(name).font(.callout.weight(.semibold)).foregroundStyle(filled == nil ? RCPaper.ink.opacity(0.8) : RCPaper.ink)
                        .lineLimit(1).minimumScaleFactor(0.75)
                    Spacer(minLength: 4)
                    Text(filled.map { "\($0)" } ?? "–").font(.system(.title3, design: .serif).weight(.bold).monospacedDigit())
                        .foregroundStyle(filled == nil ? RCPaper.pencil.opacity(0.7) : RCPaper.pen)
                }
                .padding(.horizontal, 8).frame(height: h)
                .accessibilityElement(children: .combine)
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(RCPaper.rule).frame(height: 1) }
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
