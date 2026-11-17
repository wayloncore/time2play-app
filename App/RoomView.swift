import SwiftUI
import T2PCore

/// A room, full screen: picking a name and face, the lobby, the game, and how it ends.
struct RoomView: View {
    @ObservedObject var room: RoomModel
    @EnvironmentObject var app: AppModel
    @State private var confirmLeave = false
    @AppStorage(Table3DSwitch.key) private var table3D = false

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            content
        }
        .overlay(alignment: .top) { banners }
        .overlay(alignment: .bottom) { reactionsShown }
        .preferredColorScheme((room.game == .overdraft || room.game == .hotDice) && room.phase != "lobby" && room.view != nil ? .dark : nil)   // the card table and the felt are dark either way
        .confirmationDialog(leaveTitle, isPresented: $confirmLeave, titleVisibility: .visible) {
            Button(room.phase == "playing" ? "Leave the game" : "Leave the room", role: .destructive) { room.leave(); app.closeRoom() }
            Button("Stay", role: .cancel) {}
        } message: { Text(leaveDetail) }
    }

    private var leaveTitle: String { room.isOwner ? "Leave your room?" : "Leave?" }
    private var leaveDetail: String {
        var s = room.phase == "playing" ? "A bot plays your seat for the rest of the game." : "Your seat goes to whoever joins next."
        if room.isOwner { s += " The room passes to whoever has been here longest." }
        return s
    }

    private var background: Color {
        if room.phase == "lobby" || room.view == nil { return T2P.navy }
        switch room.game { case .overdraft: return T2P.table; case .hotDice: return T2P.felt; default: return T2P.navy }
    }

    @ViewBuilder private var content: some View {
        switch room.status {
        case .connecting, .joining:
            Waiting(text: room.starting ? "Starting your room…" : "Opening room \(room.code)…") { app.closeRoom() }
        case let .choosing(problem):
            NameFacePicker(room: room, problem: problem)
        case .needsUpdate:
            PleaseUpdateView(code: room.code) { app.closeRoom() }
        case let .ended(why):
            EndedView(why: why) { app.closeRoom() }
        case .inRoom, .reconnecting:
            if let v = room.view {
                game(v)
            } else {
                Waiting(text: "Coming back to room \(room.code)…") { app.closeRoom() }
            }
        }
    }

    @ViewBuilder private func game(_ v: JSON) -> some View {
        if (v["phase"].string ?? "lobby") == "lobby" {
            LobbyView(room: room, onLeave: { confirmLeave = true })
        } else {
            switch room.game {
            case .overdraft:
                // a late joiner waiting for the next hand has no table yet: the lobby says so
                if v["table"].object != nil {
                    // #496: the 3D table, behind its switch (off by default until Tyler approves it)
                    if table3D || Table3DSwitch.forced { Table3DView(room: room, view: Overdraft.View(v), onLeave: { confirmLeave = true }) }
                    else { OverdraftTableView(room: room, view: Overdraft.View(v), onLeave: { confirmLeave = true }) }
                }
                else { LobbyView(room: room, onLeave: { confirmLeave = true }) }
            case .hotDice: HotDiceView(room: room, view: HotDice.View(v), onLeave: { confirmLeave = true })
            case .rollCall: RollCallView(room: room, view: RollCall.View(v), onLeave: { confirmLeave = true })
            case .closeEnough: CloseEnoughView(room: room, view: CloseEnough.View(v), onLeave: { confirmLeave = true })
            }
        }
    }

    @ViewBuilder private var banners: some View {
        VStack(spacing: 8) {
            if case .reconnecting = room.status {
                Banner(text: "Reconnecting… your seat is held", icon: "wifi.exclamationmark")
                    .accessibilityIdentifier("reconnecting")
            }
            if let b = room.back { Banner(text: b, icon: "arrow.uturn.backward.circle.fill").accessibilityIdentifier("back") }
            if let t = room.toast { Banner(text: t, icon: "exclamationmark.circle.fill") }
        }
        .padding(.top, 4)
        .animation(.easeInOut, value: room.toast)
        .animation(.easeInOut, value: room.back)
    }

    private var reactionsShown: some View {
        VStack(spacing: 6) {
            ForEach(room.reactions) { r in
                HStack(spacing: 6) { Text(r.who).bold(); Text(r.words) }
                    .font(.subheadline).foregroundStyle(T2P.text)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.bottom, 96)
        .animation(.spring, value: room.reactions)
        .accessibilityHidden(true)   // announced instead (RoomModel)
    }
}

struct Banner: View {
    let text: String; let icon: String
    var body: some View {
        Label(text, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(T2P.text)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(T2P.line))
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}

struct Waiting: View {
    let text: String
    var onCancel: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large).tint(T2P.gold)
            Text(text).font(.headline).foregroundStyle(T2P.text)
            Button("Cancel", action: onCancel).foregroundStyle(T2P.goldText)
        }
    }
}

/// Your name and face for this room. A face someone in the room already has is locked.
struct NameFacePicker: View {
    @ObservedObject var room: RoomModel
    let problem: String?
    @EnvironmentObject var app: AppModel
    @State private var name = ""
    @State private var face: Int?
    @FocusState private var typing: Bool

