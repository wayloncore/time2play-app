import SwiftUI
import T2PCore

/// Overdraft with no host screen (#400): everyone else's seats across the top, the piles in the middle, your hand
/// along the bottom. The room decides what can go (legal, jump); this screen only draws it and sends taps.
/// #489: every moment is shown, not just its result: the deal, each card flying to the pile, who drew, a Reverse,
/// a Skip, a jump-in or a train taken said big for a moment, a line of what just happened, and the hand's end.
struct OverdraftTableView: View {
    @ObservedObject var room: RoomModel
    let view: Overdraft.View
    var onLeave: () -> Void
    @State private var wild: Overdraft.Card?
    @State private var wildJump = false
    @State private var feed: [FeedLine] = []
    @State private var flash: Flash?
    @State private var flying: Flying?
    @State private var gained: [String: Int] = [:]
    @State private var hitNote: String?
    @State private var dealt: Int?            // while the deal is shown: how many of your cards have landed
    @State private var showOver = false
    @Environment(\.horizontalSizeClass) private var hsize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct FeedLine: Identifiable, Equatable { let id = UUID(); let text: String }
    struct Flash: Identifiable, Equatable { let id = UUID(); let icon: String; let word: String; let detail: String }
    struct Flying: Equatable { let card: Overdraft.Card; var offset: CGSize; var scale: CGFloat; var turn: Double }

    private var table: Overdraft.Table { view.table! }
    /// Everyone else, in turn order from you: the first seat is the one play reaches after yours (direction 1).
    private var others: [Overdraft.Seat] {
        let seats = table.seats
        guard let i = seats.firstIndex(where: { $0.id == view.me.id }), seats.count > 1 else { return seats.filter { $0.id != view.me.id } }
        return (1..<seats.count).map { seats[(i + $0) % seats.count] }
    }
    private func name(_ id: String?) -> String {
        id == view.me.id ? "you" : table.seats.first { $0.id == id }.map { RoomPlayer.stripBot($0.name) } ?? "someone"
    }
    private func cap(_ id: String?) -> String { let n = name(id); return n.prefix(1).uppercased() + n.dropFirst() }
    private var cardWidth: CGFloat { hsize == .regular ? 130 : 96 }

    var body: some View {
        VStack(spacing: 0) {
            TableTopBar(game: room.game, code: room.code, line: topLine, onLeave: onLeave, owner: room.isOwner, room: room)
            seatsRow
            feedLines
            Spacer(minLength: 4)
            piles
            orderAndSuit
            Spacer(minLength: 4)
            turnHeader
            HandView(view: view, dealt: dealt, onTap: tap)
                .frame(height: hsize == .regular ? 230 : 172)
            if view.drawn != nil && view.yourTurn {
                Button("Keep it and end my turn") { room.move("hold"); Haptics.select() }
                    .buttonStyle(QuietButtonStyle()).padding(.top, 4)
                    .accessibilityIdentifier("keep")
            }
            ReactionBar(room: room)
        }
        .overlay { if showOver { HandOver(room: room, view: view).transition(.opacity) } }
        .animation(.easeInOut(duration: 0.3), value: showOver)
        // a card table can't reflow like a list: its words grow to the largest standard size, and VoiceOver reads all of it
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .confirmationDialog("Pick the suit", isPresented: Binding(get: { wild != nil }, set: { if !$0 { wild = nil } }), titleVisibility: .visible) {
            ForEach(Overdraft.suits, id: \.self) { s in
                Button(Overdraft.suitNames[s] ?? s) { if let c = wild { send(c, suit: s, jump: wildJump) }; wild = nil }
            }
            Button("Cancel", role: .cancel) { wild = nil }
        }
        .onAppear(perform: appeared)
        .onChange(of: view.yourTurn) { _, mine in if mine { Haptics.yourTurn() } }
        .onChange(of: view.table) { old, new in if let new { changed(from: old, to: new) } }
    }

