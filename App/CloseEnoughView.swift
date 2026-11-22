import SwiftUI
import T2PCore

/// Close Enough: every phone gives a range for each question at once; the tighter the range that holds the answer,
/// the more it scores. The room reveals and scores it.
/// #489: each moment shown, as the website's phone and TV pages do: who has locked in as it happens, why the question
/// ended, the answer landing on everyone's ranges with their points, the scores moving, what comes next and when,
/// and a winner screen with Play again and Back to Library.
struct CloseEnoughView: View {
    @ObservedObject var room: RoomModel
    let view: CloseEnough.View
    var onLeave: () -> Void
    @State private var lo: Double = 0
    @State private var hi: Double = 0
    @State private var forQuestion = 0
    @State private var lockLines: [String] = []
    @State private var landed = true          // the answer's marker has dropped onto the scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// #726: the Library game's brass look, unless You → "3D Close Enough board" is on (then #535's 3D board)
    @AppStorage(Boards3D.closeEnough3DKey) private var threeD = false
    private var board3D: Bool { Boards3D.playerCloseEnough3D(on: threeD) }

    private var me: String { view.common.meId }
    private func name(_ p: ScorePlayer) -> String { p.id == me ? "You" : RoomPlayer.stripBot(p.name) }
    private var lockedIds: Set<String> { Set(view.players.filter { $0.lockedIn }.map(\.id)) }

    var body: some View {
        if board3D { boardLook } else { webLook }
    }

    /// #726: the Library game's brass screens (CloseEnoughBrass.swift; #707's copy of time2play.live's page before it),
    /// with this view's state and moments (haptics, the answer landing, VoiceOver's announcement) kept.
    @ViewBuilder private var webLook: some View {
        ZStack {
            Brass.background
            if view.common.phase == "done" {
                CloseEnoughBrassOver(room: room, view: view, onLeave: onLeave)
            } else if let q = view.question {
                CloseEnoughBrassGame(room: room, view: view, q: q, onLeave: onLeave, lo: $lo, hi: $hi, landed: landed)
                    .onAppear { prepare(q) }
                    .onChange(of: q.n) { _, _ in prepare(q) }
                    .onChange(of: q.stage) { _, stage in if stage == "reveal" { revealed(q) } }
            }
        }
        .environment(\.colorScheme, .dark)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .overlay(alignment: .topLeading) {
            // for UI tests: the Library's brass look is on (#726; the id is #707's)
            Text("brass").font(.system(size: 2)).opacity(0.02).accessibilityIdentifier("ce-web").allowsHitTesting(false)
        }
    }

