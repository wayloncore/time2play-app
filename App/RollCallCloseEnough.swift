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
    @StateObject private var arenaStage = DiceArenaStage()
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
                ScoreStrip(players: view.players, turn: view.turn?.id, owner: view.common.owner, me: me)
                    .padding(.vertical, 8)
                ScrollView {
                    VStack(spacing: 16) {
                        VStack(spacing: 2) {
                            Text(turnLine).font(.headline).foregroundStyle(T2P.text).multilineTextAlignment(.center).accessibilityIdentifier("rollcall-turn")
                            if let n = upNext { Text("Up next: \(n)").font(.footnote).foregroundStyle(T2P.muted) }
                        }
                        MomentFeed(lines: feed, id: "rollcall-last")
                        dice
                        if mine { rollButton }
                        if let o = view.options, mine, !rolling, !o.instruction.isEmpty, o.instruction != "Choose one open box" {
                            Text(o.instruction).font(.subheadline.weight(.semibold)).foregroundStyle(T2P.gold)
                        }
                        scorecard
                    }
                    .padding(.horizontal, 20).padding(.bottom, 12)
                    .frame(maxWidth: 640).frame(maxWidth: .infinity)
                }
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

    @ViewBuilder private var dice: some View {
        if arena, let t = view.turn {
            DiceArenaView(stage: arenaStage, state: ArenaState.rollCall(view), button: { d in
                let i = d.id, held = i < t.held.count && t.held[i]
                return ArenaDieButton(id: "rc-die-\(i)",
                                      label: !view.diceShown ? "Die, not rolled yet" : rolling && !held ? "Die, rolling" : "Die showing \(i < t.dice.count ? t.dice[i] : 0)",
                                      value: held ? "held" : "", enabled: canHold)
            }, onTap: { i in
                if canHold { room.move("hold", ["die": .number(Double(i))]); Haptics.select() }
            })
            .frame(height: hsize == .regular ? 440 : 300)
            .frame(maxWidth: 760)
        } else if let t = view.turn {
            HStack(spacing: 10) {
                ForEach(0..<5, id: \.self) { i in
                    let held = i < t.held.count && t.held[i]
                    let canHold = mine && t.rolls > 0 && t.rolls < RollCall.maxRolls
                    let air = tumbling != nil && !held
                    Button { if canHold { room.move("hold", ["die": .number(Double(i))]); Haptics.select() } } label: {
                        VStack(spacing: 4) {
                            if air {
                                TumblingDie(size: 56, seed: i)
                            } else if held || !view.diceShown {
                                DieView(value: view.diceShown && i < t.dice.count ? t.dice[i] : nil, size: 56, held: held)
                            } else {
                                DieView(value: i < t.dice.count ? t.dice[i] : nil, size: 56).modifier(Landing())
                            }
                            Text(held ? "HELD" : " ").font(.caption2.weight(.bold)).foregroundStyle(T2P.gold)
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

    private var scorecard: some View {
        let mePlayer = view.me
        let allowed = Set(mine && !rolling ? view.options?.allowed ?? [] : [])
        return VStack(spacing: 0) {
            ForEach(Array(RollCall.boxes.enumerated()), id: \.offset) { i, b in
                let filled = mePlayer?.scores[b.key]
                HStack {
                    Text(b.name).foregroundStyle(T2P.text)
                    Spacer()
                    if let f = filled {
                        Text("\(f)").font(.body.monospacedDigit().weight(.semibold)).foregroundStyle(T2P.text)
                    } else if allowed.contains(b.key) {
                        Button("+\(view.options?.scores[b.key] ?? 0)") { room.move("score", ["key": .string(b.key)]); Haptics.play() }
                            .font(.body.monospacedDigit().weight(.bold)).foregroundStyle(T2P.ink)
                            .padding(.horizontal, 12).padding(.vertical, 4).background(T2P.gold, in: Capsule())
                            .accessibilityLabel("Score \(view.options?.scores[b.key] ?? 0) in \(b.name)")
                            .accessibilityIdentifier("box-\(b.key)")
                    } else {
                        Text("–").foregroundStyle(T2P.faint)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .accessibilityElement(children: filled == nil && allowed.contains(b.key) ? .contain : .combine)
                if i == 5 { Divider().overlay(T2P.line) }
            }
            HStack {
                Text("Total").font(.headline).foregroundStyle(T2P.text)
                Spacer()
                Text("\(mePlayer?.score ?? 0)").font(.headline.monospacedDigit()).foregroundStyle(T2P.text)
            }
            .padding(16)
        }
        .background(T2P.panel, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(T2P.line))
    }
}

// Close Enough moved to CloseEnoughView.swift (#489).
