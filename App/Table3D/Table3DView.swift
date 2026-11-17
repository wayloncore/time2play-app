import SwiftUI
import T2PCore

/// Overdraft at a true 3D table (#496): a glass stadium table seen from your seat at its near end, the element's
/// scene under and behind it, everyone else round the rim in turn order, your hand as a fan along the bottom.
/// The room decides what can go; this screen draws it and sends taps, like the 2D table (OverdraftTableView).
/// `room` is nil in still mode (screenshots with a made-up table).
struct Table3DView: View {
    var room: RoomModel?
    let view: Overdraft.View
    var onLeave: () -> Void
    var still: Table3DStill? = nil

    @StateObject private var stage = Table3DStage()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var hsize

    @State private var feed: [String] = []
    @State private var flash: Flash?
    @State private var gained: [String: Int] = [:]
    @State private var hitNote: String?
    @State private var dealt: Int?
    @State private var showOver = false
    @State private var wild: Overdraft.Card?
    @State private var wildJump = false
    @State private var confirmEnd = false
    @State private var headerBottom: CGFloat = 100
    @State private var bottomTop: CGFloat = 520
    @State private var tray: CGRect = .zero
    @State private var lastThrow: (x: Double, y: Double, roll: Double, w: Double)?
    @State private var arriving: Set<String> = []
    @State private var nameShown: String?
    @State private var started = false

    struct Flash: Identifiable, Equatable { let id = UUID(); let icon: String; let word: String; let detail: String }

