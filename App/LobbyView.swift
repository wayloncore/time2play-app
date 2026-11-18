import SwiftUI
import T2PCore

/// A player as a lobby lists them, whichever game.
struct LobbyPlayer: Identifiable, Equatable {
    let id: String; let name: String; let face: Int; let bot: String?; let connected: Bool; let held: Bool
}

extension RoomModel {
    var lobbyPlayers: [LobbyPlayer] {
        guard let v = view else { return [] }
        let list = game == .overdraft ? v["roster"].array : v["players"].array.filter { $0["left"].bool != true }
        return list.map {
            LobbyPlayer(id: $0["id"].string ?? "", name: RoomPlayer.stripBot($0["name"].string ?? ""), face: $0["face"].int ?? 0,
                        bot: $0["bot"].string, connected: $0["connected"].bool ?? true, held: $0["held"].bool ?? false)
        }
    }
    var ownerName: String? {
        guard let o = view?["owner"].string else { return nil }
        return lobbyPlayers.first { $0.id == o }?.name
    }
    var hostless: Bool { view?["hostless"].bool ?? true }
}

/// The lobby: the code, QR and Share; who's here; bots; house rules; and, for the room's owner, Start.
/// Option A in the plan (#385): the owner runs the room, a player like everyone else. No big screen needed.
struct LobbyView: View {
    @ScaledMetric(relativeTo: .headline) private var face: CGFloat = 48
    @ObservedObject var room: RoomModel
    @EnvironmentObject var app: AppModel
    var onLeave: () -> Void
    /// The room's painted dialogs (RoomView's); Take out, End the room and Report are painted like the game (Nov 18).
    @Environment(\.gameDialogs) private var dialogs
    @State private var showQR = false
    @State private var tv = false

