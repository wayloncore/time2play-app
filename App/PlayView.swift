import SwiftUI
import T2PCore

/// Play: join with a code (or the room's QR), or start a room. Guest first: nothing here needs an account.
struct PlayView: View {
    @EnvironmentObject var app: AppModel
    @State private var code = ""
    @State private var scanning = false
    @FocusState private var typing: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    joinPanel
                    ForEach(app.challenges) { c in Panel { ChallengeRow(c: c) } }
                    PresetsSection()   // #538
                    startRooms
                    offline
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(T2P.navy.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .overlay { if app.busy { ProgressView().controlSize(.large).padding(24).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
        }
        .sheet(isPresented: $scanning) {
            ScannerSheet { found in
                scanning = false
                code = found
                Task { await app.join(code: found) }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let logo = Art.image("t2p-logo") {
                    Image(uiImage: logo).resizable().scaledToFit().frame(height: 40).accessibilityLabel("Time2Play")
                }
                Spacer()
                Button { app.tab = .you } label: {
                    if let f = app.profile.face { FaceView(face: f, size: 40) }
                    else { Image(systemName: "person.crop.circle").font(.system(size: 34)).foregroundStyle(T2P.muted) }
                }
                .accessibilityLabel("You")
            }
            Text("Play").font(.largeTitle.bold()).foregroundStyle(T2P.text).accessibilityAddTraits(.isHeader)
                .padding(.top, 8)
        }
        .padding(.top, 8)
    }

    private var normalized: String? { RoomCode.normalize(code) }

    private var joinPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                Text("Join with a room code").font(.headline).foregroundStyle(T2P.muted)
                HStack(spacing: 10) {
                    CodeBoxes(code: $code, focused: $typing)
                    Button { scanning = true } label: {
                        Image(systemName: "qrcode.viewfinder").font(.title2.weight(.semibold))
                            .frame(width: 56, height: 64)
                            .foregroundStyle(T2P.gold)
                            .background(T2P.panelHi, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(T2P.line))
                    }
                    .accessibilityLabel("Scan the room’s QR code")
                    .accessibilityIdentifier("scan")
                }
                Button {
                    typing = false
                    if let c = normalized { Task { await app.join(code: c) } }
                } label: {
                    Text(normalized.map { "Join \($0)" } ?? "Join")
                }
                .buttonStyle(GoldButtonStyle())
                .disabled(normalized == nil || app.busy)
                .accessibilityIdentifier("join")
            }
        }
    }

    private var startRooms: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Start a room").font(.title2.bold()).foregroundStyle(T2P.text).accessibilityAddTraits(.isHeader).fixedSize()
                    Spacer()
                    Button("Library") { app.tab = .library }.foregroundStyle(T2P.goldText).fixedSize()
                }
                Text("Start a room").font(.title2.bold()).foregroundStyle(T2P.text).accessibilityAddTraits(.isHeader)
            }
            Text("Private: only people with the code or link can join. Bots can fill seats.")
                .font(.subheadline).foregroundStyle(T2P.muted)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                ForEach(Game.allCases) { g in
                    Button { Task { await app.start(g) } } label: { GameCard(game: g) }
                        .buttonStyle(.plain)
                        .disabled(app.busy)
                        .accessibilityIdentifier("start-\(g.rawValue)")
                }
            }
        }
    }
}

extension PlayView {
    /// Bots with no signal (#402): the server's own rules, run on the phone. Practice: nothing reaches the server.
    var offline: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No signal? Practice with bots").font(.title3.bold()).foregroundStyle(T2P.text).accessibilityAddTraits(.isHeader)
            Text("Same rules, played on this device. Practice games don’t count.").font(.subheadline).foregroundStyle(T2P.muted)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Game.allCases) { g in
                        Button { app.startOffline(g) } label: { Label(g.title, systemImage: "airplane") }
                            .buttonStyle(QuietButtonStyle())
                            .accessibilityLabel("Practice \(g.title) offline")
                            .accessibilityIdentifier("offline-\(g.rawValue)")
                    }
                }
            }
        }
    }
}

/// A game's Start card: its picture, its name, who it's for.
struct GameCard: View {
    let game: Game
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                game.tint
                if game == .overdraft, let a = Art.image("change_suit"), let b = Art.image("wave_7") {
                    HStack(spacing: -34) {
                        Image(uiImage: b).resizable().scaledToFit().rotationEffect(.degrees(-10))
                        Image(uiImage: a).resizable().scaledToFit().rotationEffect(.degrees(8))
                    }
                    .padding(.vertical, 10)
                } else {
                    Image(systemName: game.symbol).font(.system(size: 44)).foregroundStyle(.white.opacity(0.92))
                }
            }
            .frame(height: 96)
            .clipped()
            VStack(alignment: .leading, spacing: 2) {
                Text(game.title).font(.headline).foregroundStyle(T2P.text)
                Text(game.players).font(.subheadline).foregroundStyle(T2P.muted)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(T2P.panel)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(T2P.line))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Start \(game.title)")
        .accessibilityHint(game.blurb)
        .accessibilityAddTraits(.isButton)
    }
}

/// Four boxes over one text field: type, paste or dictate a code; VoiceOver reads it as one "Room code" field.
struct CodeBoxes: View {
    @Binding var code: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        ZStack {
            HStack(spacing: 8) {
                ForEach(0..<RoomCode.length, id: \.self) { i in
                    let chars = Array(code)
                    let ch = i < chars.count ? String(chars[i]) : ""
                    let current = focused.wrappedValue && i == min(chars.count, RoomCode.length - 1)
                    Text(ch)
                        .font(.system(.title, design: .rounded).weight(.bold))
                        .foregroundStyle(T2P.text)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(T2P.navy, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(ch.isEmpty && !current ? T2P.line : T2P.gold, lineWidth: current ? 2 : 1))
                }
            }
            .accessibilityHidden(true)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)   // four boxes across, at every text size
            .onTapGesture { focused.wrappedValue = true }
            TextField("", text: Binding(get: { code }, set: { code = RoomCode.partial($0) }))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .textContentType(.oneTimeCode)
                .focused(focused)
                .foregroundStyle(.clear)
                .tint(.clear)
                .frame(maxWidth: .infinity, minHeight: 64)
                .opacity(0.05)
                .accessibilityLabel("Room code")
                .accessibilityValue(code.isEmpty ? "Empty" : code.map(String.init).joined(separator: " "))
                .accessibilityIdentifier("room-code")
        }
    }
}