    private var table: Overdraft.Table { view.table! }
    private var me: String { view.me.id }
    /// Everyone else, in turn order from you: the first seat is the one play reaches after yours (direction 1).
    private var others: [Overdraft.Seat] { Self.others(table, me: me) }
    static func others(_ t: Overdraft.Table, me: String) -> [Overdraft.Seat] {
        let seats = t.seats
        guard let i = seats.firstIndex(where: { $0.id == me }), seats.count > 1 else { return seats.filter { $0.id != me } }
        return (1..<seats.count).map { seats[(i + $0) % seats.count] }
    }
    private func name(_ id: String?) -> String {
        id == me ? "you" : table.seats.first { $0.id == id }.map { RoomPlayer.stripBot($0.name) } ?? "someone"
    }
    private func cap(_ id: String?) -> String { let n = name(id); return n.prefix(1).uppercased() + n.dropFirst() }
    private var suit: String? { table.suit ?? table.top?.suit }

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .top) {
                Table3DSceneHost(stage: stage).ignoresSafeArea()
                scrims.ignoresSafeArea().allowsHitTesting(false)
                overTable.ignoresSafeArea()
                hud
                if showOver, let room { HandOver(room: room, view: view).transition(.opacity) }
            }
            .onAppear { appeared(g) }
            .onChange(of: g.size) { _, _ in refit(g) }
            .onChange(of: headerBottom) { _, _ in refit(g) }
            .onChange(of: bottomTop) { _, _ in refit(g) }
            .onChange(of: table.seats.count) { _, _ in refit(g) }
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .animation(.easeInOut(duration: 0.3), value: showOver)
        .confirmationDialog("Pick the suit", isPresented: Binding(get: { wild != nil }, set: { if !$0 { wild = nil } }), titleVisibility: .visible) {
            ForEach(Overdraft.suits, id: \.self) { s in
                Button(Overdraft.suitNames[s] ?? s) { if let c = wild { send(c, suit: s, jump: wildJump) }; wild = nil }
            }
            Button("Cancel", role: .cancel) { wild = nil }
        }
        .confirmationDialog("End the room for everyone?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End the room", role: .destructive) { room?.send(Out.close) }
            Button("Keep playing", role: .cancel) {}
        }
        .onChange(of: view.yourTurn) { _, mine in if mine { Haptics.yourTurn() } }
        .onChange(of: view.table) { old, new in if let new { changed(from: old, to: new) } }
        .onChange(of: view.hand) { old, new in handChanged(from: old, to: new) }
        .onChange(of: stage.layout) { _, _ in sync(table) }
        .onChange(of: reduceMotion) { _, r in stage.world.post { [world = stage.world] in world.reduced = r } }
    }

    // MARK: the layers

    private var scrims: some View {
        ZStack {
            RadialGradient(colors: [.clear, Color(hex: 0x05040A).opacity(0.55)], center: .center, startRadius: 220, endRadius: 560)
            VStack(spacing: 0) {
                LinearGradient(colors: [Color(hex: 0x07060C).opacity(0.55), Color(hex: 0x07060C).opacity(0.32), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: headerBottom + 10)
                Spacer()
                LinearGradient(colors: [.clear, Color(hex: 0x07060C).opacity(0.72), Color(hex: 0x07060C).opacity(0.95)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 380)
            }
        }
    }

    /// Faces, counts and names over the seats; the suit between the piles; a tap on the draw pile draws.
    @ViewBuilder private var overTable: some View {
        if let l = stage.layout {
            ZStack(alignment: .topLeading) {
                Color.clear
                ForEach(Array(others.enumerated()), id: \.element.id) { i, s in
                    if l.seats.indices.contains(i) {
                        let p = l.screen(l.seats[i])
                        SeatBillboard(seat: s, spec: l.seats[i], k: p.k, turn: table.turn == s.id && !table.over,
                                      endsAt: table.turnEndsAt, gained: gained[s.id], owner: view.owner == s.id,
                                      showName: nameShown == s.id)
                            .position(x: p.x, y: p.y)
                            .onTapGesture { if l.seats[i].compact { showName(s.id) } }
                    }
                }
                if let deck = stage.screen(T3Vec(0, 0.1, Table3D.deckAt.z + Table3D.cardH / 2 + 0.06)) {
                    Color.clear.contentShape(Rectangle())
                        .frame(width: 90, height: 80)
                        .position(deck)
                        .onTapGesture { drawTapped() }
                        .accessibilityHidden(true)
                }
                if let s = suit, let a = stage.screen(T3Vec(0, Double(Table3D.deckCards) * Table3D.cardT, Table3D.deckAt.z + Table3D.cardH / 2 + 0.04)),
                   let b = stage.screen(T3Vec(0, 0.1, Table3D.pileAt.z - Table3D.cardH / 2 - 0.12)) {
                    SuitChip(suit: s, named: table.top?.isWild == true)
                        .position(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                }
                if table.stack > 0, let p = stage.screen(T3Vec(0, 0.1, Table3D.pileAt.z + Table3D.cardH / 2 + 0.25)) {
                    Text("+\(table.stack)").font(.title.bold()).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 4).background(T2P.ember, in: Capsule())
                        .position(p)
                        .accessibilityLabel("A train of \(table.stack) cards")
                }
                if let f = flash {
                    flashCard(f).position(x: l.width / 2, y: bandY(l)).id(f.id)
                }
                Text(stage.frozen ? "ready" : "").font(.system(size: 2)).opacity(0.02)
                    .accessibilityIdentifier(stage.frozen ? "od3d-ready" : "od3d-wait")
                    .position(x: 2, y: 2)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("table-3d")
        }
    }

    /// The band between the horizon and the far seats: where big moments show, clear of the table.
    private func bandY(_ l: Table3DLayout) -> Double {
        let tops = l.seats.map { l.screen($0) }.map { $0.y - 0.6 * $0.k }
        let far = tops.min() ?? (l.horizonY + 80)
        return max(l.horizonY + 44, min(far - 10, (l.horizonY + far) / 2 + 20))
    }

    private func flashCard(_ f: Flash) -> some View {
        VStack(spacing: 4) {
            Image(systemName: f.icon).font(.system(size: 30, weight: .bold)).foregroundStyle(T2P.gold)
            Text(f.word).font(.title2.bold()).foregroundStyle(T2P.text)
            Text(f.detail).font(.subheadline.weight(.semibold)).foregroundStyle(T2P.muted)
        }
        .padding(.horizontal, 22).padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(T2P.gold.opacity(0.5)))
        .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.scale(scale: 0.6).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("od-flash")
    }

    private var hud: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                Text(feed.first ?? " ").font(.footnote).foregroundStyle(Color(hex: 0xCFC3D3))
                    .shadow(color: .black, radius: 3)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .padding(.horizontal, 12).padding(.bottom, 6)
                    .accessibilityLabel(feed.first ?? "")
                    .accessibilityIdentifier("od-feed")
            }
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { headerBottom = $0 }
            Spacer(minLength: 0)
            bottom
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { bottomTop = $0 }
        }
    }

    private var titleText: String {
        if table.over { return "Hand over" }
        if view.yourTurn { return table.stack > 0 ? "You’re on the hook: +\(table.stack)" : "Your turn" }
        if view.held { return "A bot is playing for you" }
        return table.stack > 0 ? "\(cap(table.turn)) is on the hook" : "\(cap(table.turn))’s turn"
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle().fill(Color(hex: 0xF5DE95)).frame(width: 9, height: 9).shadow(color: T2P.gold, radius: 5)
            Text(titleText)
                .font(.system(size: 20, weight: .semibold)).foregroundStyle(T2P.text)
                .lineLimit(1).minimumScaleFactor(0.6).shadow(color: .black, radius: 3)
                .accessibilityIdentifier(table.over ? "table-over" : view.yourTurn ? "your-turn" : "their-turn")
            if !table.over, let ends = table.turnEndsAt { ClockPill(endsAt: ends) }
            Spacer(minLength: 4)
            if let room {
                HowToButton(game: room.game, view: room.view)
                Menu {
                    if !room.offline { ShareLink(item: room.inviteLink) { Label("Invite people", systemImage: "square.and.arrow.up") } }
                    Section("Send") { ForEach(Reaction.allCases) { r in Button(r == .gg ? "GG" : r.words) { room.react(r) } } }
                    if room.isOwner { Button("End the room", role: .destructive) { confirmEnd = true } }
                } label: {
                    Image(systemName: "ellipsis").font(.headline).foregroundStyle(T2P.text)
                        .frame(width: 44, height: 44).background(Color(hex: 0x14101C).opacity(0.7), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.17)))
                }
                .accessibilityLabel("Room menu")
            }
            Button(action: onLeave) {
                Text("Leave").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color(hex: 0xD9CFDC))
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .background(Color(hex: 0x14101C).opacity(0.7), in: Capsule()).overlay(Capsule().stroke(.white.opacity(0.17)))
            }
            .accessibilityIdentifier("leave")
        }
        .padding(.leading, 16).padding(.trailing, 12).padding(.top, 4)
    }

    private var handDetail: String {
        if view.held { return "Your seat is yours again at the next turn" }
        if view.yourTurn {
            if view.drawn != nil { return view.legal.isEmpty ? "No luck: keep it" : "Play it, or keep it" }
            if table.stack > 0 { return table.taking || view.legal.isEmpty ? "Taking +\(table.stack)…" : "Pass it on with a +2 or +4" }
            if let h = hitNote { return h }
            let n = view.legal.count
            return n == 0 ? "Nothing can go: draw" : "\(n) can go"
        }
        if !view.jump.isEmpty { return "Jump in: you hold the same card" }
        return "\(view.hand.count) card\(view.hand.count == 1 ? "" : "s")"
    }

    private var canDraw: Bool { view.yourTurn && view.drawn == nil && table.stack == 0 && !table.over }

    private var bottom: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your hand").font(.system(size: 15, weight: .semibold)).foregroundStyle(T2P.text)
                Spacer()
                Text(handDetail).font(.footnote).foregroundStyle(view.yourTurn || !view.jump.isEmpty ? Color(hex: 0xF5DE95) : Color(hex: 0xC9BCCD))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .shadow(color: .black, radius: 3)
            .padding(.horizontal, 18)
            HandFan3D(view: view, dealt: dealt, arriving: arriving, onTap: tap)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(colors: [(T2P.suit[suit ?? "wave"] ?? .blue).opacity(0.14).blendedOver(Color(hex: 0x1A1422).opacity(0.85)), Color(hex: 0x120E19).opacity(0.9)],
                                   startPoint: .top, endPoint: .bottom),
                    in: UnevenRoundedRectangle(topLeadingRadius: 26, bottomLeadingRadius: 16, bottomTrailingRadius: 16, topTrailingRadius: 26))
                .overlay(UnevenRoundedRectangle(topLeadingRadius: 26, bottomLeadingRadius: 16, bottomTrailingRadius: 16, topTrailingRadius: 26)
                    .stroke(view.yourTurn ? T2P.gold.opacity(0.8) : .white.opacity(0.11), lineWidth: view.yourTurn ? 1.5 : 1))
                .shadow(color: view.yourTurn ? T2P.gold.opacity(0.45) : .black.opacity(0.5), radius: view.yourTurn ? 14 : 12, y: view.yourTurn ? 0 : 8)
                .padding(.horizontal, 12).padding(.top, 6)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { tray = $0 }
            if view.drawn != nil && view.yourTurn {
                Button { room?.move("hold"); Haptics.select() } label: { Text("Keep it and end my turn").frame(maxWidth: .infinity) }
                    .buttonStyle(DrawButtonStyle(on: true, gold: false))
                    .padding(.horizontal, 16).padding(.top, 10)
                    .accessibilityIdentifier("keep")
            } else {
                Button { drawTapped() } label: { Text("Draw").frame(maxWidth: .infinity) }
                    .buttonStyle(DrawButtonStyle(on: canDraw, gold: true))
                    .disabled(!canDraw)
                    .padding(.horizontal, 16).padding(.top, 10)
                    .accessibilityLabel(canDraw ? "Draw a card" : "Draw pile, \(table.drawLeft) left")
                    .accessibilityIdentifier("draw")
            }
        }
        .frame(maxWidth: 560)
        .padding(.bottom, 6)
    }

    // MARK: fitting the table to the screen

    private func refit(_ g: GeometryProxy) {
        let full = g.frame(in: .global)
        let w = Double(full.width + g.safeAreaInsets.leading + g.safeAreaInsets.trailing)
        let h = Double(full.height + g.safeAreaInsets.top + g.safeAreaInsets.bottom)
        let free = T3Rect(x0: 6, y0: Double(headerBottom) + 6, x1: w - 6, y1: max(Double(headerBottom) + 126, Double(bottomTop) - 6))
        let labels = others.map { Table3DStage.labelUnits(RoomPlayer.stripBot($0.name), bot: $0.name.hasSuffix(" (bot)") && !$0.held) }
        stage.fit(width: w, height: h, free: free, players: table.seats.count, labels: labels, counts: others.map(\.cards))
    }

    private func appeared(_ g: GeometryProxy) {
        let world = stage.world, r = reduceMotion
        world.post { world.reduced = r }
        if let st = still { world.autoStepDown = false; st.run(world) }
        DispatchQueue.main.async { refit(g) }
        if started { return }
        started = true
        if table.over { if room != nil { showOver = true }; return }
        let fresh = (table.top?.k ?? 0) == 0 && table.seats.allSatisfy { $0.cards == view.hand.count }
        if fresh && still == nil { deal() } else if let top = table.top {
            say(table.turn == me ? "Your turn: match \(top.label)" : "\(cap(table.turn)) to play on \(top.label)")
        }
    }

    // MARK: the scene follows the table

    /// Where a seat sits round the rim (you are at 0).
    private func rimS(_ id: String?) -> Double? {
        guard let id, let l = stage.layout else { return nil }
        if id == me { return 0 }
        guard let i = others.firstIndex(where: { $0.id == id }), l.seats.indices.contains(i) else { return nil }
        return l.seats[i].s
    }

    private func sync(_ t: Overdraft.Table) {
        let world = stage.world
        let counts = Self.others(t, me: me).map(\.cards)
        let pile = t.pile.map { (k: $0.k ?? 0, art: $0.artName) }
        let s = t.suit ?? t.top?.suit
        let mine = view.yourTurn && view.drawn == nil && !t.over
        var arrow: (Double, Double, Int)?
        if !t.over, let turn = t.turn, let i = t.seats.firstIndex(where: { $0.id == turn }), t.seats.count > 1 {
            let d = t.direction >= 0 ? 1 : -1, n = t.seats.count
            let next = t.seats[((i + d) % n + n) % n].id
            if let a = rimS(turn), let b = rimS(next) { arrow = (a, b, d) }
        }
        world.post {
            world.setCounts(counts)
            world.setDeck(left: t.drawLeft)
            world.setPile(pile)
            if let s { world.setSuit(s) }
            world.setMyTurn(mine)
            if let a = arrow { world.setArrow(from: a.0, to: a.1, dir: a.2) } else { world.hideArrow() }
        }
    }

    private func changed(from old: Overdraft.Table?, to new: Overdraft.Table) {
        if old?.turn != new.turn && new.turn != me { hitNote = nil }
        let moves = Overdraft.moves(from: old, to: new)
        for m in moves { if let line = words(m, new) { say(line) } }
        let seatsNow = Self.others(new, me: me)
        let world = stage.world
        for m in moves {
            switch m {
            case let .played(by, card, _):
                let k = card.k ?? new.seq, art = card.artName
                if by == me {
                    let t = lastThrow ?? (x: Double(tray.midX), y: Double(tray.midY), roll: 0, w: 96)
                    world.post { world.throwFromScreen(x: t.x, y: t.y, cardPoints: t.w, roll: t.roll, art: art, k: k) }
                    lastThrow = nil
                } else if let i = seatsNow.firstIndex(where: { $0.id == by }) {
                    world.post { world.throwFromSeat(i, art: art, k: k) }
                }
            case let .drew(who, n), let .hit(who, n, _, _), let .tookTrain(who, n):
                if who != me {
                    bump(who, n)
                    if let i = seatsNow.firstIndex(where: { $0.id == who }) { world.post { world.drawToSeat(i, count: n) } }
                }
            default: break
            }
        }
        if let big = moves.last(where: \.isBig) { show(big) }
        if moves.contains(where: { if case let .hit(who, _, _, _) = $0 { return who == me }; if case let .tookTrain(who, _) = $0 { return who == me }; return false }) {
            Haptics.nope()
        }
        sync(new)
        if old?.over == true && !new.over { showOver = false; deal(); return }   // Play again, dealt in place
        if new.over && !(old?.over ?? true) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { if table.over && room != nil { showOver = true } }
        } else if !new.over && showOver {
            showOver = false
        }
    }

    /// New cards in your hand fly in from the draw pile and drop into the fan as they land.
    private func handChanged(from old: [Overdraft.Card], to new: [Overdraft.Card]) {
        guard dealt == nil, !old.isEmpty else { return }
        let had = Set(old.map(\.id))
        let added = new.filter { !had.contains($0.id) }
        guard !added.isEmpty, tray != .zero else { return }
        if reduceMotion { Haptics.select(); return }
        arriving.formUnion(added.map(\.id))
        let ids = added.map(\.id), arts = added.map(\.artName)
        let w = Double(HandFan3D.cardWidth(width: Double(tray.width), height: Double(UIScreen.main.bounds.height)))
        let world = stage.world, x = Double(tray.midX), y = Double(tray.midY)
        world.post {
            world.drawToScreen(x: x, y: y, cardPoints: w, arts: arts) { j in
                if ids.indices.contains(j) { _ = withAnimation(.spring(duration: 0.28)) { arriving.remove(ids[j]) } }
                Haptics.select()
            }
        }
        // whatever happens, nothing stays hidden
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6 + 0.16 * Double(ids.count) + 0.4) { arriving.subtract(ids) }
    }

    /// The deal: cards fly round to every seat and into your fan, and the line says who goes first.
    private func deal() {
        feed = []; hitNote = nil
        say("Dealt \(view.hand.count) cards each. \(cap(table.turn)) \(table.turn == me ? "go" : "goes") first.")
        let world = stage.world, seats = others
        if reduceMotion { return }
        world.post {
            world.resetShown()
            for (i, s) in seats.enumerated() { world.drawToSeat(i, count: min(s.cards, 7), delay: 0.05 * Double(i)) }
        }
        dealt = 0
        for i in 1...max(1, view.hand.count) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.09 * Double(i)) {
                withAnimation(.spring(duration: 0.3)) { dealt = i }
                if i == view.hand.count { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { dealt = nil } }
                Haptics.select()
            }
        }
    }

    private func words(_ m: Overdraft.Move, _ t: Overdraft.Table) -> String? {
        switch m {
        case let .played(by, card, jump):
            if t.over && t.winner == by { return "\(cap(by)) went out with \(card.label)" }
            return jump ? "\(cap(by)) jumped in with \(card.label)" : "\(cap(by)) played \(card.label)"
        case let .drew(who, n):
            if who == me, n == 1, let d = view.drawn, let c = view.hand.first(where: { $0.id == d }) { return "You drew \(c.label)" }
            return "\(cap(who)) drew \(n == 1 ? "a card" : "\(n) cards")"
        case let .hit(who, n, by, card):
            if who == me { hitNote = "You drew \(n) from \(name(by))’s \(card.label). Still your turn." }
            return "\(cap(who)) drew \(n) from \(by == me ? "your" : "\(name(by))’s") \(card.label)"
        case let .tookTrain(who, n):
            return who == me ? "You took the +\(n) train" : "\(cap(who)) took the +\(n) train"
        case .reversed:
            return "Reverse: play turns around"
        case let .skipped(who, _):
            return who == me ? "You’re skipped" : "\(cap(who)) is skipped"
        }
    }

    private func say(_ text: String) {
        withAnimation(reduceMotion ? nil : Animation.easeOut(duration: 0.25)) {
            feed.insert(text, at: 0)
            if feed.count > 3 { feed.removeLast(feed.count - 3) }
        }
    }

    private func show(_ m: Overdraft.Move) {
        let f: Flash
        switch m {
        case .reversed: f = Flash(icon: "arrow.triangle.2.circlepath", word: "Reverse", detail: "Play turns around")
        case let .skipped(who, _): f = Flash(icon: "nosign", word: "Skipped", detail: who == me ? "You miss a turn" : "\(cap(who)) misses a turn")
        case let .tookTrain(who, n): f = Flash(icon: "rectangle.stack.badge.plus", word: "+\(n) taken", detail: who == me ? "You draw \(n)" : "\(cap(who)) draws \(n)")
        case let .played(by, _, _): f = Flash(icon: "arrow.up.forward", word: "Jump in!", detail: by == me ? "You played the same card" : "\(cap(by)) played the same card")
        default: return
        }
        withAnimation(reduceMotion ? Animation.easeInOut(duration: 0.2) : Animation.spring(duration: 0.3)) { flash = f }
        UIAccessibility.post(notification: .announcement, argument: "\(f.word). \(f.detail)")
        Haptics.select()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { if flash?.id == f.id { withAnimation(.easeOut(duration: 0.3)) { flash = nil } } }
    }

    private func bump(_ id: String, _ n: Int) {
        withAnimation(reduceMotion ? nil : Animation.spring(duration: 0.3)) { gained[id] = n }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { withAnimation(.easeOut(duration: 0.3)) { gained[id] = nil } }
    }

    private func showName(_ id: String) {
        withAnimation(.easeOut(duration: 0.2)) { nameShown = id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { if nameShown == id { withAnimation(.easeOut(duration: 0.2)) { nameShown = nil } } }
    }

    // MARK: taps

    private func drawTapped() {
        guard canDraw else { Haptics.nope(); return }
        room?.move("draw"); Haptics.play()
    }

    private func tap(_ c: Overdraft.Card, _ center: CGPoint, _ roll: Double, _ width: Double) {
        let jump = !view.yourTurn && view.jump.contains(c.id)
        guard (view.yourTurn && view.legal.contains(c.id) && (view.drawn == nil || view.drawn == c.id)) || jump else { Haptics.nope(); return }
        lastThrow = (Double(tray.minX + center.x), Double(tray.minY + center.y), roll, width)
        if c.isWild { wild = c; wildJump = jump; return }
        send(c, suit: nil, jump: jump)
    }

    private func send(_ c: Overdraft.Card, suit: String?, jump: Bool) {
        var f: [String: JSON] = ["card": .string(c.id)]
        if let s = suit { f["suit"] = .string(s) }
        if jump { f["on"] = .number(Double(table.seq)) }
        room?.move(jump ? "jump" : "play", f)
        Haptics.play()
    }
}