    // MARK: what just happened

    private func appeared() {
        if table.over { showOver = true; return }
        // a fresh hand (nothing played on the first card yet): show the deal, then whose turn it is
        let fresh = (table.top?.k ?? 0) == 0 && table.seats.allSatisfy { $0.cards == view.hand.count }
        if fresh { deal() }
    }

    /// The deal: your cards land one by one, and the line says who goes first.
    private func deal() {
        feed = []; hitNote = nil
        say("Dealt \(view.hand.count) cards each. \(cap(table.turn)) \(table.turn == view.me.id ? "go" : "goes") first.")
        if reduceMotion { return }
        dealt = 0
        for i in 1...max(1, view.hand.count) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.09 * Double(i)) {
                withAnimation(.spring(duration: 0.3)) { dealt = i }
                if i == view.hand.count { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { dealt = nil } }
                Haptics.select()
            }
        }
    }

    private func changed(from old: Overdraft.Table?, to new: Overdraft.Table) {
        if old?.turn != new.turn && new.turn != view.me.id { hitNote = nil }
        let moves = Overdraft.moves(from: old, to: new)
        for m in moves { if let line = words(m) { say(line) } }
        if let play = moves.last(where: { if case .played = $0 { return true }; return false }), case let .played(by, card, _) = play { fly(card, from: by) }
        for m in moves {
            switch m {
            case let .drew(who, n), let .hit(who, n, _, _), let .tookTrain(who, n): if who != view.me.id { bump(who, n) }
            default: break
            }
        }
        if let big = moves.last(where: \.isBig) { show(big) }
        if moves.contains(where: { if case let .hit(who, _, _, _) = $0 { return who == view.me.id }; if case let .tookTrain(who, _) = $0 { return who == view.me.id }; return false }) {
            Haptics.nope()
        }
        if old?.over == true && !new.over { showOver = false; deal(); return }   // Play again, dealt in place
        if new.over && !(old?.over ?? true) {
            // the last card lands and the table says who went out before the end screen covers it
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { if table.over { showOver = true } }
        } else if !new.over && showOver {
            showOver = false
        }
    }

    /// One line for the feed, or nil for a move the feed doesn't name.
    private func words(_ m: Overdraft.Move) -> String? {
        switch m {
        case let .played(by, card, jump):
            if table.over && table.winner == by { return "\(cap(by)) went out with \(card.label)" }
            return jump ? "\(cap(by)) jumped in with \(card.label)" : "\(cap(by)) played \(card.label)"
        case let .drew(who, n):
            if who == view.me.id, n == 1, let d = view.drawn, let c = view.hand.first(where: { $0.id == d }) { return "You drew \(c.label)" }
            return "\(cap(who)) drew \(n == 1 ? "a card" : "\(n) cards")"
        case let .hit(who, n, by, card):
            let line = "\(cap(who)) drew \(n) from \(by == view.me.id ? "your" : "\(name(by))’s") \(card.label)"
            if who == view.me.id { hitNote = "You drew \(n) from \(name(by))’s \(card.label). Still your turn." }
            return line
        case let .tookTrain(who, n):
            return who == view.me.id ? "You took the +\(n) train" : "\(cap(who)) took the +\(n) train"
        case .reversed:
            return "Reverse: play turns around"
        case let .skipped(who, _):
            return who == view.me.id ? "You’re skipped" : "\(cap(who)) is skipped"
        }
    }

    private func say(_ text: String) {
        withAnimation(reduceMotion ? nil : Animation.easeOut(duration: 0.25)) {
            feed.insert(FeedLine(text: text), at: 0)
            if feed.count > 3 { feed.removeLast(feed.count - 3) }
        }
    }

    /// A Reverse, a Skip, a jump-in or a train taken, big over the piles for a moment.
    private func show(_ m: Overdraft.Move) {
        let f: Flash
        switch m {
        case .reversed: f = Flash(icon: "arrow.triangle.2.circlepath", word: "Reverse", detail: "Play turns around")
        case let .skipped(who, _): f = Flash(icon: "nosign", word: "Skipped", detail: who == view.me.id ? "You miss a turn" : "\(cap(who)) misses a turn")
        case let .tookTrain(who, n): f = Flash(icon: "rectangle.stack.badge.plus", word: "+\(n) taken", detail: who == view.me.id ? "You draw \(n)" : "\(cap(who)) draws \(n)")
        case let .played(by, _, _): f = Flash(icon: "arrow.up.forward", word: "Jump in!", detail: by == view.me.id ? "You played the same card" : "\(cap(by)) played the same card")
        default: return
        }
        withAnimation(reduceMotion ? Animation.easeInOut(duration: 0.2) : Animation.spring(duration: 0.3)) { flash = f }
        UIAccessibility.post(notification: .announcement, argument: "\(f.word). \(f.detail)")
        Haptics.select()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { if flash?.id == f.id { withAnimation(.easeOut(duration: 0.3)) { flash = nil } } }
    }

    /// The card just played flies to the pile: from the seats along the top, or up from your hand.
    private func fly(_ card: Overdraft.Card, from id: String) {
        if id != view.me.id { Haptics.play() }
        guard !reduceMotion else { return }
        let start: CGSize
        if id == view.me.id { start = CGSize(width: 0, height: 260) }
        else {
            let i = others.firstIndex { $0.id == id } ?? 0
            let mid = Double(min(others.count, 3) - 1) / 2
            start = CGSize(width: max(-150, min(150, (Double(min(i, 2)) - mid) * 120)), height: -190)
        }
        flying = Flying(card: card, offset: start, scale: 0.55, turn: id == view.me.id ? 0 : -14)
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.38)) { flying?.offset = .zero; flying?.scale = 1; flying?.turn = 0 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { if flying?.card == card { flying = nil } }
    }

    /// "+2" over a seat that just gained cards.
    private func bump(_ id: String, _ n: Int) {
        withAnimation(reduceMotion ? nil : Animation.spring(duration: 0.3)) { gained[id] = n }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { withAnimation(.easeOut(duration: 0.3)) { gained[id] = nil } }
    }

    // MARK: the table

    private var topLine: String {
        if table.over { return "HAND OVER" }
        if table.stack > 0 { return "+\(table.stack) TRAIN" }
        return view.yourTurn ? "YOUR TURN" : "\(name(table.turn).uppercased())’S TURN"
    }

    private var seatsRow: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(others) { s in
                        SeatCard(seat: s, turn: table.turn == s.id && !table.over, owner: view.owner == s.id, endsAt: table.turnEndsAt, gained: gained[s.id])
                            .id(s.id)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 8)
            .onChange(of: table.turn) { _, t in
                guard let t, t != view.me.id else { return }
                withAnimation(reduceMotion ? nil : Animation.easeInOut) { proxy.scrollTo(t, anchor: .center) }
            }
        }
    }

    /// What just happened: the newest line bright, the two before it fainter.
    @ViewBuilder private var feedLines: some View {
        VStack(spacing: 2) {
            ForEach(Array(feed.enumerated()), id: \.element.id) { i, line in
                Text(line.text)
                    .font(i == 0 ? Font.subheadline.weight(.semibold) : Font.footnote)
                    .foregroundStyle(i == 0 ? T2P.text : T2P.muted.opacity(i == 1 ? 1 : 0.7))
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, feed.isEmpty ? 0 : 6)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 56, alignment: .top)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(feed.first?.text ?? "")
        .accessibilityIdentifier("od-feed")
    }

    private var piles: some View {
        HStack(spacing: 28) {
            Button { if view.yourTurn && view.drawn == nil && table.stack == 0 { room.move("draw"); Haptics.play() } else { Haptics.nope() } } label: {
                VStack(spacing: 6) {
                    CardImage(name: "card_back", width: cardWidth)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(canDraw ? T2P.gold : .clear, lineWidth: 3))
                    Text("\(table.drawLeft) left").font(.footnote).foregroundStyle(T2P.muted)
                }
            }
            .accessibilityLabel(canDraw ? "Draw a card" : "Draw pile, \(table.drawLeft) left")
            .accessibilityIdentifier("draw")
            ZStack {
                ForEach(Array(table.pile.dropLast().enumerated()), id: \.offset) { i, c in
                    CardImage(name: c.artName, width: cardWidth)
                        .rotationEffect(.degrees(Double(((c.k ?? i) * 37) % 17) - 8))
                        .offset(x: CGFloat(((c.k ?? i) * 13) % 9) - 4)
                }
                if let top = table.top {
                    CardImage(name: top.artName, width: cardWidth + 8)
                        .shadow(radius: 8)
                        .opacity(flying != nil && flying?.card.k == top.k ? 0 : 1)
                        .accessibilityLabel("On the table: \(top.spoken)\(top.isWild ? ", \(Overdraft.suitNames[table.suit ?? ""] ?? "") named" : "")")
                }
                if let f = flying {
                    CardImage(name: f.card.artName, width: cardWidth + 8)
                        .shadow(radius: 12)
                        .rotationEffect(.degrees(f.turn))
                        .scaleEffect(f.scale)
                        .offset(f.offset)
                        .accessibilityHidden(true)
                        .zIndex(2)
                }
                if table.stack > 0 {
                    Text("+\(table.stack)").font(.title.bold()).foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4).background(T2P.ember, in: Capsule())
                        .offset(y: 70).accessibilityLabel("A train of \(table.stack) cards")
                        .zIndex(3)
                }
            }
        }
        .overlay {
            if let f = flash {
                VStack(spacing: 6) {
                    Image(systemName: f.icon).font(.system(size: 40, weight: .bold)).foregroundStyle(T2P.gold)
                    Text(f.word).font(.title.bold()).foregroundStyle(T2P.text)
                    Text(f.detail).font(.subheadline.weight(.semibold)).foregroundStyle(T2P.muted)
                }
                .padding(.horizontal, 24).padding(.vertical, 16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(T2P.gold.opacity(0.5)))
                .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.scale(scale: 0.6).combined(with: .opacity))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("od-flash")
                .id(f.id)
            }
        }
    }

    private var canDraw: Bool { view.yourTurn && view.drawn == nil && table.stack == 0 }

    /// Which way play goes along the seats above, and the suit to match.
    private var orderAndSuit: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: table.direction >= 0 ? "arrow.right" : "arrow.left").font(.caption.weight(.bold))
                Text("Turn order").font(.caption.weight(.semibold))
            }
            .foregroundStyle(T2P.muted)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.black.opacity(0.3), in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(table.direction >= 0 ? "Turn order: left to right along the seats, then you" : "Turn order: right to left along the seats, then you")
            .accessibilityIdentifier("od-direction")
            if let s = table.suit ?? table.top?.suit {
                HStack(spacing: 6) {
                    Circle().fill(T2P.suit[s] ?? .gray).frame(width: 12, height: 12).overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 1))
                    Text(table.top?.isWild == true ? "\(Overdraft.suitNames[s] ?? s) named" : Overdraft.suitNames[s] ?? s).font(.caption.weight(.semibold))
                }
                .foregroundStyle(T2P.text)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.black.opacity(0.3), in: Capsule())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Suit to match: \(Overdraft.suitNames[s] ?? s)")
            }
        }
        .padding(.top, table.stack > 0 ? 18 : 8)
        .animation(reduceMotion ? nil : Animation.easeInOut, value: table.direction)
    }

    private var turnHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                if view.held {
                    Text("A bot is playing for you").font(.title3.bold()).foregroundStyle(T2P.text)
                    Text("Your seat is yours again at the next turn.").font(.subheadline).foregroundStyle(T2P.muted)
                } else if view.yourTurn {
                    Text(table.stack > 0 ? "You’re on the hook: +\(table.stack)" : "Your turn").font(.title.bold()).foregroundStyle(T2P.text).accessibilityIdentifier("your-turn")
                    Text(turnDetail).font(.subheadline).foregroundStyle(hitNote != nil && view.drawn == nil ? T2P.gold : T2P.muted)
                } else if table.over {
                    Text("Hand over").font(.title3.bold()).foregroundStyle(T2P.text).accessibilityIdentifier("table-over")
                    Text("\(view.hand.count) card\(view.hand.count == 1 ? "" : "s") left in your hand").font(.subheadline).foregroundStyle(T2P.muted)
                } else {
                    Text(table.stack > 0 ? "\(cap(table.turn)) is on the hook" : "\(cap(table.turn))’s turn").font(.title3.bold()).foregroundStyle(T2P.text)
                        .accessibilityIdentifier("their-turn")
                    Text(view.jump.isEmpty ? "You have \(view.hand.count) card\(view.hand.count == 1 ? "" : "s")" : "Jump in: you hold the same card").font(.subheadline)
                        .foregroundStyle(view.jump.isEmpty ? T2P.muted : T2P.gold)
                }
            }
            Spacer()
            if view.yourTurn, let ends = table.turnEndsAt { TurnClock(endsAt: ends, total: 45) }
        }
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
    }

    private var turnDetail: String {
        if view.drawn != nil { return view.legal.isEmpty ? "No luck: keep it" : "Play the card you drew, or keep it" }
        if table.stack > 0 {
            return table.taking || view.legal.isEmpty ? "Nothing can add to it. Taking +\(table.stack)…" : "Play a lit +2 or +4 to pass it on, or take it when your clock runs out"
        }
        if let h = hitNote { return h }
        let n = view.legal.count
        let can = n == 0 ? "nothing can go: draw" : "\(n) card\(n == 1 ? "" : "s") can go"
        return [view.matchLine, can].compactMap { $0 }.joined(separator: " · ")
    }

    private func tap(_ c: Overdraft.Card) {
        let jump = !view.yourTurn && view.jump.contains(c.id)
        guard (view.yourTurn && view.legal.contains(c.id)) || jump else { Haptics.nope(); return }
        if c.isWild { wild = c; wildJump = jump; return }
        send(c, suit: nil, jump: jump)
    }

    private func send(_ c: Overdraft.Card, suit: String?, jump: Bool) {
        var f: [String: JSON] = ["card": .string(c.id)]
        if let s = suit { f["suit"] = .string(s) }
        if jump { f["on"] = .number(Double(table.seq)) }
        room.move(jump ? "jump" : "play", f)
        Haptics.play()
    }
}

