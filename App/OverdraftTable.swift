import SwiftUI
import T2PCore

/// Overdraft with no host screen (#400): everyone else's seats across the top, the piles in the middle, your hand
/// along the bottom. The room decides what can go (legal, jump); this screen only draws it and sends taps.
struct OverdraftTableView: View {
    @ObservedObject var room: RoomModel
    let view: Overdraft.View
    var onLeave: () -> Void
    @State private var wild: Overdraft.Card?
    @State private var wildJump = false
    @State private var lastLine: String?
    @Environment(\.horizontalSizeClass) private var hsize

    private var table: Overdraft.Table { view.table! }
    private var others: [Overdraft.Seat] { table.seats.filter { $0.id != view.me.id } }
    private var name: (String?) -> String { { id in id == view.me.id ? "you" : table.seats.first { $0.id == id }.map { RoomPlayer.stripBot($0.name) } ?? "someone" } }

    var body: some View {
        VStack(spacing: 0) {
            TableTopBar(game: room.game, code: room.code, line: topLine, onLeave: onLeave, owner: room.isOwner, room: room)
            seatsRow
            Spacer(minLength: 8)
            statusLine
            piles
            Spacer(minLength: 8)
            turnHeader
            HandView(view: view, onTap: tap)
                .frame(height: hsize == .regular ? 230 : 172)
            if view.drawn != nil && view.yourTurn {
                Button("Keep it and end my turn") { room.move("hold"); Haptics.select() }
                    .buttonStyle(QuietButtonStyle()).padding(.top, 4)
                    .accessibilityIdentifier("keep")
            }
            ReactionBar(room: room)
        }
        .overlay { if table.over || view.phase == "done" { HandOver(room: room, view: view) } }
        // a card table can't reflow like a list: its words grow to the largest standard size, and VoiceOver reads all of it
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .confirmationDialog("Pick the suit", isPresented: Binding(get: { wild != nil }, set: { if !$0 { wild = nil } }), titleVisibility: .visible) {
            ForEach(Overdraft.suits, id: \.self) { s in
                Button(Overdraft.suitNames[s] ?? s) { if let c = wild { send(c, suit: s, jump: wildJump) }; wild = nil }
            }
            Button("Cancel", role: .cancel) { wild = nil }
        }
        .onChange(of: view.yourTurn) { _, mine in if mine { Haptics.yourTurn() } }
        .onChange(of: TurnKey(seq: table.seq, turn: table.turn)) { old, new in
            // who just played what: whoever's turn it was before this play, or the one who jumped in
            if new.seq > old.seq, let top = table.top {
                let who = table.jumpBy.map { name($0) } ?? name(old.turn)
                lastLine = "\(who.prefix(1).uppercased() + who.dropFirst()) played \(top.label)"
                if who != "you" { Haptics.play() }
            }
        }
    }

    private struct TurnKey: Equatable { let seq: Int; let turn: String? }

    private var topLine: String {
        if table.over { return "HAND OVER" }
        return view.yourTurn ? "YOUR TURN" : "\(name(table.turn).uppercased())’S TURN"
    }