    private var cleanName: String { name.trimmingCharacters(in: .whitespaces) }
    private var ready: Bool { cleanName.count >= 2 && face != nil }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { app.closeRoom() }.foregroundStyle(T2P.goldText)
                Spacer()
                Text("Room \(room.code)").font(.subheadline.weight(.semibold)).foregroundStyle(T2P.muted)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(room.game.title).font(.largeTitle.bold()).foregroundStyle(T2P.text).accessibilityAddTraits(.isHeader)
                        Text("Pick a name and a face. Nobody needs an account to play.").foregroundStyle(T2P.muted)
                    }
                    if let p = problem { Label(p, systemImage: "exclamationmark.circle.fill").foregroundStyle(T2P.ember).font(.subheadline.weight(.semibold)) }
                    Panel {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Your name").font(.headline).foregroundStyle(T2P.text)
                            TextField("", text: Binding(get: { name }, set: { name = String($0.prefix(12)) }),
                                      prompt: Text("2 to 12 letters").foregroundStyle(T2P.faint))
                                .font(.title3).foregroundStyle(T2P.text)
                                .textInputAutocapitalization(.words).autocorrectionDisabled()
                                .submitLabel(.done).focused($typing)
                                .padding(12)
                                .background(T2P.navy, in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(T2P.line))
                                .accessibilityLabel("Your name")
                                .accessibilityIdentifier("name")
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(text: "Your face", trailing: face.map { Faces.label($0) })
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 60), spacing: 10)], spacing: 10) {
                            ForEach(0..<Faces.count, id: \.self) { i in
                                let taken = room.taken.contains(i)
                                Button { face = i; Haptics.select() } label: {
                                    FaceView(face: i, size: 60, dimmed: taken)
                                        .overlay(Circle().stroke(face == i ? T2P.gold : .clear, lineWidth: 4).padding(-3))
                                        .overlay(alignment: .bottomTrailing) {
                                            if taken { Image(systemName: "lock.fill").font(.caption).foregroundStyle(T2P.text).padding(4).background(T2P.panel, in: Circle()) }
                                        }
                                }
                                .disabled(taken)
                                .accessibilityLabel(Faces.label(i))
                                .accessibilityValue(taken ? "Taken" : face == i ? "Selected" : "")
                                .accessibilityAddTraits(face == i ? .isSelected : [])
                                .accessibilityIdentifier("face-\(i)")
                            }
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: 700).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            Button {
                guard let f = face else { return }
                app.profile = Profile(name: cleanName, face: f)
                room.join(name: cleanName, face: f)
            } label: { Text(ready ? "Join as \(cleanName)" : "Join") }
                .buttonStyle(GoldButtonStyle())
                .disabled(!ready)
                .padding(.horizontal, 20).padding(.vertical, 12)
                .accessibilityIdentifier("join-room")
        }
        .onAppear {
            if name.isEmpty { name = app.profile.name }
            let want = app.profile.face ?? Int.random(in: 0..<Faces.count)
            if face == nil { face = Faces.firstFree(preferring: want, taken: room.taken) }
            if room.offline { return }
            Task {
                let t = await app.api.taken(room.game, code: room.code)
                room.taken = t
                if let f = face, t.contains(f) { face = Faces.firstFree(preferring: f, taken: t) }
            }
        }
    }
}

struct EndedView: View {
    let why: RoomSession.EndReason
    var onDone: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: why == .closedByOwner ? "door.left.hand.closed" : "hand.wave.fill")
                .font(.system(size: 48)).foregroundStyle(T2P.gold)
                .accessibilityHidden(true)
            Text(why.title).font(.title2.bold()).foregroundStyle(T2P.text).multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(why.detail).foregroundStyle(T2P.muted).multilineTextAlignment(.center)
            Button("Back to Play", action: onDone).buttonStyle(GoldButtonStyle()).padding(.top, 8)
                .accessibilityIdentifier("back-to-play")
        }
        .padding(32)
        .frame(maxWidth: 500)
    }
}

/// The server no longer serves this app's protocol (it only ever adds, so this should almost never show).
struct PleaseUpdateView: View {
    let code: String
    var onDone: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.app.fill").font(.system(size: 52)).foregroundStyle(T2P.gold).accessibilityHidden(true)
            Text("Please update Time2Play").font(.title2.bold()).foregroundStyle(T2P.text).accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("please-update")
            Text("This room needs a newer version of the app. Updating takes a minute, and your games and friends stay as they are.")
                .foregroundStyle(T2P.muted).multilineTextAlignment(.center)
            Link("Open the App Store", destination: URL(string: "https://apps.apple.com/search?term=Time2Play")!)
                .buttonStyle(GoldButtonStyle())
            Link("Play this room on the website", destination: Endpoints.live.invite(code: code))
                .foregroundStyle(T2P.goldText)
            Button("Not now", action: onDone).foregroundStyle(T2P.muted)
        }
        .padding(32)
        .frame(maxWidth: 500)
    }
}