/// A card, drawn with the website's own art.
struct CardImage: View {
    let name: String
    var width: CGFloat = 96
    var body: some View {
        Group {
            if let i = Art.image(name) { Image(uiImage: i).resizable().scaledToFit() }
            else { RoundedRectangle(cornerRadius: 8).fill(T2P.panelHi) }
        }
        .frame(width: width, height: width * 489 / 320)
        .clipShape(RoundedRectangle(cornerRadius: width / 14))
    }
}

/// Your hand: every card the room sent, the ones that can go lifted and lit; the rest dimmed.
struct HandView: View {
    let view: Overdraft.View
    /// While the deal is shown: how many cards have landed (nil: all of them).
    var dealt: Int? = nil
    var onTap: (Overdraft.Card) -> Void
    @Environment(\.horizontalSizeClass) private var hsize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { g in
            let n = max(1, view.hand.count)
            let w: CGFloat = hsize == .regular ? 130 : 96
            let step = min(w * 0.82, max(44, (g.size.width - 32 - w) / CGFloat(max(1, n - 1))))   // 44 pt of every card to tap, at least
            let total = step * CGFloat(n - 1) + w
            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .bottomLeading) {
                    ForEach(Array(view.hand.enumerated()), id: \.element.id) { i, c in
                        let ok = playable(c)
                        let shown = dealt.map { i < $0 } ?? true
                        Button { onTap(c) } label: {
                            CardImage(name: c.artName, width: w)
                                .overlay(RoundedRectangle(cornerRadius: w / 14).stroke(ok ? T2P.gold : .clear, lineWidth: 3))
                                .shadow(color: ok ? T2P.gold.opacity(0.5) : .black.opacity(0.4), radius: ok ? 8 : 3)
                                .brightness(ok || !view.yourTurn ? 0 : -0.12)
                        }
                        .buttonStyle(.plain)
                        .opacity(shown ? 1 : 0)
                        .offset(x: CGFloat(i) * step, y: (ok ? -16 : 0) + (shown ? 0 : -90))
                        // a card drawn drops in from the deck; a card played lifts off toward the pile
                        .transition(reduceMotion ? AnyTransition.opacity
                                    : AnyTransition.asymmetric(insertion: AnyTransition.offset(y: -90).combined(with: .opacity),
                                                               removal: AnyTransition.offset(y: -150).combined(with: .opacity)))
                        .accessibilityLabel(c.spoken)
                        .accessibilityValue(ok ? (view.yourTurn ? "playable" : "jump in") : "can’t go now")
                        .accessibilityIdentifier(ok ? "legal-\(c.id)" : "card-\(c.id)")
                        .accessibilitySortPriority(Double(n - i))
                    }
                }
                .frame(width: max(total + 32, g.size.width), height: g.size.height, alignment: .bottomLeading)
                .padding(.leading, max(16, (g.size.width - total) / 2))
            }
        }
        .animation(.spring(duration: 0.3), value: view.hand)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Your hand, \(view.hand.count) cards")
    }

    private func playable(_ c: Overdraft.Card) -> Bool {
        if view.held { return false }
        if view.yourTurn { return view.legal.contains(c.id) && (view.drawn == nil || view.drawn == c.id) }
        return view.jump.contains(c.id)
    }
}

