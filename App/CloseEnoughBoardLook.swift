import SwiftUI
import T2PCore

/// #728: Close Enough's 3D board look (You → "3D Close Enough board", #535) on one screen with no page scroll, as the
/// brass look is (#727). Asking: the standings' chips, the question (it takes the room that's left and its type shrinks
/// to fit), the 3D board, the sliders, the readout, Lock, and who's in. At the answer the board shows every range and the
/// result (verdict, your range, why, the standings with each range, the reactions, Next) comes up as a pop-up card under
/// the board, in the board's navy and gold; tap outside or its chevron to see the board whole, "See the result" brings
/// it back. The reactions are in the room's menu while asking.
struct CloseEnoughBoardGame: View {
    @ObservedObject var room: RoomModel
    let view: CloseEnough.View
    let q: CloseEnough.Question
    var onLeave: () -> Void
    @Binding var lo: Double
    @Binding var hi: Double
    /// the latest player to lock in ("Rosa locked in"), so a bot's answer is seen landing
    let lockLine: String?
    /// read so a text-size change redraws the screen
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showResult = false
    @State private var boardBottom: CGFloat = 0     // where the board ends, so the pop-up stops under it

    private var me: String { view.common.meId }
    private var asking: Bool { q.stage == "ask" }
    private var mine: CloseEnough.Result? { q.results[me] }
    private var ranked: [ScorePlayer] { view.players.filter { !$0.left || $0.score > 0 }.sorted { $0.score > $1.score } }
    private func name(_ p: ScorePlayer) -> String { p.id == me ? "You" : RoomPlayer.stripBot(p.name) }