    private var players: [LobbyPlayer] { room.lobbyPlayers }
    private var owner: Bool { room.isOwner }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(room.game.title).font(.largeTitle.bold()).foregroundStyle(T2P.text).accessibilityAddTraits(.isHeader)
                            Text(room.offline ? "Practice with bots, on this device · nothing here counts"
                                 : room.hostless ? "Private room · only people with the code or link" : "Hosted by the room’s big screen")
                                .foregroundStyle(T2P.muted)
                        }
                        // #543: Tyler's looping logo while the room waits for players (not offline: nobody's coming)
                        if !room.offline && room.phase == "lobby" {
                            Spacer(minLength: 0)
                            WaitingLogo(phase: room.phase, style: .badge).frame(width: 96, height: 96)
                        }
                    }
                    if !room.offline { codePanel }
                    // Nov 18: the room's owner invites friends or a group from here
                    if !room.offline && owner { InviteFriendsBar(book: app.invites, game: room.game, code: room.code) }
                    if room.phase == "playing" || room.phase == "done" {
                        Label(room.game == .overdraft ? "A hand is on. You’re dealt in at the next one." : "A game is on. You’ll play in the next one.",
                              systemImage: "hourglass").foregroundStyle(T2P.muted)
                    }
                    playersPanel
                    rulesPanel
                }
                .padding(20)
                .frame(maxWidth: 700).frame(maxWidth: .infinity)
            }
            startBar
        }
        .sheet(isPresented: $showQR) { BigQR(code: room.code, link: room.inviteLink) }
        .sheet(isPresented: $tv) { ShowOnTV() }
    }

    private func ask(_ d: GameDialog) {
        if let dialogs { dialogs.show(d) } else { AppDialogs.shared.show(d) }
    }

    private func askRemove(_ p: LobbyPlayer) {
        let r = room
        ask(GameDialog(title: "Take \(p.name) out of the room?",
                       message: p.bot == nil ? "They can come back in with the code." : nil,
                       choices: [GameChoice(label: "Remove", kind: .danger, identifier: "remove-confirm") { r.send(Out.remove(p.id)) }],
                       cancel: "Keep", identifier: "dialog-remove"))
    }

    private func askReport(_ p: LobbyPlayer) {
        let r = room, a = app
        let thanks = { r.toast = "Thanks. Tyler will look at it." }
        ask(GameDialog(title: p.name, message: "Report this player to Tyler. Only the reason you pick goes with it.",
                       choices: [GameChoice(label: "Report their name", identifier: "report-name") { Task { try? await a.api.report(name: p.name, why: "name", room: r.code); thanks() } },
                                 GameChoice(label: "Report how they play", identifier: "report-behavior") { Task { try? await a.api.report(name: p.name, why: "behavior", room: r.code); thanks() } }],
                       cancel: "Back", identifier: "dialog-report"))
    }

    private var topBar: some View {
        HStack {
            Button("Leave", action: onLeave).foregroundStyle(T2P.goldText).accessibilityIdentifier("leave")
            Spacer()
            HowToButton(game: room.game, view: room.view)   // #489: the rules, one tap away
            if !room.offline {
                Button { tv = true } label: { Image(systemName: "tv").font(.headline).foregroundStyle(T2P.text).frame(width: 44, height: 44) }
                    .accessibilityLabel("Show on TV").accessibilityIdentifier("show-on-tv")
            }
            if owner {
                Label("You own this room", systemImage: "crown.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(T2P.text)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(T2P.panelHi, in: Capsule())
                    .accessibilityIdentifier("owner-chip")
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
    }

    private var codePanel: some View {
        Panel {
            HStack(spacing: 16) {
                Button { showQR = true } label: {
                    if let q = QR.image(room.inviteLink.absoluteString) {
                        Image(uiImage: q).interpolation(.none).resizable().frame(width: 76, height: 76)
                            .padding(6).background(.white, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .accessibilityLabel("Show the QR code bigger")
                VStack(alignment: .leading, spacing: 2) {
                    Text(room.code).font(.system(size: 40, weight: .bold, design: .rounded)).tracking(4).foregroundStyle(T2P.text)
                        .minimumScaleFactor(0.6).lineLimit(1)
                        .accessibilityLabel("Room code \(room.code.map(String.init).joined(separator: " "))")
                        .accessibilityIdentifier("room-code-shown")
                    Text(room.inviteLink.absoluteString.replacingOccurrences(of: "https://", with: ""))
                        .font(.subheadline).foregroundStyle(T2P.muted).lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
                ShareLink(item: room.inviteLink, subject: Text("Play \(room.game.title)"),
                          message: Text("Join my \(room.game.title) room: code \(room.code)")) {
                    Image(systemName: "square.and.arrow.up").font(.title2.weight(.semibold)).foregroundStyle(T2P.ink)
                        .frame(width: 52, height: 52).background(T2P.gold, in: Circle())
                }
                .accessibilityLabel("Invite people")
            }
        }
    }

    private var playersPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Players · \(players.count) of \(room.game.maxPlayers)")
            VStack(spacing: 0) {
                ForEach(players) { p in
                    row(p)
                    if p.id != players.last?.id || owner { Divider().overlay(T2P.line) }
                }
                if owner && room.phase == "lobby" { addBots }
            }
            .background(T2P.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(T2P.line))
        }
    }

    private func row(_ p: LobbyPlayer) -> some View {
        let me = p.id == room.meId
        let isOwnerRow = p.id == room.view?["owner"].string
        let sub = [p.bot != nil ? "Bot · \(p.bot!)" : nil, isOwnerRow ? "owner" : nil, !p.connected && p.bot == nil ? "away" : nil,
                   p.held ? "a bot is playing for them" : nil].compactMap { $0 }.joined(separator: " · ")
        return HStack(spacing: 14) {
            FaceView(face: p.face, size: face, dimmed: !p.connected && p.bot == nil)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(me ? "You" : p.name).font(.headline).foregroundStyle(T2P.text)
                    if p.bot != nil { Tag(text: "BOT") }
                    if isOwnerRow { Image(systemName: "crown.fill").font(.caption).foregroundStyle(T2P.gold).accessibilityHidden(true) }
                }
                if !sub.isEmpty { Text(sub.prefix(1).uppercased() + sub.dropFirst()).font(.subheadline).foregroundStyle(T2P.muted) }
            }
            Spacer()
            if owner && !me && room.phase == "lobby" {
                Button { askRemove(p) } label: { Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(T2P.faint) }
                    .accessibilityLabel("Remove \(p.name)")
                    .accessibilityIdentifier("remove-\(p.id)")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel([me ? "You" : p.name, sub].filter { !$0.isEmpty }.joined(separator: ", "))
        .accessibilityIdentifier("player-\(p.id)")
        // report a name from any player list (#395); guests can too. No free text: a preset reason. A long press asks,
        // painted (Nov 18).
        .onLongPressGesture(minimumDuration: 0.5) { if !me && p.bot == nil && !room.offline { askReport(p) } }
        .accessibilityAction(named: "Report") { if !me && p.bot == nil && !room.offline { askReport(p) } }
    }

    private var addBots: some View {
        let seated = Set(players.compactMap(\.bot))
        let full = players.count >= room.game.maxPlayers
        return VStack(alignment: .leading, spacing: 10) {
            Label("Add a bot", systemImage: "plus.circle").font(.headline).foregroundStyle(T2P.goldText)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(room.game.bots, id: \.level) { b in
                        // Overdraft's bots are levels (add as many as fit); the other games' are three named bots, once each
                        let used = room.game != .overdraft && seated.contains(b.level)
                        Button { room.send(Out.addBot(level: b.level)); Haptics.select() } label: { Text(b.name) }
                            .buttonStyle(QuietButtonStyle())
                            .disabled(used || full)
                            .accessibilityLabel(room.game == .overdraft ? "Add a \(b.name.lowercased()) bot" : "Add \(b.name), \(b.level)")
                            .accessibilityIdentifier("addbot-\(b.level)")
                    }
                }
            }
        }
        .padding(16)
    }

    @ViewBuilder private var rulesPanel: some View {
        if let v = room.view {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "House rules")
                Panel { RulesEditor(game: room.game, view: v, editable: owner && room.phase == "lobby") { room.send(Out.options($0)) } }
            }
        }
    }

    private var startBar: some View {
        VStack(spacing: 8) {
            if owner && room.phase == "lobby" {
                let enough = players.count >= room.game.minPlayers
                Button { room.send(Out.deal); Haptics.play() } label: {
                    Text(room.game == .overdraft ? "Deal the first hand" : "Start the game")
                }
                .buttonStyle(GoldButtonStyle())
                .disabled(!enough)
                .accessibilityIdentifier("start-game")
                Text(room.offline ? "Offline: just you and the bots." : enough ? "No big screen needed. Anyone can put it on a TV."
                     : "Add a bot or invite someone: \(room.game.minPlayers) or more can play.")
                    .font(.footnote).foregroundStyle(T2P.muted).multilineTextAlignment(.center)
                HStack(spacing: 24) {
                    SavePresetButton(room: room)   // #538
                    Button("End the room") { let r = room; ask(.endRoom(keep: "Keep it open", end: { r.send(Out.close) })) }
                        .font(.footnote.weight(.semibold)).foregroundStyle(T2P.faint)
                        .accessibilityIdentifier("lobby-end-room")
                }
            } else if room.phase == "lobby" {
                Text(room.hostless ? "Waiting for \(room.ownerName ?? "the room’s owner") to start." : "The big screen starts the game.")
                    .font(.headline).foregroundStyle(T2P.muted).multilineTextAlignment(.center)
                    .accessibilityIdentifier("waiting-for-owner")
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(T2P.navy.opacity(0.96))
    }
}

struct Tag: View {
    let text: String
    var body: some View {
        Text(text).font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(T2P.muted).fixedSize()
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(T2P.panelHi, in: RoundedRectangle(cornerRadius: 6))
    }
}

/// The house rules, each game's own. The owner changes them in the lobby; everyone else reads them.
struct RulesEditor: View {
    let game: Game
    let view: JSON
    let editable: Bool
    var set: ([String: JSON]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch game {
            case .overdraft:
                toggle("Jump-in", "Play the same card out of turn", view["jumpIn"].bool ?? false) { set(["jumpIn": .bool($0)]) }
                toggle("Stacking", "Pass a +2 or +4 along with your own", view["stacking"].bool ?? false) { set(["stacking": .bool($0)]) }
            case .hotDice:
                picker("Three 1s score", [1000, 300], view["ones"].int ?? 1000, label: { "\($0)" }) { set(["ones": .number(Double($0))]) }
                picker("Play to", [2500, 5000, 10000], view["target"].int ?? 10000, label: { $0.formatted() }) { set(["target": .number(Double($0))]) }
                toggle("500 to get on the board", "Your first bank needs 500 in one turn", view["rules"]["board"].bool ?? true) { set(["board": .bool($0)]) }
                toggle("Three Farkles cost 1,000", "Three in a row, and you lose 1,000", view["rules"]["three"].bool ?? true) { set(["three": .bool($0)]) }
            case .rollCall:
                toggle("Quick game", "6 rounds instead of 13", view["quick"].bool ?? false) { set(["quick": .bool($0)]) }
            case .closeEnough:
                if let qs = view["sets"].array.first(where: { $0["key"].string == (view["opts"]["set"].string ?? "general") }) ?? view["sets"].array.first {
                    Text("Questions from \(qs["name"].string ?? "the question set") · \(qs["size"].int ?? 0) in the set").font(.subheadline).foregroundStyle(T2P.muted)
                }
                picker("Questions", CloseEnough.counts, view["opts"]["count"].int ?? 10, label: { "\($0)" }) { set(["count": .number(Double($0))]) }
                picker("Time for each", CloseEnough.timers, view["opts"]["timer"].int ?? 60, label: { $0 < 60 || $0 == 90 ? "\($0)s" : "\($0 / 60) min" }) {
                    set(["timer": .number(Double($0))])
                }
            }
        }
    }

    private func toggle(_ title: String, _ detail: String, _ on: Bool, _ change: @escaping (Bool) -> Void) -> some View {
        // the words beside the switch, not inside it: a switch's own label is drawn dimmed, too faint to read
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(T2P.text)
                Text(detail).font(.subheadline).foregroundStyle(T2P.muted)
            }
            Spacer(minLength: 8)
            Toggle(title, isOn: Binding(get: { on }, set: change)).labelsHidden().tint(T2P.gold).disabled(!editable)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(detail)
    }

    private func picker(_ title: String, _ options: [Int], _ value: Int, label: @escaping (Int) -> String, _ change: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline).foregroundStyle(T2P.text)
            Picker(title, selection: Binding(get: { value }, set: change)) {
                ForEach(options, id: \.self) { Text(label($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(!editable)
        }
    }
}

/// The room's QR code, big, for someone across the table to scan.
struct BigQR: View {
    let code: String; let link: URL
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 20) {
            Text("Scan to join").font(.title2.bold()).foregroundStyle(T2P.text)
            if let q = QR.image(link.absoluteString, scale: 16) {
                Image(uiImage: q).interpolation(.none).resizable().scaledToFit().frame(maxWidth: 320)
                    .padding(16).background(.white, in: RoundedRectangle(cornerRadius: 20))
                    .accessibilityLabel("QR code for room \(code)")
            }
            Text(code).font(.system(size: 48, weight: .bold, design: .rounded)).tracking(6).foregroundStyle(T2P.text)
            Text(link.absoluteString.replacingOccurrences(of: "https://", with: "")).foregroundStyle(T2P.muted)
            Button("Done") { dismiss() }.buttonStyle(GoldButtonStyle()).frame(maxWidth: 240)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(T2P.navy.ignoresSafeArea())
        .presentationDetents([.large])
    }
}