/// Another player's seat: face, name, how many cards, whose turn, a bot, away.
struct SeatCard: View {
    @ScaledMetric(relativeTo: .headline) private var face: CGFloat = 58
    let seat: Overdraft.Seat
    let turn: Bool
    let owner: Bool
    let endsAt: Double?
    /// Cards this seat just gained (a draw, a +2 or +4, a train), shown as "+2" for a moment.
    var gained: Int? = nil
    var body: some View {
        let bot = seat.name.hasSuffix(" (bot)") && !seat.held
        VStack(spacing: 6) {
            FaceView(face: seat.face, size: face, dimmed: !seat.connected)
                .overlay(Circle().stroke(turn ? T2P.gold : .clear, lineWidth: 3).padding(-3))
                .overlay(Circle().stroke(style: StrokeStyle(lineWidth: 2, dash: [4, 3])).foregroundStyle(seat.connected ? .clear : T2P.muted).padding(-4))
                .overlay(alignment: .topTrailing) {
                    if let g = gained {
                        Text("+\(g)").font(.caption.weight(.heavy)).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(T2P.ember, in: Capsule())
                            .offset(x: 10, y: -6)
                            .transition(AnyTransition.scale(scale: 0.4).combined(with: .opacity))
                            .accessibilityHidden(true)
                    }
                }
            HStack(spacing: 4) {
                Text(RoomPlayer.stripBot(seat.name)).font(.subheadline.weight(.semibold)).foregroundStyle(T2P.text).lineLimit(1)
                if owner { Image(systemName: "crown.fill").font(.caption2).foregroundStyle(T2P.gold) }
                if bot { Tag(text: "BOT") }
                if !seat.connected { Tag(text: "AWAY") }
            }
            Text(seat.held ? "Bot holding · \(seat.cards)" : "\(seat.cards) card\(seat.cards == 1 ? "" : "s")")
                .font(.caption).foregroundStyle(T2P.muted)
                .contentTransition(.numericText())
                .animation(.default, value: seat.cards)
        }
        .padding(10)
        .frame(minWidth: 104)
        .background(.white.opacity(turn ? 0.10 : 0.05), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(turn ? T2P.gold.opacity(0.6) : .white.opacity(0.08)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(RoomPlayer.stripBot(seat.name))\(bot ? ", bot" : "")\(owner ? ", owner" : ""), \(seat.cards) cards\(seat.connected ? "" : ", away")\(seat.held ? ", a bot is holding the seat" : "")\(turn ? ", their turn" : "")")
    }
}

/// The turn's clock, counting down to the room's own deadline.
struct TurnClock: View {
    let endsAt: Double   // ms since 1970, the room's
    let total: Double
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let left = max(0, endsAt / 1000 - ctx.date.timeIntervalSince1970)
            ZStack {
                Circle().stroke(.white.opacity(0.15), lineWidth: 5)
                Circle().trim(from: 0, to: min(1, left / total)).stroke(left < 10 ? T2P.ember : T2P.gold, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(left.rounded(.up)))").font(.title3.monospacedDigit().bold()).foregroundStyle(T2P.text)
                    .lineLimit(1).minimumScaleFactor(0.5).padding(6)
            }
            .frame(width: 56, height: 56)
            .accessibilityLabel("\(Int(left.rounded(.up))) seconds left")
        }
    }
}