private extension Color {
    /// A see-through color laid over another, as one color (the tray's tint).
    func blendedOver(_ base: Color) -> Color {
        let a = UIColor(self), b = UIColor(base)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0, r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1); b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return Color(red: r1 * a1 + r2 * (1 - a1), green: g1 * a1 + g2 * (1 - a1), blue: b1 * a1 + b2 * (1 - a1)).opacity(Double(a2))
    }
}

/// The Draw button: gold when you can draw, dim when you can't; the quiet style for "Keep it".
struct DrawButtonStyle: ButtonStyle {
    let on: Bool
    let gold: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(gold ? (on ? Color(hex: 0x2A1A05) : Color(hex: 0x3B2A14).opacity(0.67)) : T2P.text)
            .frame(minHeight: 48)
            .background(
                Group {
                    if gold && on { LinearGradient(colors: [Color(hex: 0xF0D38A), Color(hex: 0xD4A853), Color(hex: 0xB8893A)], startPoint: .top, endPoint: .bottom) }
                    else if gold { LinearGradient(colors: [Color(hex: 0x7D6A4A), Color(hex: 0x5F4E36)], startPoint: .top, endPoint: .bottom) }
                    else { LinearGradient(colors: [Color(hex: 0x2A2236), Color(hex: 0x1B1524)], startPoint: .top, endPoint: .bottom) }
                }, in: Capsule())
            .overlay(Capsule().stroke(gold ? .clear : .white.opacity(0.2)))
            .shadow(color: gold && on ? Color(hex: 0xD4A853).opacity(0.6) : .clear, radius: 12, y: 6)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

/// The turn's clock in the header, counting down to the room's deadline.
struct ClockPill: View {
    let endsAt: Double
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let left = max(0, Int((endsAt / 1000 - ctx.date.timeIntervalSince1970).rounded(.up)))
            Text(String(format: "%d:%02d", left / 60, left % 60))
                .font(.system(size: 13, weight: .semibold, design: .monospaced)).monospacedDigit()
                .foregroundStyle(left < 10 ? T2P.ember : Color(hex: 0xF5DE95))
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Color(hex: 0x1B140C).opacity(0.8), in: Capsule())
                .overlay(Capsule().stroke(Color(hex: 0xD4A853).opacity(0.4)))
                .accessibilityLabel("\(left) seconds left")
        }
    }
}

