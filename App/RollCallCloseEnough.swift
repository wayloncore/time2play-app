import SwiftUI
import T2PCore

/// Roll Call: five dice, three rolls, thirteen boxes; against Pip, Rosa and Viktor or friends. The room scores every box.
/// #488: every roll (yours, a friend's or a bot's) tumbles and lands before the boxes it can go in show.
struct RollCallView: View {
    @ObservedObject var room: RoomModel
    @Environment(\.accessibilityReduceMotion) private var still
    let view: RollCall.View
    var onLeave: () -> Void
    /// The roll in the air (its RollCall.View.rollKey), and the last roll seen, so a view arriving mid-turn doesn't tumble.
    @State private var tumbling: String?
    @State private var seen: String?

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
                        if let l = view.lastLine { lastScored(l) }
                        dice
                        if mine { rollButton }
                        if let o = view.options, mine, tumbling == nil, !o.instruction.isEmpty, o.instruction != "Choose one open box" {
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
        .onAppear { seen = view.rollKey }
        .onChange(of: view.rollKey) { _, key in
            guard let key, key != seen else { return }
            seen = key
            if still { if mine { Haptics.play() }; return }
            tumbling = key
            DispatchQueue.main.asyncAfter(deadline: .now() + (mine ? 0.6 : 0.45)) {
                if tumbling == key { tumbling = nil; if mine { Haptics.play() } }
            }
        }
    }

    /// Who scored what last, with the dice they scored it with (#488), so a bot's turn doesn't just vanish.
    private func lastScored(_ line: String) -> some View {
        HStack(spacing: 8) {
            Text(line).font(.footnote).foregroundStyle(T2P.muted)
            if !view.lastDice.isEmpty {
                HStack(spacing: 3) { ForEach(Array(view.lastDice.enumerated()), id: \.offset) { _, v in DieView(value: v, size: 20) } }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(view.lastDice.isEmpty ? line : "\(line), with \(view.lastDice.map(String.init).joined(separator: ", "))")
        .accessibilityIdentifier("rollcall-last")
    }

    private var topLine: String {
        if view.common.phase == "done" { return "GAME OVER" }
        return "ROUND \(view.round) OF \(view.rounds)"
    }

    private var turnLine: String {
        guard let t = view.turn else { return "" }
        if view.common.held { return "A bot is playing your seat" }
        if tumbling != nil { return mine ? "Rolling…" : "\(name(t.id)) is rolling…" }
        if mine { return t.rolls == 0 ? "Your turn: roll the dice" : t.rolls < RollCall.maxRolls ? "Your turn · roll \(t.rolls) of 3: hold dice, roll again or pick a box" : "Your turn: pick a box" }
        return "\(name(t.id))’s turn"
    }

    @ViewBuilder private var dice: some View {
        if let t = view.turn {
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
        .disabled(rolls >= RollCall.maxRolls || (rolls > 0 && allHeld) || view.common.held || tumbling != nil)
        .accessibilityIdentifier("rc-roll")
    }

    private var scorecard: some View {
        let mePlayer = view.me
        let allowed = Set(mine && tumbling == nil ? view.options?.allowed ?? [] : [])
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

/// Close Enough: every phone gives a range for each question at once; the tighter the range that holds the answer,
/// the more it scores. The room reveals and scores it.
struct CloseEnoughView: View {
    @ObservedObject var room: RoomModel
    let view: CloseEnough.View
    var onLeave: () -> Void
    @State private var lo: Double = 0
    @State private var hi: Double = 0
    @State private var forQuestion = 0

    private var me: String { view.common.meId }

    var body: some View {
        VStack(spacing: 0) {
            TableTopBar(game: room.game, code: room.code, line: topLine, onLeave: onLeave, owner: room.isOwner, room: room)
            if view.common.phase == "done" {
                GameOver(room: room, players: view.players, winners: view.common.winners ?? [], me: me) { p in "\(p.score) · \(p.hits) of \(p.hits + p.misses)" }
            } else if let q = view.question {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Question \(q.n) of \(q.of)").font(.subheadline.weight(.semibold)).foregroundStyle(T2P.muted)
                            Spacer()
                            if let e = q.endsAt { Countdown(endsAt: e) }
                        }
                        Text(q.q).font(.title2.bold()).foregroundStyle(T2P.text).accessibilityIdentifier("ce-question")
                        if !q.note.isEmpty { Text(q.note).foregroundStyle(T2P.muted) }
                        ScaleBar(q: q, lo: view.lockedIn ? view.answerLo ?? lo : lo, hi: view.lockedIn ? view.answerHi ?? hi : hi)
                        if q.stage == "ask" { ask(q) } else { reveal(q) }
                        standings(q)
                    }
                    .padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
                }
                ReactionBar(room: room)
                    .onAppear { prepare(q) }
                    .onChange(of: q.n) { _, _ in prepare(q) }
            }
        }
    }

    private var topLine: String { view.common.phase == "done" ? "GAME OVER" : "\(view.me?.score ?? 0) POINTS" }

    private func prepare(_ q: CloseEnough.Question) {
        guard forQuestion != q.n else { return }
        forQuestion = q.n
        let span = q.ceiling - q.floor
        lo = q.snap(q.floor + span * 0.25); hi = q.snap(q.floor + span * 0.75)
    }

    @ViewBuilder private func ask(_ q: CloseEnough.Question) -> some View {
        if view.lockedIn {
            let waiting = view.players.filter { !$0.lockedIn && !$0.left && $0.id != me }.map { RoomPlayer.stripBot($0.name) }
            Label("Locked in: \(q.formatRange(view.answerLo ?? 0, view.answerHi ?? 0))", systemImage: "lock.fill")
                .font(.headline).foregroundStyle(T2P.text)
            if !waiting.isEmpty { Text("Waiting for \(waiting.joined(separator: ", ")).").foregroundStyle(T2P.muted) }
        } else if view.common.seated {
            VStack(alignment: .leading, spacing: 12) {
                slider("Low", value: $lo, q: q) { if hi < $0 { hi = $0 } }
                slider("High", value: $hi, q: q) { if lo > $0 { lo = $0 } }
                Text("From \(q.format(lo)) to \(q.format(hi)) · worth \(q.worth(lo: lo, hi: hi, maxPoints: view.maxPoints)) points if it holds the answer")
                    .font(.subheadline).foregroundStyle(T2P.muted)
                Button("Lock in this range") { room.move("range", ["lo": .number(lo), "hi": .number(hi)]); Haptics.play() }
                    .buttonStyle(GoldButtonStyle()).accessibilityIdentifier("lock-in")
            }
        } else {
            Text("You’ll play in the next game.").foregroundStyle(T2P.muted)
        }
    }

    private func slider(_ label: String, value: Binding<Double>, q: CloseEnough.Question, then: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(label).font(.headline).foregroundStyle(T2P.text); Spacer(); Text(q.format(value.wrappedValue)).font(.headline.monospacedDigit()).foregroundStyle(T2P.gold) }
            Slider(value: Binding(get: { value.wrappedValue }, set: { value.wrappedValue = q.snap($0); then(value.wrappedValue) }),
                   in: q.floor...max(q.ceiling, q.floor + 1), step: q.step > 0 ? q.step : 1)
                .tint(T2P.gold)
                .accessibilityLabel(label)
                .accessibilityValue(q.format(value.wrappedValue))
            .accessibilityIdentifier("ce-\(label.lowercased())")
        }
    }

