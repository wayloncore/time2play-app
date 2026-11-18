import SwiftUI
import T2PCore

/// Play → "Host on this iPad" (#537): start a hosted room of any of the app's games, run from this iPad.
struct HostRoomsSection: View {
    @EnvironmentObject var app: AppModel
    @State private var hosting: HostModel?
    @State private var busy = false

    var body: some View {
        if AppModel.canHost {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("Host on this iPad").font(.title3.bold()).foregroundStyle(T2P.text).accessibilityAddTraits(.isHeader)
                    if busy { T2PSpinner(size: 22, label: "Opening a room") }   // #543: the room is being started
                }
                Text("This iPad runs the room: the table, the code and the controls. Everyone plays on their own phone, and a TV can show the table.")
                    .font(.subheadline).foregroundStyle(T2P.muted)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Game.allCases) { g in
                            Button { Task { await host(g) } } label: { Label(g.title, systemImage: "ipad.landscape") }
                                .buttonStyle(QuietButtonStyle())
                                .disabled(busy)
                                .accessibilityLabel("Host \(g.title) on this iPad")
                                .accessibilityIdentifier("host-\(g.rawValue)")
                        }
                    }
                }
            }
            .fullScreenCover(item: $hosting) { h in HostView(host: h) { h.stop(); hosting = nil }.environmentObject(app) }
        }
    }

    private func host(_ g: Game) async {
        busy = true; defer { busy = false }
        do {
            let r = try await app.api.startHostedRoom(g)
            let h = HostModel(room: r, endpoints: app.endpoints)
            hosting = h
            h.start()
        } catch {
            app.problem = (error as? API.Failure)?.message ?? "Couldn’t start a room. Check your signal and try again."
        }
    }
}

/// The host screen on an iPad: how to join (code, QR, link), who's in, the controls, and the table everyone shares.
struct HostView: View {
    @ObservedObject var host: HostModel
    var onDone: () -> Void
    @State private var confirmEnd = false
    @State private var tv = false
    @State private var removing: FloorPlayer?
    @ScaledMetric(relativeTo: .headline) private var face: CGFloat = 44