    private var seatsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(others) { s in SeatCard(seat: s, turn: table.turn == s.id, owner: view.owner == s.id, endsAt: table.turnEndsAt) }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder private var statusLine: some View {
        let next = table.turn.map { name($0) } ?? ""
        let text = [lastLine, table.over ? nil : (table.taking ? "the room takes the train for \(next)" : "next: \(next)")].compactMap { $0 }.joined(separator: " · ")
        if !text.isEmpty {
            Text(text)
                .font(.subheadline.weight(.semibold)).foregroundStyle(T2P.text)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.black.opacity(0.35), in: Capsule())
                .accessibilityIdentifier("status-line")
        }
    }

    private var piles: some View {
        HStack(spacing: 28) {
            Button { if view.yourTurn && view.drawn == nil { room.move("draw"); Haptics.play() } else { Haptics.nope() } } label: {
                VStack(spacing: 6) {
                    CardImage(name: "card_back", width: hsize == .regular ? 130 : 96)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(view.yourTurn && view.drawn == nil ? T2P.gold : .clear, lineWidth: 3))
                    Text("\(table.drawLeft) left").font(.footnote).foregroundStyle(T2P.muted)
                }
            }
            .accessibilityLabel(view.yourTurn && view.drawn == nil ? "Draw a card" : "Draw pile, \(table.drawLeft) left")
            .accessibilityIdentifier("draw")
            ZStack {
                ForEach(Array(table.pile.dropLast().enumerated()), id: \.offset) { i, c in
                    CardImage(name: c.artName, width: hsize == .regular ? 130 : 96)
                        .rotationEffect(.degrees(Double(((c.k ?? i) * 37) % 17) - 8))
                        .offset(x: CGFloat(((c.k ?? i) * 13) % 9) - 4)
                }
                if let top = table.top {
                    CardImage(name: top.artName, width: hsize == .regular ? 140 : 104)
                        .shadow(radius: 8)
                        .accessibilityLabel("On the table: \(top.spoken)\(top.isWild ? ", \(Overdraft.suitNames[table.suit ?? ""] ?? "") named" : "")")
                }
                if let s = table.suit, table.top?.isWild == true {
                    Circle().fill(T2P.suit[s] ?? .gray).frame(width: 26, height: 26).overlay(Circle().stroke(.white, lineWidth: 2))
                        .offset(x: 46, y: -66).accessibilityHidden(true)
                }
                if table.stack > 0 {
                    Text("+\(table.stack)").font(.title.bold()).foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4).background(T2P.ember, in: Capsule())
                        .offset(y: 70).accessibilityLabel("A train of \(table.stack) cards")
                }
            }
        }
    }

    private var turnHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                if view.held {
                    Text("A bot is playing for you").font(.title3.bold()).foregroundStyle(T2P.text)
                    Text("Your seat is yours again at the next turn.").font(.subheadline).foregroundStyle(T2P.muted)
                } else if view.yourTurn {
                    Text("Your turn").font(.title.bold()).foregroundStyle(T2P.text).accessibilityIdentifier("your-turn")
                    Text(turnDetail).font(.subheadline).foregroundStyle(T2P.muted)
                } else {
                    Text("\(view.hand.count) cards").font(.title3.bold()).foregroundStyle(T2P.text)
                    Text(view.jump.isEmpty ? "Waiting for \(name(table.turn))" : "Jump in: you hold the same card").font(.subheadline)
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
    var onTap: (Overdraft.Card) -> Void
    @Environment(\.horizontalSizeClass) private var hsize

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
                        Button { onTap(c) } label: {
                            CardImage(name: c.artName, width: w)
                                .overlay(RoundedRectangle(cornerRadius: w / 14).stroke(ok ? T2P.gold : .clear, lineWidth: 3))
                                .shadow(color: ok ? T2P.gold.opacity(0.5) : .black.opacity(0.4), radius: ok ? 8 : 3)
                                .brightness(ok || !view.yourTurn ? 0 : -0.12)
                        }
                        .buttonStyle(.plain)
                        .offset(x: CGFloat(i) * step, y: ok ? -16 : 0)
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
    var body: some View {
        let bot = seat.name.hasSuffix(" (bot)") && !seat.held
        VStack(spacing: 6) {
            FaceView(face: seat.face, size: face, dimmed: !seat.connected)
                .overlay(Circle().stroke(turn ? T2P.gold : .clear, lineWidth: 3).padding(-3))
                .overlay(Circle().stroke(style: StrokeStyle(lineWidth: 2, dash: [4, 3])).foregroundStyle(seat.connected ? .clear : T2P.muted).padding(-4))
            HStack(spacing: 4) {
                Text(RoomPlayer.stripBot(seat.name)).font(.subheadline.weight(.semibold)).foregroundStyle(T2P.text).lineLimit(1)
                if owner { Image(systemName: "crown.fill").font(.caption2).foregroundStyle(T2P.gold) }
                if bot { Tag(text: "BOT") }
                if !seat.connected { Tag(text: "AWAY") }
            }
            Text(seat.held ? "Bot holding · \(seat.cards)" : "\(seat.cards) card\(seat.cards == 1 ? "" : "s")")
                .font(.caption).foregroundStyle(T2P.muted)
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
            Spacer()
            VStack(spacing: 2) {
                Text(game.title).font(.headline).foregroundStyle(T2P.text)
                Text(room.offline ? "PRACTICE · \(line)" : "ROOM \(code) · \(line)").font(.caption.weight(.semibold)).tracking(1).foregroundStyle(T2P.muted)
            }
            .accessibilityElement(children: .combine)
            Spacer()
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

/// A hand won: who won, and for the owner, Play again.
struct HandOver: View {
    @ObservedObject var room: RoomModel
    let view: Overdraft.View
    var body: some View {
        let t = view.table
        let winner = t?.winner
        let me = winner == view.me.id
        let name = t?.seats.first { $0.id == winner }.map { RoomPlayer.stripBot($0.name) } ?? "Someone"
        VStack(spacing: 14) {
            Image(systemName: me ? "trophy.fill" : "flag.checkered").font(.system(size: 44)).foregroundStyle(T2P.gold).accessibilityHidden(true)
            Text(me ? "You win!" : "\(name) wins").font(.largeTitle.bold()).foregroundStyle(T2P.text)
                .accessibilityIdentifier("hand-over")
            Text("\(view.hand.count) card\(view.hand.count == 1 ? "" : "s") left in your hand").foregroundStyle(T2P.muted)
            if room.isOwner {
                Button("Play again") { room.send(Out.again); room.send(Out.deal); Haptics.play() }.buttonStyle(GoldButtonStyle())
                    .accessibilityIdentifier("play-again")
                Button("Back to the lobby") { room.send(Out.again) }.buttonStyle(QuietButtonStyle())
            } else {
                Text("Waiting for \(room.ownerName ?? "the room’s owner") to deal again.").foregroundStyle(T2P.muted)
            }
        }
        .padding(28)
        .frame(maxWidth: 420)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .padding(24)
        .onAppear { if me { Haptics.yourTurn() } }
    }
}