    private var boardLook: some View {
        VStack(spacing: 0) {
            TableTopBar(game: room.game, code: room.code, line: topLine, onLeave: onLeave, owner: room.isOwner, room: room)
            if view.common.phase == "done" {
                CloseEnoughOver(room: room, view: view)
            } else if let q = view.question {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Question \(q.n) of \(q.of)").font(.subheadline.weight(.semibold)).foregroundStyle(T2P.muted)
                                .accessibilityIdentifier("ce-number")
                            Spacer()
                            if q.stage == "ask", let e = q.endsAt { Countdown(endsAt: e) }
                        }
                        Group {
                            Text(q.q).font(.title2.bold()).foregroundStyle(T2P.text).accessibilityIdentifier("ce-question")
                            if !q.note.isEmpty { Text(q.note).foregroundStyle(T2P.muted) }
                        }
                        .id(q.n)
                        .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.move(edge: .trailing).combined(with: .opacity))
                        if q.stage == "ask" {
                            if board3D {
                                CloseEnoughBoard3D(state: .make(q: q, players: view.players, me: me, lo: view.lockedIn ? view.answerLo ?? lo : lo,
                                                                hi: view.lockedIn ? view.answerHi ?? hi : hi, seated: view.common.seated))
                                    .accessibilityIdentifier("ce-board3d")
                            } else {
                                ScaleBar(q: q, lo: view.lockedIn ? view.answerLo ?? lo : lo, hi: view.lockedIn ? view.answerHi ?? hi : hi)
                            }
                            ask(q)
                            lockedIn(q)
                        } else {
                            reveal(q)
                        }
                        standings(q)
                    }
                    .padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
                    .animation(reduceMotion ? nil : Animation.spring(duration: 0.4), value: q.n)
                }
                ReactionBar(room: room)
                    .onAppear { prepare(q) }
                    .onChange(of: q.n) { _, _ in prepare(q) }
                    .onChange(of: q.stage) { _, stage in if stage == "reveal" { revealed(q) } }
                    .onChange(of: lockedIds) { old, new in lockedChanged(old, new) }
            }
        }
    }

    private var topLine: String { view.common.phase == "done" ? "GAME OVER" : "\(view.me?.score ?? 0) POINTS" }

    private func prepare(_ q: CloseEnough.Question) {
        guard forQuestion != q.n else { return }
        forQuestion = q.n
        let span = q.ceiling - q.floor
        lo = q.snap(q.floor + span * 0.25); hi = q.snap(q.floor + span * 0.75)
        lockLines = []
        landed = q.stage == "reveal"
        if q.n > 1 { Haptics.select() }
    }

    /// Someone locked in: a line for it, so a bot's answer is seen landing, not just a tick appearing.
    private func lockedChanged(_ old: Set<String>, _ new: Set<String>) {
        let fresh = view.players.filter { new.contains($0.id) && !old.contains($0.id) && $0.id != me }
        guard !fresh.isEmpty, view.question?.stage == "ask" else { return }
        withAnimation(reduceMotion ? nil : Animation.easeOut(duration: 0.25)) {
            for p in fresh { lockLines.insert("\(name(p)) locked in", at: 0) }
            if lockLines.count > 3 { lockLines.removeLast(lockLines.count - 3) }
        }
    }

    /// The answer is out: it drops onto the scale, and this phone feels whether its range held it.
    private func revealed(_ q: CloseEnough.Question) {
        let r = q.results[me]
        if let r { if r.points > 0 { Haptics.yourTurn() } else { Haptics.nope() } }
        UIAccessibility.post(notification: .announcement, argument: "The answer: \(q.answer.map { q.format($0) } ?? ""). \(verdictTitle(r?.verdict)) \(r.map { "+\($0.points)" } ?? "")")
        if reduceMotion { landed = true; return }
        landed = false
        DispatchQueue.main.async { withAnimation(.spring(duration: 0.5, bounce: 0.35)) { landed = true } }
    }

    @ViewBuilder private func ask(_ q: CloseEnough.Question) -> some View {
        if view.lockedIn {
            Label("Locked in: \(q.formatRange(view.answerLo ?? 0, view.answerHi ?? 0))", systemImage: "lock.fill")
                .font(.headline).foregroundStyle(T2P.text)
                .accessibilityIdentifier("ce-locked")
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
            Text("A game is on. You’ll play in the next one.").foregroundStyle(T2P.muted)
        }
    }

    /// Who's in so far: a count, and the latest to lock in.
    @ViewBuilder private func lockedIn(_ q: CloseEnough.Question) -> some View {
        let inGame = view.players.filter { !$0.left && $0.seated }
        let done = inGame.filter(\.lockedIn).count
        let waiting = inGame.filter { !$0.lockedIn && $0.id != me && ($0.bot != nil || $0.connected) }.map(name)
        VStack(alignment: .leading, spacing: 4) {
            Text("\(done) of \(inGame.count) locked in").font(.subheadline.weight(.semibold)).foregroundStyle(T2P.text)
                .contentTransition(.numericText()).animation(.default, value: done)
                .accessibilityIdentifier("ce-count")
            if !waiting.isEmpty {
                Text("Waiting for \(waiting.joined(separator: ", ")). The answer shows when everyone’s in or the clock runs out.")
                    .font(.footnote).foregroundStyle(T2P.muted)
            }
            ForEach(Array(lockLines.enumerated()), id: \.offset) { i, line in
                Label(line, systemImage: "checkmark.circle.fill").font(.footnote.weight(i == 0 ? .semibold : .regular))
                    .foregroundStyle(i == 0 ? T2P.good : T2P.muted)
                    .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func verdictTitle(_ v: String?) -> String {
        ["tight": "Tight, and right.", "hit": "Inside, comfortably.", "miss": "Outside the range."][v ?? ""] ?? "No range locked in."
    }
    private func verdictDetail(_ v: String?) -> String {
        ["tight": "You committed to a small window and the answer was in it.",
         "hit": "Wide enough to be safe, which is why it’s worth less.",
         "miss": "No points. A range that misses scores nothing, however narrow."][v ?? ""] ?? "No points this time."
    }

    private func yourRange(_ r: CloseEnough.Result, _ q: CloseEnough.Question) -> String {
        guard let a = r.lo, let b = r.hi else { return "" }
        return "Your range: \(q.formatRange(a, b)). "
    }

    @ViewBuilder private func reveal(_ q: CloseEnough.Question) -> some View {
        let r = q.results[me]
        let missing = q.results.values.contains { $0.verdict == "none" }
        VStack(alignment: .leading, spacing: 10) {
            Text(missing ? "Not everyone locked in before the clock ran out." : "Everyone locked in.")
                .font(.subheadline.weight(.semibold)).foregroundStyle(T2P.muted)
                .accessibilityIdentifier("ce-why-ended")
            Text("The answer: \(q.answer.map { q.format($0) } ?? "")").font(.title2.bold()).foregroundStyle(T2P.text)
                .accessibilityIdentifier("ce-answer")
            if board3D {
                CloseEnoughBoard3D(state: .make(q: q, players: view.players, me: me, lo: lo, hi: hi, seated: view.common.seated))
                    .accessibilityIdentifier("ce-ranges")
            } else {
                RangesChart(q: q, players: view.players.filter { q.results[$0.id] != nil }, me: me, landed: landed)
            }
            if let r {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(verdictTitle(r.verdict))\(r.points > 0 ? " +\(r.points)" : "")").font(.headline).foregroundStyle(r.points > 0 ? T2P.good : T2P.ember)
                    Text(yourRange(r, q) + verdictDetail(r.verdict))
                        .font(.subheadline).foregroundStyle(T2P.muted)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("ce-verdict")
            }
            if let why = q.why, !why.isEmpty { Text("Why: \(why)").foregroundStyle(T2P.muted) }
            if room.isOwner {
                Button(q.n < q.of ? "Next question" : "See the standings") { room.move("next"); Haptics.select() }.buttonStyle(GoldButtonStyle())
                    .accessibilityIdentifier("ce-next")
            }
            if let e = q.endsAt {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let left = max(0, Int((e / 1000 - ctx.date.timeIntervalSince1970).rounded(.up)))
                    if left > 0 {
                        Text(room.isOwner ? "Or it goes on by itself in \(left)s." : q.n < q.of ? "Next question in \(left)s." : "The standings in \(left)s.")
                            .font(.footnote.monospacedDigit()).foregroundStyle(T2P.muted)
                            .accessibilityIdentifier("ce-next-in")
                    }
                }
            }
        }
    }

    private func standings(_ q: CloseEnough.Question) -> some View {
        VStack(spacing: 0) {
            ForEach(view.players.filter { !$0.left || $0.score > 0 }.sorted { $0.score > $1.score }) { p in
                HStack(spacing: 10) {
                    FaceView(face: p.face, size: 32)
                    Text(name(p)).foregroundStyle(T2P.text)
                    if p.bot != nil { Tag(text: "BOT") }
                    if p.id == view.common.owner { Image(systemName: "crown.fill").font(.caption).foregroundStyle(T2P.gold).accessibilityLabel("runs the room") }
                    if q.stage == "ask" && p.lockedIn { Image(systemName: "checkmark.circle.fill").foregroundStyle(T2P.good).accessibilityLabel("locked in") }
                    Spacer()
                    if q.stage == "reveal", let r = q.results[p.id] {
                        Text(r.points > 0 ? "+\(r.points)" : "0").font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(r.points > 0 ? T2P.good : T2P.faint)
                    }
                    Text("\(p.score)").font(.headline.monospacedDigit()).foregroundStyle(T2P.text)
                        .contentTransition(.numericText(value: Double(p.score)))
                        .animation(reduceMotion ? nil : Animation.spring(duration: 0.5), value: p.score)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .accessibilityElement(children: .combine)
            }
        }
        .background(T2P.panel, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityIdentifier("ce-standings")
    }
}

/// Every range on the question's scale with the answer through them, as the website's TV page shows it: who was
/// close, who was wide, who missed, and their points.
struct RangesChart: View {
    let q: CloseEnough.Question
    let players: [ScorePlayer]
    let me: String
    let landed: Bool
    private func rangeText(_ r: CloseEnough.Result?) -> String {
        guard let a = r?.lo, let b = r?.hi else { return "no range" }
        return q.formatRange(a, b)
    }
    var body: some View {
        let span = max(1, q.ceiling - q.floor)
        let frac = { (v: Double) in CGFloat(min(1, max(0, (v - q.floor) / span))) }
        let rows = players.sorted { (q.results[$0.id]?.points ?? 0) > (q.results[$1.id]?.points ?? 0) }
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows) { p in
                let r = q.results[p.id]
                HStack(spacing: 10) {
                    Text(p.id == me ? "You" : RoomPlayer.stripBot(p.name)).font(.footnote.weight(p.id == me ? .bold : .regular))
                        .foregroundStyle(T2P.text).frame(width: 64, alignment: .leading).lineLimit(1).minimumScaleFactor(0.7)
                    GeometryReader { g in
                        let w = g.size.width
                        ZStack(alignment: .leading) {
                            Capsule().fill(T2P.panelHi).frame(height: 10)
                            if let a = r?.lo, let b = r?.hi {
                                Capsule().fill(r?.verdict == "miss" ? T2P.ember.opacity(0.85) : T2P.gold.opacity(0.9))
                                    .frame(width: max(5, (frac(b) - frac(a)) * w), height: 10)
                                    .offset(x: frac(a) * w)
                            }
                            if let ans = q.answer {
                                Rectangle().fill(T2P.text).frame(width: 2, height: 22)
                                    .offset(x: frac(ans) * w - 1, y: landed ? 0 : -18)
                                    .opacity(landed ? 1 : 0)
                            }
                        }
                        .frame(height: 22)
                    }
                    .frame(height: 22)
                    Text(r?.lo == nil ? "none" : (r?.points ?? 0) > 0 ? "+\(r?.points ?? 0)" : "0").font(.footnote.weight(.bold).monospacedDigit())
                        .foregroundStyle((r?.points ?? 0) > 0 ? T2P.good : T2P.faint).frame(width: 40, alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(p.id == me ? "You" : RoomPlayer.stripBot(p.name)): \(rangeText(r)), \(r?.points ?? 0) points")
            }
            HStack { Text(q.format(q.floor)); Spacer(); Text(q.format(q.ceiling)) }
                .font(.caption2).foregroundStyle(T2P.muted).padding(.leading, 74).padding(.trailing, 50)
                .accessibilityHidden(true)
        }
        .padding(12)
        .background(T2P.panel, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityIdentifier("ce-ranges")
    }
}

/// The end of a game: who won and why, everyone's points and how often their range held the answer, and what next.
struct CloseEnoughOver: View {
    @ObservedObject var room: RoomModel
    @EnvironmentObject var app: AppModel
    let view: CloseEnough.View
    var body: some View {
        let me = view.common.meId
        let winners = view.common.winners ?? []
        let sorted = view.players.filter { !$0.left || $0.score > 0 }.sorted { $0.score > $1.score }
        let names = winners.compactMap { w in view.players.first { $0.id == w } }.map { $0.id == me ? "You" : RoomPlayer.stripBot($0.name) }
        let asked = view.players.map { $0.hits + $0.misses }.max() ?? 0
        ScrollView {
            VStack(spacing: 16) {
                if winners.count == 1, let w = view.players.first(where: { $0.id == winners[0] }) {
                    FaceView(face: w.face, size: 76).overlay(Circle().stroke(T2P.gold, lineWidth: 3).padding(-3))
                } else {
                    Image(systemName: "trophy.fill").font(.system(size: 48)).foregroundStyle(T2P.gold).accessibilityHidden(true)
                }
                Text(winners.count > 1 ? "A shared win!" : winners.contains(me) ? "You win!" : "\(names.first ?? "Someone") wins!")
                    .font(Painted.display(34, .bold)).foregroundStyle(T2P.text).multilineTextAlignment(.center)
                    .accessibilityIdentifier("game-over")
                PaintedDivider()
                Text(winners.count > 1 ? "\(names.joined(separator: " and ")) finished level on points after \(asked) questions."
                     : "The highest total after \(asked) question\(asked == 1 ? "" : "s").")
                    .foregroundStyle(T2P.muted).multilineTextAlignment(.center)
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
                                Text("\(p.hits) of \(p.hits + p.misses) in range").font(.subheadline).foregroundStyle(T2P.muted)
                            }
                            Spacer()
                            Text("\(p.score)").font(.title3.bold().monospacedDigit()).foregroundStyle(T2P.text)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .accessibilityElement(children: .combine)
                    }
                }
                .background(T2P.panel, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Painted.rim, lineWidth: 1.5))
                // the choices, painted like the game (Nov 18)
                if room.isOwner {
                    Button("Play again") { room.send(Out.again); room.send(Out.deal); Haptics.play() }.buttonStyle(PaintedButtonStyle(kind: .gold))
                        .accessibilityIdentifier("play-again")
                    Button("Change seats") { room.send(Out.again) }.buttonStyle(PaintedButtonStyle(kind: .quiet))
                } else {
                    Text("If \(room.ownerName ?? "the room’s owner") starts another game, you’ll be in it.").foregroundStyle(T2P.muted).multilineTextAlignment(.center)
                }
                Button("Back to Library") { room.leave(); app.closeRoom(); app.tab = .library }
                    .buttonStyle(PaintedButtonStyle(kind: .quiet))
                    .accessibilityIdentifier("back-to-library")
                TipLine()   // #598
            }
            .padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .onAppear { if winners.contains(me) { Haptics.yourTurn() } }
    }
}

/// Where the range sits on the question's scale while it's being set.
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
                }
                .frame(height: 30)
            }
            .frame(height: 30)
            HStack { Text(q.format(q.floor)); Spacer(); Text(q.format(q.ceiling)) }.font(.caption).foregroundStyle(T2P.muted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Scale from \(q.format(q.floor)) to \(q.format(q.ceiling)); your range \(q.formatRange(lo, hi))")
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