    var body: some View {
        GeometryReader { g in
            let wide = g.size.width > g.size.height
            VStack(spacing: 0) {
                topBar
                if let why = endedWhy {
                    EndedHost(why: why, onDone: onDone)
                } else if host.floor == nil {
                    Spacer()
                    VStack(spacing: 16) {
                        T2PSpinner(size: 64, label: "Opening room \(host.room.code)")   // #543
                        Text("Opening room \(host.room.code)…").font(.headline).foregroundStyle(T2P.text)
                    }
                    Spacer()
                } else if wide {
                    HStack(alignment: .top, spacing: 20) {
                        side.frame(width: min(380, g.size.width * 0.36))
                        stage.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(20)
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            joinCard
                            stage.frame(minHeight: 420)
                            playersCard
                            controls
                        }
                        .padding(20)
                    }
                }
            }
        }
        .background(background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .overlay(alignment: .top) {
            VStack(spacing: 6) {
                if host.status == .reconnecting { Banner(text: "Reconnecting… the room carries on", icon: "wifi.exclamationmark") }
                if let t = host.toast { Banner(text: t, icon: "exclamationmark.circle.fill") }
            }
            .padding(.top, 60)
        }
        .confirmationDialog("End the room for everyone?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End the room", role: .destructive) { host.endRoom(); onDone() }
            Button("Keep it open", role: .cancel) {}
        }
        .confirmationDialog("Take \(removing?.name ?? "them") out of the room?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("Remove", role: .destructive) { if let p = removing { host.send(Out.remove(p.id)) }; removing = nil }
            Button("Keep", role: .cancel) { removing = nil }
        }
        .sheet(isPresented: $tv) { ShowOnTV() }
    }

    private var endedWhy: String? { if case let .ended(w) = host.status { return w }; return nil }

    private var background: Color {
        switch host.game { case .overdraft: return T2P.table; case .hotDice: return T2P.felt; default: return Color(hex: 0x0B1121) }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button("End room") { confirmEnd = true }.foregroundStyle(T2P.goldText).accessibilityIdentifier("host-end")
            Spacer()
            Text(host.game.title).font(.title3.bold()).foregroundStyle(T2P.text).accessibilityAddTraits(.isHeader)
            Spacer()
            HowToButton(game: host.game, view: host.floor)
            Button { tv = true } label: {
                Label(TVModel.shared.connected ? "On the TV" : "Show on TV", systemImage: "tv").font(.headline).foregroundStyle(T2P.text)
            }
            .accessibilityIdentifier("host-tv")
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(.black.opacity(0.25))
    }

    // MARK: the side: join, players, controls

    private var side: some View {
        ScrollView {
            VStack(spacing: 16) {
                joinCard
                playersCard
                controls
            }
        }
    }

    private var joinCard: some View {
        Panel {
            HStack(spacing: 16) {
                if let q = QR.image(host.invite.absoluteString) {
                    Image(uiImage: q).interpolation(.none).resizable().frame(width: 120, height: 120)
                        .padding(8).background(.white, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel("QR code for room \(host.room.code)")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Join at time2play.live").font(.subheadline.weight(.semibold)).foregroundStyle(T2P.muted)
                    Text(host.room.code).font(.system(size: 54, weight: .heavy, design: .rounded)).tracking(5).foregroundStyle(T2P.text)
                        .minimumScaleFactor(0.6).lineLimit(1)
                        .accessibilityLabel("Room code \(host.room.code.map(String.init).joined(separator: " "))")
                        .accessibilityIdentifier("host-code")
                    ShareLink(item: host.invite, message: Text("Join my \(host.game.title) room: code \(host.room.code)")) {
                        Label("Invite", systemImage: "square.and.arrow.up").font(.subheadline.weight(.semibold)).foregroundStyle(T2P.goldText)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var playersCard: some View {
        let ps = host.players
        return VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Players · \(ps.count) of \(host.game.maxPlayers)",
                         trailing: Floor.watching(host.floor ?? .null) > 0 ? "Watching: \(Floor.watching(host.floor ?? .null))" : nil)
            VStack(spacing: 0) {
                if ps.isEmpty {
                    Text("Nobody yet. Scan the code or go to time2play.live on a phone.").font(.subheadline).foregroundStyle(T2P.muted)
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(ps) { p in
                    HStack(spacing: 12) {
                        FaceView(face: p.face, size: face, dimmed: !p.connected && p.bot == nil)
                            .overlay(Circle().stroke(p.turn ? T2P.gold : .clear, lineWidth: 3).padding(-3))
                        Text(p.name).font(.headline).foregroundStyle(T2P.text).lineLimit(1)
                        if p.bot != nil { Tag(text: "BOT") }
                        if !p.connected && p.bot == nil { Text("away").font(.caption).foregroundStyle(T2P.faint) }
                        Spacer()
                        if let c = p.cards { Text("\(c) cards").font(.subheadline.monospacedDigit()).foregroundStyle(T2P.muted) }
                        else if let s = p.score, host.phase != "lobby" { Text(s.formatted()).font(.headline.monospacedDigit()).foregroundStyle(T2P.text) }
                        Button { removing = p } label: { Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(T2P.faint) }
                            .accessibilityLabel("Remove \(p.name)")
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("host-player-\(p.id)")
                }
            }
            .background(T2P.panel, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    @ViewBuilder private var controls: some View {
        if let f = host.floor {
            if host.phase == "lobby" {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "Add a bot")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(host.game.bots, id: \.level) { b in
                                Button(b.name) { host.send(Out.addBot(level: b.level)); Haptics.select() }
                                    .buttonStyle(QuietButtonStyle())
                                    .disabled(host.players.count >= host.game.maxPlayers)
                                    .accessibilityIdentifier("host-addbot-\(b.level)")
                            }
                        }
                    }
                    SectionLabel(text: "House rules")
                    Panel { RulesEditor(game: host.game, view: f, editable: true) { host.send(Out.options($0)) } }
                    let enough = host.players.count >= host.game.minPlayers
                    Button(host.game == .overdraft ? "Deal the first hand" : "Start the game") { host.send(Out.deal); Haptics.play() }
                        .buttonStyle(GoldButtonStyle()).disabled(!enough)
                        .accessibilityIdentifier("host-start")
                    if !enough {
                        Text("\(host.game.minPlayers) or more can play. Add a bot, or wait for phones to join.").font(.footnote).foregroundStyle(T2P.muted)
                    }
                }
            } else if host.phase == "done" || (host.game == .overdraft && f["tables"].array.allSatisfy { $0["over"].bool == true } && !f["tables"].array.isEmpty) {
                VStack(spacing: 10) {
                    Button(host.game == .overdraft ? "Deal another hand" : "Play again") { host.send(Out.again); host.send(Out.deal); Haptics.play() }
                        .buttonStyle(GoldButtonStyle()).accessibilityIdentifier("host-again")
                    Button("Back to the lobby") { host.send(Out.again) }.buttonStyle(QuietButtonStyle())
                }
            }
        }
    }

    // MARK: the stage: the table everyone shares

    @ViewBuilder private var stage: some View {
        if let f = host.floor {
            HostStage(floor: f, game: host.game, code: host.room.code)
                // the waiting stage is the logo clip's own navy, so the loop melts into it (#543)
                .background(host.phase == "lobby" ? Color(uiColor: Intro.navy) : Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 22))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("host-stage")
        }
    }
}

/// The shared table, drawn from the floor: the lobby's how-to-join, then each game's public view.
struct HostStage: View {
    let floor: JSON
    let game: Game
    let code: String
    @AppStorage(Boards3D.flatCloseEnoughKey) private var flatBoard = false

    var body: some View {
        let phase = floor["phase"].string ?? "lobby"
        VStack(spacing: 18) {
            if phase == "lobby" {
                Spacer(minLength: 0)
                // #543: Tyler's looping logo beside how to join (never under the code or the QR, which stay big and sharp)
                HStack(spacing: 28) {
                    WaitingLogo(phase: phase)
                        .frame(maxWidth: 320, maxHeight: 440)
                    VStack(spacing: 18) {
                        Text("Join at time2play.live").font(.system(size: 30, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                        Text(code).font(.system(size: 110, weight: .heavy, design: .rounded)).tracking(12).foregroundStyle(.white)
                            .minimumScaleFactor(0.5).lineLimit(1)
                        if let q = QR.image("https://time2play.live/\(code)", scale: 12) {
                            Image(uiImage: q).interpolation(.none).resizable().frame(width: 200, height: 200)
                                .padding(12).background(.white, in: RoundedRectangle(cornerRadius: 16))
                                .accessibilityHidden(true)
                        }
                        Text(game.blurb).font(.title3).foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: 440)
                    .layoutPriority(1)
                }
                Spacer(minLength: 0)
            } else {
                switch game {
                case .overdraft: overdraft
                case .hotDice: hotDice
                case .rollCall: rollCall
                case .closeEnough: closeEnough
                }
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func name(_ id: String?) -> String {
        guard let id else { return "" }
        return Floor.players(floor, game: game).first { $0.id == id }?.name ?? ""
    }

    @ViewBuilder private var overdraft: some View {
        let t = floor["tables"][0]
        let top = t["top"]
        Spacer()
        if t["over"].bool == true {
            Image(systemName: "trophy.fill").font(.system(size: 64)).foregroundStyle(T2P.gold)
            Text("\(name(t["winner"].string)) wins the hand!").font(.system(size: 40, weight: .bold)).foregroundStyle(.white)
        } else {
            HStack(spacing: 28) {
                if top.object != nil {
                    let card = Overdraft.Card(kind: top["kind"].string ?? "number", suit: top["suit"].string, n: top["n"].int)
                    CardImage(name: card.artName, width: 220).shadow(color: .black.opacity(0.5), radius: 20, y: 10)
                        .accessibilityLabel("On the pile: \(card.spoken)")
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(name(t["turn"].string))’s turn").font(.system(size: 36, weight: .bold)).foregroundStyle(.white)
                    if let s = t["suit"].string {
                        Label("Suit: \(s.capitalized)", systemImage: "circle.fill").font(.title2.weight(.semibold))
                            .foregroundStyle(T2P.suit[s] ?? .white)
                    }
                    Label(t["direction"].int == -1 ? "Turns go the other way" : "Turns go round", systemImage: t["direction"].int == -1 ? "arrow.counterclockwise" : "arrow.clockwise")
                        .font(.title3).foregroundStyle(.white.opacity(0.8))
                    if (t["stack"].int ?? 0) > 0 { Text("+\(t["stack"].int!) waiting").font(.title2.bold()).foregroundStyle(T2P.ember) }
                }
            }
        }
        Spacer()
        seatsRow
    }

    @ViewBuilder private var hotDice: some View {
        let t = floor["turn"]
        Spacer()
        if floor["phase"].string == "done" { winners } else if t.object != nil {
            Text("\(name(t["id"].string))’s turn").font(.system(size: 36, weight: .bold)).foregroundStyle(.white)
            let kept = Set(t["kept"].array.compactMap(\.int))
            let rolling = t["state"].string == "rolling"
            HStack(spacing: 16) {
                ForEach(t["dice"].array.indices, id: \.self) { i in
                    let d = t["dice"].array[i]
                    DieView(value: rolling ? nil : d["v"].int, size: 92, dimmed: kept.contains(d["id"].int ?? -1))
                }
            }
            Text("\((t["pts"].int ?? 0) + (t["selPts"].int ?? 0)) this turn").font(.title.weight(.semibold).monospacedDigit()).foregroundStyle(T2P.gold)
        }
        Spacer()
        seatsRow
    }

    @ViewBuilder private var rollCall: some View {
        let t = floor["turn"]
        Spacer()
        if floor["phase"].string == "done" { winners } else if t.object != nil {
            Text("\(name(t["id"].string))’s turn").font(.system(size: 36, weight: .bold)).foregroundStyle(.white)
            let held = t["held"].array.map { $0.bool ?? false }
            HStack(spacing: 16) {
                ForEach(t["dice"].array.indices, id: \.self) { i in
                    DieView(value: (t["rolls"].int ?? 0) > 0 ? t["dice"][i].int : nil, size: 92, held: i < held.count && held[i])
                }
            }
            Text("Roll \(t["rolls"].int ?? 0) of 3").font(.title2.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
        }
        Spacer()
        seatsRow
    }

    @ViewBuilder private var closeEnough: some View {
        let v = CloseEnough.View(floor)
        if v.common.phase == "done" { Spacer(); winners; Spacer() }
        else if let q = v.question {
            Text("Question \(q.n) of \(q.of)").font(.title3.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
            Text(q.q).font(.system(size: 38, weight: .bold)).foregroundStyle(.white).multilineTextAlignment(.center)
            if !q.note.isEmpty { Text(q.note).font(.title3).foregroundStyle(.white.opacity(0.7)) }
            if q.stage == "ask" {
                let inGame = v.players.filter { !$0.left && $0.seated }
                Text("\(inGame.filter(\.lockedIn).count) of \(inGame.count) locked in").font(.title.weight(.semibold)).foregroundStyle(T2P.gold)
                if let e = q.endsAt { Countdown(endsAt: e).scaleEffect(1.6).padding(.top, 8) }
                Text("From \(q.format(q.floor)) to \(q.format(q.ceiling))").font(.title3).foregroundStyle(.white.opacity(0.7))
            } else {
                Text("The answer: \(q.answer.map { q.format($0) } ?? "")").font(.system(size: 34, weight: .heavy)).foregroundStyle(T2P.gold)
                    .accessibilityIdentifier("host-answer")
                if Boards3D.closeEnough3D(flat: flatBoard) {
                    // #535's board, big: everyone's ranges and the answer dropping onto them
                    CloseEnoughBoard3D(state: .make(q: q, players: v.players, me: "", lo: 0, hi: 0, seated: false))
                        .frame(maxWidth: 900)
                } else {
                    RangesChart(q: q, players: v.players.filter { q.results[$0.id] != nil }, me: "", landed: true)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var seatsRow: some View {
        HStack(spacing: 18) {
            ForEach(Floor.players(floor, game: game)) { p in
                VStack(spacing: 6) {
                    FaceView(face: p.face, size: 60).overlay(Circle().stroke(p.turn ? T2P.gold : .clear, lineWidth: 4).padding(-4))
                    Text(p.name).font(.headline).foregroundStyle(.white).lineLimit(1)
                    Text(p.cards.map { "\($0) cards" } ?? (p.score ?? 0).formatted()).font(.subheadline.monospacedDigit()).foregroundStyle(.white.opacity(0.75))
                }
                .frame(maxWidth: 110)
                .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder private var winners: some View {
        let ids = floor["winners"].array.compactMap(\.string)
        Image(systemName: "trophy.fill").font(.system(size: 64)).foregroundStyle(T2P.gold)
        Text(ids.count > 1 ? "A shared win: \(ids.map { name($0) }.joined(separator: " and "))" : "\(name(ids.first)) wins!")
            .font(.system(size: 44, weight: .bold)).foregroundStyle(.white).multilineTextAlignment(.center)
            .accessibilityIdentifier("host-winner")
    }
}

struct EndedHost: View {
    let why: String
    var onDone: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "door.left.hand.closed").font(.system(size: 48)).foregroundStyle(T2P.gold)
            Text(why).font(.title2.bold()).foregroundStyle(T2P.text).multilineTextAlignment(.center)
            Button("Back to Play", action: onDone).buttonStyle(GoldButtonStyle()).frame(maxWidth: 320)
            Spacer()
        }
        .padding(32)
    }
}