/// The bar over a table: leave, the game and room, and the room's menu.
struct TableTopBar: View {
    let game: Game; let code: String; let line: String
    var onLeave: () -> Void
    let owner: Bool
    @ObservedObject var room: RoomModel
    @State private var confirmEnd = false
    var body: some View {
        HStack {
            Button(action: onLeave) {
                Image(systemName: "chevron.left").font(.headline).foregroundStyle(T2P.text)
                    .frame(width: 44, height: 44).background(Color.primary.opacity(0.08), in: Circle())
            }
            .accessibilityLabel("Leave").accessibilityIdentifier("leave")
            // the same width on the left as How to play takes on the right, so the title stays centered
            if game.howTo(room.view) != nil { Color.clear.frame(width: 44, height: 44).accessibilityHidden(true) }
            Spacer()
            VStack(spacing: 2) {
                Text(game.title).font(.headline).foregroundStyle(T2P.text)
                Text(room.offline ? "PRACTICE · \(line)" : "ROOM \(code) · \(line)").font(.caption.weight(.semibold)).tracking(1).foregroundStyle(T2P.muted)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            HowToButton(game: game, view: room.view)
            Menu {
                if !room.offline { ShareLink(item: room.inviteLink) { Label("Invite people", systemImage: "square.and.arrow.up") } }
                if owner { Button("End the room", role: .destructive) { confirmEnd = true } }
                Button("Leave", role: .destructive, action: onLeave)
            } label: {
                Image(systemName: "ellipsis").font(.headline).foregroundStyle(T2P.text)
                    .frame(width: 44, height: 44).background(Color.primary.opacity(0.08), in: Circle())
            }
            .accessibilityLabel("Room menu")
        }
        .padding(.horizontal, 16).padding(.top, 6)
        .confirmationDialog("End the room for everyone?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End the room", role: .destructive) { room.send(Out.close) }
            Button("Keep playing", role: .cancel) {}
        }
    }
}