/// The suit in play, between the piles.
struct SuitChip: View {
    let suit: String
    var named = false
    static let icon = ["ember": "flame.fill", "wave": "water.waves", "bolt": "bolt.fill", "leaf": "leaf.fill"]
    var body: some View {
        let c = T2P.suit[suit] ?? .gray
        HStack(spacing: 6) {
            Image(systemName: Self.icon[suit] ?? "circle.fill").font(.system(size: 14, weight: .bold))
            Text((Overdraft.suitNames[suit] ?? suit).uppercased()).font(.system(size: 13, weight: .bold)).tracking(0.8)
        }
        .foregroundStyle(.white)
        .padding(.leading, 9).padding(.trailing, 12).padding(.vertical, 5)
        .background(Color(hex: 0x120D18).opacity(0.85), in: Capsule())
        .background(c.opacity(0.34), in: Capsule())
        .overlay(Capsule().stroke(c, lineWidth: 1.5))
        .shadow(color: c.opacity(0.7), radius: 9)
        .animation(.easeInOut(duration: 0.6), value: suit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Suit: \(Overdraft.suitNames[suit] ?? suit)\(named ? ", named" : "")")
        .accessibilityIdentifier("od3d-suit")
    }
}

/// A seat over the rim: the face, the card count, the name (on tap at a big table), a ring on their turn. Sized in
/// world units (`k` points each), so far seats look farther, like the prototype's billboards.
struct SeatBillboard: View {
    let seat: Overdraft.Seat
    let spec: Table3DSeat
    let k: Double
    let turn: Bool
    let endsAt: Double?
    let gained: Int?
    let owner: Bool
    let showName: Bool