    @ViewBuilder private func reveal(_ q: CloseEnough.Question) -> some View {
        let r = q.results[me]
        VStack(alignment: .leading, spacing: 8) {
            Text("The answer: \(q.answer.map { q.format($0) } ?? "")").font(.title2.bold()).foregroundStyle(T2P.text)
                .accessibilityIdentifier("ce-answer")
            if let r {
                let title = ["tight": "Tight, and right.", "hit": "Inside, comfortably.", "miss": "Outside the range."][r.verdict] ?? "No range locked in."
                Text("\(title) +\(r.points)").font(.headline).foregroundStyle(r.points > 0 ? T2P.good : T2P.ember)
            }
            if let why = q.why, !why.isEmpty { Text("Why: \(why)").foregroundStyle(T2P.muted) }
            if room.isOwner {
                Button(q.n < q.of ? "Next question" : "See the standings") { room.move("next") }.buttonStyle(GoldButtonStyle())
                    .accessibilityIdentifier("ce-next")
            }
        }
    }

    private func standings(_ q: CloseEnough.Question) -> some View {
        VStack(spacing: 0) {
            ForEach(view.players.filter { !$0.left }.sorted { $0.score > $1.score }) { p in
                HStack(spacing: 10) {
                    FaceView(face: p.face, size: 32)
                    Text(p.id == me ? "You" : RoomPlayer.stripBot(p.name)).foregroundStyle(T2P.text)
                    if q.stage == "ask" && p.lockedIn { Image(systemName: "checkmark.circle.fill").foregroundStyle(T2P.good).accessibilityLabel("locked in") }
                    Spacer()
                    if q.stage == "reveal", let r = q.results[p.id], let a = r.lo, let b = r.hi {
                        Text(q.formatRange(a, b)).font(.caption).foregroundStyle(T2P.muted)
                    }
                    Text("\(p.score)").font(.headline.monospacedDigit()).foregroundStyle(T2P.text)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .accessibilityElement(children: .combine)
            }
        }
        .background(T2P.panel, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Where the range sits on the question's scale, and the answer at the reveal.
struct ScaleBar: View {
    let q: CloseEnough.Question
    let lo: Double; let hi: Double
    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { g in
                let span = max(1, q.ceiling - q.floor)
                let x = { (v: Double) in CGFloat((v - q.floor) / span) * g.size.width }
                ZStack(alignment: .leading) {
                    Capsule().fill(T2P.panelHi).frame(height: 14)
                    Capsule().fill(T2P.gold.opacity(0.8)).frame(width: max(6, x(hi) - x(lo)), height: 14).offset(x: x(lo))
                    if let a = q.answer, q.stage == "reveal" {
                        Rectangle().fill(T2P.text).frame(width: 3, height: 30).offset(x: x(a) - 1.5)
                    }
                }
                .frame(height: 30)
            }
            .frame(height: 30)
            HStack { Text(q.format(q.floor)); Spacer(); Text(q.format(q.ceiling)) }.font(.caption).foregroundStyle(T2P.muted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Scale from \(q.format(q.floor)) to \(q.format(q.ceiling))\(q.answer.map { ", the answer \(q.format($0))" } ?? "")")
    }
}

struct Countdown: View {
    let endsAt: Double
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let left = max(0, Int((endsAt / 1000 - ctx.date.timeIntervalSince1970).rounded(.up)))
            Text(String(format: "%d:%02d", left / 60, left % 60)).font(.headline.monospacedDigit())
                .foregroundStyle(left <= 10 ? T2P.ember : T2P.text)
                .accessibilityLabel("\(left) seconds left")
        }
    }
}