/// The four preset reactions. Nothing typed, ever.
struct ReactionBar: View {
    @ObservedObject var room: RoomModel
    @State private var tv = false
    var body: some View {
        HStack(spacing: 8) {
            ForEach(Reaction.allCases) { r in
                Button(r == .gg ? "GG" : r.words) { room.react(r) }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(T2P.text)
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .background(Color.primary.opacity(0.08), in: Capsule())
                    .accessibilityLabel("Send \(r.words)")
            }
            Spacer(minLength: 0)
            if !room.offline {
                Button { tv = true } label: { Image(systemName: "tv").font(.headline) }
                    .foregroundStyle(T2P.text).frame(width: 44, height: 44).background(Color.primary.opacity(0.08), in: Circle())
                    .accessibilityLabel("Show on TV").accessibilityIdentifier("show-on-tv")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .sheet(isPresented: $tv) { ShowOnTV() }
    }
}

/// A hand won (#489): who went out and with what, everyone's cards left, and what next. For the owner, Play again
/// and Back to the lobby; for everyone, Back to Library.
struct HandOver: View {
    @ObservedObject var room: RoomModel
    @EnvironmentObject var app: AppModel
    let view: Overdraft.View
    var body: some View {
        let t = view.table
        let winner = t?.winner
        let me = winner == view.me.id
        let w = t?.seats.first { $0.id == winner }
        let name = w.map { RoomPlayer.stripBot($0.name) } ?? "Someone"
        let rest = (t?.seats ?? []).filter { $0.id != winner }.sorted { $0.cards < $1.cards }
        // the card as it is when it fits the screen; scrolling only when it doesn't (ten at a table, the largest text)
        ViewThatFits(in: .vertical) {
            card(t: t, winner: winner, me: me, w: w, name: name, rest: rest).padding(28)
            ScrollView { card(t: t, winner: winner, me: me, w: w, name: name, rest: rest).padding(28) }
        }
        .frame(maxWidth: 440)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.35))
        .onAppear { if me { Haptics.yourTurn() } else { Haptics.play() } }
    }