    var body: some View {
        let u = CGFloat(spec.scale * k)                 // points per unit for this seat
        let W = CGFloat(spec.w) * u, H = CGFloat(spec.h) * u
        let fx = W / 2 + (spec.compact ? -0.06 * u : 0), fy = H / 2 - CGFloat(spec.faceY) * u, fr = CGFloat(spec.faceR) * u
        let bot = seat.name.hasSuffix(" (bot)") && !seat.held
        let one = seat.cards == 1
        let bw = (seat.cards > 9 ? 0.58 : 0.46) * u, bh = 0.44 * u
        ZStack(alignment: .topLeading) {
            Color.clear.frame(width: W, height: H)
            if turn { TurnRing(endsAt: endsAt).frame(width: fr * 2 * 1.36, height: fr * 2 * 1.36).position(x: fx, y: fy) }
            Circle().fill(Color(hex: 0x17111C)).frame(width: fr * 2, height: fr * 2)
                .shadow(color: .black.opacity(0.7), radius: 0.07 * u, y: 0.023 * u)
                .position(x: fx, y: fy)
            FaceView(face: seat.face, size: max(4, fr * 2 - 0.023 * u), dimmed: !seat.connected)
                .position(x: fx, y: fy)
            Circle().stroke(turn ? Color(hex: 0xF5DE95) : Color(hex: 0xC9A05A), lineWidth: max(1.5, 0.02 * u))
                .frame(width: fr * 2 - 0.02 * u, height: fr * 2 - 0.02 * u).position(x: fx, y: fy)
            Text("\(seat.cards)")
                .font(.system(size: max(6, 0.32 * u), weight: .bold)).foregroundStyle(one ? Color(hex: 0xFFD9B8) : Color(hex: 0xEFE8DA))
                .frame(width: bw, height: bh)
                .background(one ? Color(hex: 0x4A2318) : Color(hex: 0x352639), in: RoundedRectangle(cornerRadius: 0.078 * u))
                .overlay(RoundedRectangle(cornerRadius: 0.078 * u).stroke(one ? T2P.ember : Color(hex: 0x8A6F88), lineWidth: max(1, 0.016 * u)))
                .contentTransition(.numericText())
                .position(x: fx + fr * 0.52 + bw / 2, y: fy - fr - 0.02 * u + bh / 2)
            if let g = gained {
                Text("+\(g)").font(.system(size: max(8, 0.3 * u), weight: .heavy)).foregroundStyle(.white)
                    .padding(.horizontal, 0.12 * u).padding(.vertical, 0.04 * u)
                    .background(T2P.ember, in: Capsule())
                    .position(x: fx - fr * 0.7, y: fy - fr * 0.9)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
            if !spec.compact || showName {
                namePill(u: u, bot: bot)
                    .position(x: W / 2, y: spec.compact ? fy + fr + 0.3 * u : (spec.nameTop ? 0.2734 * u : H - 0.2734 * u))
                    .transition(.opacity)
            }
        }
        .frame(width: W, height: H)
        .contentShape(Circle().inset(by: -0.1 * u).offset(x: fx - W / 2, y: fy - H / 2))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(RoomPlayer.stripBot(seat.name))\(bot ? ", bot" : "")\(owner ? ", owner" : ""), \(seat.cards) card\(seat.cards == 1 ? "" : "s")\(seat.connected ? "" : ", away")\(seat.held ? ", a bot is holding the seat" : "")\(turn ? ", their turn" : "")")
        .accessibilityIdentifier("od3d-seat")
    }

    private func namePill(u: CGFloat, bot: Bool) -> some View {
        HStack(spacing: 0) {
            Text(RoomPlayer.stripBot(seat.name)).font(.system(size: max(7, 0.35 * u), weight: .semibold))
                .foregroundStyle(turn ? Color(hex: 0xF5DE95) : Color(hex: 0xE8DFEB))
            if bot { Text(" bot").font(.system(size: max(6, 0.28 * u), weight: .medium)).foregroundStyle(Color(hex: 0xA99BB0)) }
        }
        .lineLimit(1)
        .padding(.horizontal, 0.15 * u)
        .frame(height: 0.5 * u)
        .background(turn ? Color(hex: 0x2B1F12).opacity(0.95) : Color(hex: 0x1A121E).opacity(0.93), in: RoundedRectangle(cornerRadius: 0.0625 * u))
        .overlay(RoundedRectangle(cornerRadius: 0.0625 * u).stroke(turn ? Color(hex: 0xD4A853).opacity(0.8) : .clear, lineWidth: max(1, 0.012 * u)))
        .fixedSize()
    }
}

/// The gold ring round the face whose turn it is, running down with their clock.
struct TurnRing: View {
    let endsAt: Double?
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
            let left = endsAt.map { max(0, min(1, ($0 / 1000 - ctx.date.timeIntervalSince1970) / 45)) } ?? 1
            GeometryReader { g in
                let r = min(g.size.width, g.size.height) / 2, lw = r * 0.1
                ZStack {
                    Circle().stroke(Color(hex: 0xD4A853).opacity(0.35), lineWidth: r * 0.3).blur(radius: r * 0.12)
                    Circle().stroke(.white.opacity(0.22), lineWidth: lw)
                    Circle().trim(from: 0, to: left).stroke(Color(hex: 0xF5DE95), style: StrokeStyle(lineWidth: lw, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .padding(r * 0.25)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Your hand as the prototype's fan: one row, or two overlapping rows past 7 cards. Playable cards are bright, lifted
/// and edged in gold; the rest are dimmed.
struct HandFan3D: View {
    struct FanItem: Identifiable { let i: Int; let card: Overdraft.Card; var id: String { card.id } }
    let view: Overdraft.View
    var dealt: Int?
    var arriving: Set<String>
    /// A card tapped, where its center is in the fan, how far it's turned (degrees), and its width.
    var onTap: (Overdraft.Card, CGPoint, Double, Double) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func cardWidth(width: Double, height: Double) -> CGFloat {
        CGFloat(min(116, max(72, min((min(width, 560) - 40) / 3.35, height * 0.135).rounded())))
    }

    var body: some View {
        GeometryReader { g in
            let W = Double(g.size.width)
            let hw = Self.cardWidth(width: W + 24, height: Double(UIScreen.main.bounds.height))
            let ch = hw * 489 / 320
            let n = view.hand.count
            let items = view.hand.enumerated().map { FanItem(i: $0.offset, card: $0.element) }
            let rows: [[FanItem]] = n > 7 ? [Array(items.prefix((n + 1) / 2)), Array(items.dropFirst((n + 1) / 2))] : [items]
            let rowGap = ch * 0.42
            ZStack(alignment: .topLeading) {
                Color.clear
                ForEach(Array(rows.enumerated()), id: \.offset) { ri, row in
                    let m = row.count, boxW = W - 20
                    let step = m > 1 ? min(Double(hw) * 0.42, (boxW - Double(hw)) / Double(m - 1)) : 0
                    let total = step * Double(max(0, m - 1)) + Double(hw)
                    let x0 = (W - total) / 2 + Double(hw) / 2
                    let baseY = Double(ch) / 2 + 12 + (rows.count == 2 ? Double(ri) * Double(rowGap) : 0)
                    ForEach(Array(row.enumerated()), id: \.element.id) { j, item in
                        let i = item.i, c = item.card
                        let mid = Double(m - 1) / 2
                        let r = (Double(j) - mid) * min(3, 18 / Double(max(m, 1)))
                        let ok = playable(c)
                        let lift = Double(abs(Double(j) - mid) * 3) - (ok ? 10 : 0)
                        let shown = (dealt.map { i < $0 } ?? true) && !arriving.contains(c.id)
                        let center = CGPoint(x: x0 + Double(j) * step, y: baseY + lift)
                        Button { onTap(c, center, r, Double(hw)) } label: {
                            CardImage(name: c.artName, width: hw)
                                .saturation(ok ? 1 : 0.85)
                                .colorMultiply(ok ? .white : Color(white: 0.7))
                                .overlay(RoundedRectangle(cornerRadius: hw / 14).stroke(ok ? Color(hex: 0xF5DE95).opacity(0.85) : .black.opacity(0.4), lineWidth: ok ? 1.5 : 1))
                                .shadow(color: ok ? Color(hex: 0xF5DE95).opacity(0.6) : .black.opacity(0.55), radius: ok ? 8 : 6, y: ok ? 0 : 6)
                        }
                        .buttonStyle(.plain)
                        .rotationEffect(.degrees(r))
                        .opacity(shown ? 1 : 0)
                        .offset(y: shown ? 0 : 40)
                        .position(center)
                        .zIndex(Double(ri * 100 + j))
                        .accessibilityLabel(c.spoken)
                        .accessibilityValue(ok ? (view.yourTurn ? "playable" : "jump in") : "can’t go now")
                        .accessibilityIdentifier(ok ? "legal-\(c.id)" : "card-\(c.id)")
                        .accessibilitySortPriority(Double(n - i))
                    }
                }
            }
            .frame(width: g.size.width, height: g.size.height)
        }
        .frame(height: Self.height(view.hand.count))
        .animation(reduceMotion ? nil : .spring(duration: 0.3), value: view.hand)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Your hand, \(view.hand.count) cards")
    }

    /// The fan's height: one row, or two overlapping ones.
    static func height(_ n: Int) -> CGFloat {
        let hw = cardWidth(width: Double(UIScreen.main.bounds.width), height: Double(UIScreen.main.bounds.height))
        let ch = hw * 489 / 320
        return ch + 24 + (n > 7 ? ch * 0.42 : 0)
    }

    private func playable(_ c: Overdraft.Card) -> Bool {
        if view.held { return false }
        if view.yourTurn { return view.legal.contains(c.id) && (view.drawn == nil || view.drawn == c.id) }
        return view.jump.contains(c.id)
    }
}