    private static let verdicts: [String: (String, String)] = [
        "tight": ("Tight, and right.", "You committed to a small window and the answer was in it."),
        "hit": ("Inside, comfortably.", "Wide enough to be safe, which is why it’s worth less."),
        "miss": ("Outside the range.", "No points. A range that misses scores nothing, however narrow."),
        "none": ("No range locked in.", "No points this time."),
    ]

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                TableTopBar(game: room.game, code: room.code, line: "\(view.me?.score ?? 0) POINTS", onLeave: onLeave,
                            owner: room.isOwner, room: room, reactions: true)
                GeometryReader { g in
                    // a small screen (an iPhone SE) or Larger Text: a shorter board and tighter spacing, so it all fits
                    let compact = g.size.height < 620 || textSize >= .xxLarge
                    let width = min(g.size.width, 640) - (compact ? 28 : 40)
                    // the page never scrolls; only if a screen ever can't hold it all does it scroll rather than cut Lock off
                    ViewThatFits(in: .vertical) {
                        page(g.size.height, width, compact)
                        ScrollView { page(g.size.height, width, compact) }.scrollBounceBehavior(.basedOnSize)
                    }
                    .frame(width: g.size.width, height: g.size.height, alignment: .top)
                }
            }
            if showResult && !asking {
                resultCard
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    .zIndex(3)
            }
        }
        .coordinateSpace(name: CEBoardBottom.space)
        .onPreferenceChange(CEBoardBottom.self) { boardBottom = $0 }
        // the answer: the beam drops onto the board first, then the result comes up
        .task(id: "\(q.n)-\(q.stage)") {
            if asking { showResult = false; return }
            if !reduceMotion { try? await Task.sleep(nanoseconds: 1_100_000_000) }
            guard !Task.isCancelled, !asking else { return }
            withAnimation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.12)) { showResult = true }
        }
    }

    // MARK: the page

    private func page(_ h: CGFloat, _ width: CGFloat, _ compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            if asking {
                chips
                header
                question(compact)
                    .frame(minHeight: 44, idealHeight: 44, maxHeight: .infinity, alignment: .topLeading)
                board(h, width, compact)
                askControls(compact)
            } else {
                header
                questionLine
                Text("The answer: \(q.answer.map { q.format($0) } ?? "")").font(.title2.bold()).foregroundStyle(T2P.text)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .accessibilityIdentifier("ce-answer")
                board(h, width, compact)
                revealLow
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, compact ? 14 : 20).padding(.top, compact ? 6 : 10).padding(.bottom, compact ? 8 : 12)
        .frame(maxWidth: 640).frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : .spring(duration: 0.4), value: q.n)
    }

    /// The standings as one line of chips: face and points, a tick for each player who's locked in, yours lit.
    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ranked) { p in
                    HStack(spacing: 5) {
                        FaceView(face: p.face, size: 22)
                        Text("\(p.score)").font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(T2P.text)
                            .contentTransition(.numericText(value: Double(p.score)))
                        if p.lockedIn { Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(T2P.good) }
                    }
                    .padding(.leading, 5).padding(.trailing, 10).frame(minHeight: 32)
                    .background(T2P.panel, in: Capsule())
                    .overlay(Capsule().strokeBorder(p.id == me ? T2P.gold : T2P.line, lineWidth: 1))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(name(p)): \(p.score) points\(p.lockedIn ? ", locked in" : "")")
                }
            }
            .padding(.horizontal, 1)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("ce-chips")
    }

    /// Question n of N, how many are in, and the clock.
    private var header: some View {
        let inGame = view.players.filter { !$0.left && $0.seated }
        let done = inGame.filter(\.lockedIn).count
        return HStack(spacing: 10) {
            Text("Question \(q.n) of \(q.of)").font(.subheadline.weight(.semibold)).foregroundStyle(T2P.muted)
                .lineLimit(1).minimumScaleFactor(0.75)
                .accessibilityIdentifier("ce-number")
            Spacer(minLength: 4)
            if asking {
                Text("\(done) of \(inGame.count) in").font(.subheadline.weight(.semibold)).foregroundStyle(T2P.text)
                    .lineLimit(1).fixedSize()
                    .contentTransition(.numericText()).animation(.default, value: done)
                    .accessibilityLabel("\(done) of \(inGame.count) locked in")
                    .accessibilityIdentifier("ce-count")
                if let e = q.endsAt { Countdown(endsAt: e).fixedSize() }
            }
        }
    }

    /// The question takes the room that's left between the header and the board; a long one's type shrinks to fit.
    private func question(_ compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(q.q).font(.title2.bold()).foregroundStyle(T2P.text)
                .minimumScaleFactor(0.45)
                .layoutPriority(1)
                .accessibilityIdentifier("ce-question")
            if !q.note.isEmpty {
                Text(q.note).font(.subheadline).foregroundStyle(T2P.muted).lineLimit(compact ? 2 : 3).minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(q.n)
        .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.move(edge: .trailing).combined(with: .opacity))
    }

    /// At the answer the question is one line (cut with …); VoiceOver still reads the whole of it.
    private var questionLine: some View {
        Text(q.q).font(.headline).foregroundStyle(T2P.muted)
            .lineLimit(1).truncationMode(.tail)
            .accessibilityLabel(q.q)
            .accessibilityIdentifier("ce-question")
    }

    /// The 3D board at its own height when the screen has the room, else shorter, its width kept in proportion so the
    /// camera sees the same board. At the answer it gives up to about half the screen, so the pop-up has room under it.
    private func board(_ h: CGFloat, _ width: CGFloat, _ compact: Bool) -> some View {
        let state = CloseEnoughBoardState.make(q: q, players: view.players, me: me,
                                               lo: asking && view.lockedIn ? view.answerLo ?? lo : lo,
                                               hi: asking && view.lockedIn ? view.answerHi ?? hi : hi, seated: view.common.seated)
        let natural = CloseEnoughBoard3D.naturalHeight(lanes: state.lanes.count)
        let cap = asking ? (compact ? max(96, h * 0.2) : max(120, h * 0.26)) : max(130, h * (compact ? 0.36 : 0.44))
        let bh = min(natural, cap)
        let bw = bh < natural ? width * bh / natural : width
        return CloseEnoughBoard3D(state: state, height: bh)
            .accessibilityIdentifier(asking ? "ce-board3d" : "ce-ranges")
            .frame(width: bw, height: bh)
            .frame(maxWidth: .infinity)
            .background(GeometryReader { t in
                Color.clear.preference(key: CEBoardBottom.self, value: t.frame(in: .named(CEBoardBottom.space)).maxY)
            })
    }

    // MARK: asking

    @ViewBuilder private func askControls(_ compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            if view.lockedIn {
                Label("Locked in: \(q.formatRange(view.answerLo ?? 0, view.answerHi ?? 0))", systemImage: "lock.fill")
                    .font(.headline).foregroundStyle(T2P.text).lineLimit(2).minimumScaleFactor(0.8)
                    .accessibilityIdentifier("ce-locked")
            } else if view.common.seated {
                slider("Low", value: $lo, compact) { if hi < $0 { hi = $0 } }
                slider("High", value: $hi, compact) { if lo > $0 { lo = $0 } }
                let worth = q.worth(lo: lo, hi: hi, maxPoints: view.maxPoints)
                Text(compact ? "\(q.formatRange(lo, hi)) · worth \(worth) points"
                     : "From \(q.format(lo)) to \(q.format(hi)) · worth \(worth) points if it holds the answer")
                    .font(.subheadline).foregroundStyle(T2P.muted).lineLimit(compact ? 1 : 2).minimumScaleFactor(0.7)
                    .accessibilityIdentifier("ce-worth")
                Button("Lock in this range") { room.move("range", ["lo": .number(lo), "hi": .number(hi)]); Haptics.play() }
                    .buttonStyle(GoldButtonStyle()).accessibilityIdentifier("lock-in")
            } else {
                Text("A game is on. You’ll play in the next one.").foregroundStyle(T2P.muted)
            }
            status(compact)
        }
    }

    /// A line under Lock: who just locked in, and who we're still waiting for.
    @ViewBuilder private func status(_ compact: Bool) -> some View {
        let waiting = view.players.filter { !$0.left && $0.seated && !$0.lockedIn && $0.id != me && ($0.bot != nil || $0.connected) }.map(name)
        let wait = waiting.isEmpty ? "" : "Waiting for \(waiting.joined(separator: ", "))."
        if lockLine != nil || !wait.isEmpty {
            (Text(lockLine.map { "✓ \($0). " } ?? "").font(.footnote.weight(.semibold)).foregroundColor(T2P.good)
             + Text(wait).font(.footnote).foregroundColor(T2P.muted))
                .lineLimit(compact ? 1 : 2).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: lockLine)
        }
    }

    @ViewBuilder private func slider(_ label: String, value: Binding<Double>, _ compact: Bool, then: @escaping (Double) -> Void) -> some View {
        let reading = Text(q.format(value.wrappedValue)).font(.headline.monospacedDigit()).foregroundStyle(T2P.gold)
            .lineLimit(1).minimumScaleFactor(0.7)
        let control = Slider(value: Binding(get: { value.wrappedValue }, set: { value.wrappedValue = q.snap($0); then(value.wrappedValue) }),
                             in: q.floor...max(q.ceiling, q.floor + 1), step: q.step > 0 ? q.step : 1)
            .tint(T2P.gold)
            .accessibilityLabel(label)
            .accessibilityValue(q.format(value.wrappedValue))
            .accessibilityIdentifier("ce-\(label.lowercased())")
        if compact {
            // one row each on a small screen: the name, the slider, the number
            HStack(spacing: 10) {
                Text(label).font(.headline).foregroundStyle(T2P.text).lineLimit(1).fixedSize()
                control
                reading.frame(maxWidth: 120, alignment: .trailing).fixedSize(horizontal: false, vertical: true)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                HStack { Text(label).font(.headline).foregroundStyle(T2P.text); Spacer(); reading }
                control
            }
        }
    }

    // MARK: the answer

    private var points: Int { mine?.points ?? 0 }

    /// Under the board with the pop-up hidden: what you scored, when it goes on, and the button that brings the result
    /// back. While the pop-up's up it has both, so this steps aside rather than peek out behind the card's edge.
    private var revealLow: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(points > 0 ? "+\(points) points" : "No points").font(.title3.bold())
                    .foregroundStyle(points > 0 ? T2P.good : T2P.muted)
                Spacer(minLength: 8)
                countdown(short: false, alignment: .trailing)
            }
            if !showResult {
                Button("See the result") { withAnimation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.12)) { showResult = true } }
                    .buttonStyle(GoldButtonStyle())
                    .accessibilityIdentifier("ce-show-result")
            }
        }
        .opacity(showResult ? 0 : 1)
        .accessibilityHidden(showResult)
    }

    private func hideResult() { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) { showResult = false } }

    /// The result as a pop-up card over the lower part of the screen, its top kept under the board. If it's taller than
    /// the room it has, only its middle scrolls; Next stays pinned at the bottom.
    private var resultCard: some View {
        GeometryReader { s in
            let top = boardBottom > 0 ? boardBottom + 12 : s.size.height * 0.5
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.001).contentShape(Rectangle()).onTapGesture { hideResult() }.accessibilityHidden(true)
                resultBody
                    .frame(maxHeight: max(170, s.size.height - top - 8), alignment: .bottom)
                    .padding(.horizontal, 10).padding(.bottom, 8)
                    .frame(maxWidth: 560)
            }
            .frame(width: s.size.width, height: s.size.height, alignment: .bottom)
        }
    }

    private var resultBody: some View {
        let verdict = mine?.verdict ?? "none"
        let vd = Self.verdicts[verdict] ?? Self.verdicts["none"]!
        let edge: Color = verdict == "tight" || verdict == "hit" ? T2P.good : verdict == "miss" ? T2P.ember : T2P.faint
        let head: Color = verdict == "miss" ? T2P.ember : verdict == "none" ? T2P.text : T2P.good
        return VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(vd.0 + (points > 0 ? " +\(points)" : "")).font(.title3.bold()).foregroundStyle(head)
                    .lineLimit(2).minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("ce-verdict")
                Button(action: hideResult) {
                    Image(systemName: "chevron.down").font(.system(size: 15, weight: .bold)).foregroundStyle(T2P.muted)
                        .frame(width: 44, height: 36).contentShape(Rectangle())
                }
                .accessibilityLabel("Hide the result")
                .accessibilityIdentifier("ce-hide-result")
            }
            .padding(.leading, 20).padding(.trailing, 8).padding(.top, 12)
            ViewThatFits(in: .vertical) {
                resultMiddle(vd.1)
                // (for UI tests: only when the pop-up can't hold it all, on a small screen or at Larger Text)
                ScrollView { resultMiddle(vd.1) }
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollIndicatorsFlash(onAppear: true)
                    .accessibilityIdentifier("ce-result-scrolls")
            }
            resultFoot
        }
        .background(LinearGradient(colors: [Color(hex: 0x1A2542), Color(hex: 0x0F1628)], startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: 18))
        // the verdict's color down the left edge, cut to the card's rounded corners
        .overlay {
            RoundedRectangle(cornerRadius: 18).fill(edge)
                .mask(HStack(spacing: 0) { Rectangle().frame(width: 6); Spacer(minLength: 0) })
        }
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(T2P.gold.opacity(0.55), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.6), radius: 20, y: -2)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityAction(.escape) { hideResult() }
        .accessibilityIdentifier("ce-result")
    }

    private func resultMiddle(_ detail: String) -> some View {
        let missing = q.results.values.contains { $0.verdict == "none" }
        let yours = mine.flatMap { r in r.lo.flatMap { a in r.hi.map { b in "Your range: \(q.formatRange(a, b)). " } } } ?? ""
        return VStack(alignment: .leading, spacing: 8) {
            // why it ended rides on the end of the detail, a line saved for the standings
            (Text(yours + detail + " ").font(.subheadline).foregroundColor(T2P.muted)
             + Text(missing ? "Not everyone locked in before the clock ran out." : "Everyone locked in.").font(.footnote).foregroundColor(T2P.faint))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("ce-why-ended")
            if let why = q.why, !why.isEmpty {
                (Text("Why: ").foregroundColor(T2P.text).fontWeight(.bold) + Text(why))
                    .font(.subheadline).foregroundStyle(T2P.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            standings.padding(.top, 2)
            WebFlow(spacing: 8) {
                ForEach(Reaction.allCases) { r in
                    Button(r.words) { room.react(r); Haptics.select() }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(T2P.text)
                        .padding(.horizontal, 14).frame(minHeight: 40)
                        .background(Color.white.opacity(0.08), in: Capsule())
                        .accessibilityLabel("Send \(r.words)")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.leading, 20).padding(.trailing, 16).padding(.top, 4).padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Next (the room's owner) and when it goes on by itself: side by side when they fit, else stacked.
    private var resultFoot: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                countdown(short: true, alignment: .leading)
                if room.isOwner { nextButton.fixedSize(horizontal: true, vertical: false) }
            }
            VStack(spacing: 6) {
                if room.isOwner { nextButton }
                countdown(short: false, alignment: .center)
            }
        }
        .padding(.leading, 20).padding(.trailing, 16).padding(.top, 10).padding(.bottom, 12)
        .overlay(alignment: .top) { Rectangle().fill(T2P.line).frame(height: 1).padding(.leading, 20).padding(.trailing, 16) }
    }

    private var nextButton: some View {
        Button(q.n < q.of ? "Next question" : "See the standings") { showResult = false; room.move("next"); Haptics.select() }
            .buttonStyle(GoldButtonStyle())
            .accessibilityIdentifier("ce-next")
    }

    /// When it goes on by itself. Never coral at the answer: nothing's at stake there.
    @ViewBuilder private func countdown(short: Bool, alignment: Alignment) -> some View {
        if let e = q.endsAt {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let left = max(0, Int((e / 1000 - ctx.date.timeIntervalSince1970).rounded(.up)))
                let owner = short ? "On by itself in \(left)s." : "Or it goes on by itself in \(left)s."
                Text(left == 0 ? " " : room.isOwner ? owner : q.n < q.of ? "Next question in \(left)s." : "The standings in \(left)s.")
                    .font(.footnote.monospacedDigit()).foregroundStyle(T2P.muted)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: alignment)
                    .accessibilityIdentifier("ce-next-in")
            }
        } else {
            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
        }
    }

    /// The standings in the pop-up: compact rows (face, name, range, points this question, total), yours lit.
    private var standings: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("STANDINGS").font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(T2P.faint)
            ForEach(ranked) { p in
                ViewThatFits(in: .horizontal) {
                    standingRow(p, oneLine: true)
                    standingRow(p, oneLine: false)
                }
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.5), value: view.players.map(\.score))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ce-standings")
    }

    @ViewBuilder private func standingRow(_ p: ScorePlayer, oneLine: Bool) -> some View {
        let x = q.results[p.id]
        let range = x.flatMap { r in r.lo.flatMap { a in r.hi.map { b in q.formatRange(a, b) } } } ?? "No range"
        let pts = x?.points ?? 0
        let who = Text(name(p)).font(.subheadline.weight(.semibold)).foregroundColor(T2P.text)
            + Text(p.bot != nil ? " (bot)" : "").font(.caption).foregroundColor(T2P.faint)
        let rangeText = Text(range).font(.footnote).foregroundStyle(T2P.muted).lineLimit(1)
        let gained = Text(pts > 0 ? "+\(pts)" : "0").font(.footnote.weight(.bold).monospacedDigit())
            .foregroundStyle(pts > 0 ? T2P.good : T2P.faint)
        let total = Text("\(p.score)").font(.headline.monospacedDigit()).foregroundStyle(T2P.gold)
            .contentTransition(.numericText(value: Double(p.score)))
        HStack(spacing: 8) {
            FaceView(face: p.face, size: 24)
            if oneLine {
                who.lineLimit(1).fixedSize()
                Spacer(minLength: 6)
                rangeText.fixedSize()
                gained.fixedSize()
                total.fixedSize()
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    who.lineLimit(1).minimumScaleFactor(0.8)
                    rangeText.minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                gained
                total
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 3).frame(minHeight: 31)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(p.id == me ? T2P.gold : T2P.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// Where the 3D board ends on the screen, so the result's pop-up stops under it (#728).
struct CEBoardBottom: PreferenceKey {
    static let space = "ce-board-bottom"
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