    private var ownerName: String {
        view.table?.seats.first(where: { $0.id == view.owner }).map { RoomPlayer.stripBot($0.name) } ?? "the room’s owner"
    }

    @ViewBuilder private func card(t: Overdraft.Table?, winner: String?, me: Bool, w: Overdraft.Seat?, name: String, rest: [Overdraft.Seat]) -> some View {
        VStack(spacing: 14) {
            if let w { FaceView(face: w.face, size: 76).overlay(Circle().stroke(T2P.gold, lineWidth: 3).padding(-3)) }
            else { Image(systemName: "flag.checkered").font(.system(size: 44)).foregroundStyle(T2P.gold).accessibilityHidden(true) }
            Text(me ? "You win!" : "\(name) wins").font(.largeTitle.bold()).foregroundStyle(T2P.text)
                .accessibilityIdentifier("hand-over")
            if let top = t?.top {
                Text("\(me ? "You" : name) played the last card: \(top.label).").foregroundStyle(T2P.muted).multilineTextAlignment(.center)
            }
            VStack(spacing: 0) {
                ForEach(rest) { s in
                    HStack(spacing: 12) {
                        FaceView(face: s.face, size: 34)
                        Text(s.id == view.me.id ? "You" : RoomPlayer.stripBot(s.name)).font(.headline).foregroundStyle(T2P.text)
                        Spacer()
                        Text("\(s.cards) card\(s.cards == 1 ? "" : "s") left").font(.subheadline.monospacedDigit()).foregroundStyle(T2P.muted)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .accessibilityElement(children: .combine)
                }
            }
            .background(T2P.panel.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
            if room.isOwner {
                Button("Play again") { room.send(Out.again); room.send(Out.deal); Haptics.play() }.buttonStyle(GoldButtonStyle())
                    .accessibilityIdentifier("play-again")
                Button("Back to the lobby") { room.send(Out.again) }.buttonStyle(QuietButtonStyle())
            } else {
                Text("Waiting for \(ownerName) to deal again.").foregroundStyle(T2P.muted).multilineTextAlignment(.center)
            }
            Button("Back to Library") { room.leave(); app.closeRoom(); app.tab = .library }
                .font(.headline).foregroundStyle(T2P.goldText).frame(minHeight: 44)
                .accessibilityIdentifier("back-to-library")
        }
    }
}
