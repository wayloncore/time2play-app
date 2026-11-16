import SwiftUI
import T2PCore

/// Roll Call: five dice, three rolls, thirteen boxes; against Pip, Rosa and Viktor or friends. The room scores every box.
struct RollCallView: View {
    @ObservedObject var room: RoomModel
    let view: RollCall.View
    var onLeave: () -> Void

    private var me: String { view.common.meId }
    private var mine: Bool { view.common.yourTurn }
    private func name(_ id: String?) -> String {
        id == me ? "You" : view.players.first { $0.id == id }.map { RoomPlayer.stripBot($0.name) } ?? "Someone"
    }

    var body: some View {
        VStack(spacing: 0) {
            TableTopBar(game: room.game, code: room.code, line: topLine, onLeave: onLeave, owner: room.isOwner, room: room)
            if view.common.phase == "done" {
                GameOver(room: room, players: view.players, winners: view.common.winners ?? [], me: me)
            } else {
                ScoreStrip(players: view.players, turn: view.turn?.id, owner: view.common.owner, me: me)
                    .padding(.vertical, 8)
                ScrollView {
                    VStack(spacing: 16) {
                        Text(turnLine).font(.headline).foregroundStyle(T2P.text).accessibilityIdentifier("rollcall-turn")
                        if let l = view.lastLine { Text(l).font(.footnote).foregroundStyle(T2P.muted) }
                        dice
                        if mine { rollButton }
                        if let o = view.options, mine, !o.instruction.isEmpty, o.instruction != "Choose one open box" {
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
        .onChange(of: mine) { _, m in if m { Haptics.yourTurn() } }
    }

    private var topLine: String {
        if view.common.phase == "done" { return "GAME OVER" }
        return "ROUND \(view.round) OF \(view.rounds)"
    }

    private var turnLine: String {
        guard let t = view.turn else { return "" }
        if view.common.held { return "A bot is playing your seat" }
        if mine { return t.rolls == 0 ? "Your turn: roll the dice" : t.rolls < RollCall.maxRolls ? "Your turn · roll \(t.rolls) of 3: hold dice, roll again or pick a box" : "Your turn: pick a box" }
        return "\(name(t.id))’s turn"
    }

    @ViewBuilder private var dice: some View {
        if let t = view.turn {
            HStack(spacing: 10) {
                ForEach(0..<5, id: \.self) { i in
                    let held = i < t.held.count && t.held[i]
                    let canHold = mine && t.rolls > 0 && t.rolls < RollCall.maxRolls
                    Button { if canHold { room.move("hold", ["die": .number(Double(i))]); Haptics.select() } } label: {
                        VStack(spacing: 4) {
                            DieView(value: view.diceShown && i < t.dice.count ? t.dice[i] : nil, size: 56, held: held)
                            Text(held ? "HELD" : " ").font(.caption2.weight(.bold)).foregroundStyle(T2P.gold)
                        }
                    }
                    .buttonStyle(.plain).disabled(!canHold)
                    .accessibilityLabel(view.diceShown && i < t.dice.count ? "Die showing \(t.dice[i])" : "Die, not rolled yet")
                    .accessibilityValue(held ? "held" : "")
                    .accessibilityIdentifier("rc-die-\(i)")
                }
            }
        }
    }

    private var rollButton: some View {
        let rolls = view.turn?.rolls ?? 0
        let allHeld = view.turn?.held.allSatisfy { $0 } ?? false
        return Button { room.move("roll"); Haptics.play() } label: {
            Text(rolls == 0 ? "Roll" : "Roll again (\(RollCall.maxRolls - rolls) left)")
        }
        .buttonStyle(GoldButtonStyle())
        .disabled(rolls >= RollCall.maxRolls || (rolls > 0 && allHeld) || view.common.held)
        .accessibilityIdentifier("rc-roll")
    }

    private var scorecard: some View {
        let mePlayer = view.me
        let allowed = Set(mine ? view.options?.allowed ?? [] : [])
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
