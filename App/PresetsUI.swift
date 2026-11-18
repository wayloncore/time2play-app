import SwiftUI
import T2PCore

/// Quick-start presets (#538), kept on this phone (UserDefaults "t2p.presets").
@MainActor
final class PresetStore: ObservableObject {
    static let shared = PresetStore()
    static let key = "t2p.presets"
    @Published private(set) var list: [Preset]

    init() {
        if ProcessInfo.processInfo.arguments.contains("-uitest-reset") { UserDefaults.standard.removeObject(forKey: PresetStore.key) }
        list = Presets.decode(UserDefaults.standard.data(forKey: PresetStore.key))
    }
    func save(_ p: Preset) { list = Presets.adding(p, to: list); write() }
    func delete(_ p: Preset) { list.removeAll { $0.id == p.id }; write() }
    private func write() { UserDefaults.standard.set(Presets.encode(list), forKey: PresetStore.key) }
}

extension RoomModel {
    /// Puts a preset's house rules and bots into this room once its owner is in the lobby (#538).
    func applyPreset() {
        guard let p = preset, isOwner, phase == "lobby", view != nil else { return }
        preset = nil
        if !p.options.isEmpty { send(Out.options(p.options)) }
        let seated = lobbyPlayers.compactMap(\.bot)
        let room = max(0, game.maxPlayers - lobbyPlayers.count)
        for b in p.botsToAdd(seated: seated, game: game).prefix(room) { send(Out.addBot(level: b)) }
        toast = "Set up from “\(p.name)”"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in if self?.toast?.hasPrefix("Set up from") == true { self?.toast = nil } }
    }
}

/// Play → "Your presets": one tap starts a room set up the saved way. Long-press for offline practice or Delete.
struct PresetsSection: View {
    @ObservedObject private var store = PresetStore.shared

    var body: some View {
        if !store.list.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Your presets").font(.title3.bold()).foregroundStyle(T2P.text).accessibilityAddTraits(.isHeader)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(store.list.enumerated()), id: \.element.id) { i, p in
                            PresetButton(preset: p, index: i)
                        }
                    }
                }
            }
        }
    }
}

/// One preset on Play.
struct PresetButton: View {
    @EnvironmentObject var app: AppModel
    let preset: Preset
    let index: Int

    var body: some View {
        if let g = preset.gameValue {
            Button { go(offline: preset.offline == true) } label: { PresetCard(preset: preset, game: g) }
                .buttonStyle(.plain)
                .disabled(app.busy)
                .contextMenu { menu }
                .accessibilityLabel("Start \(preset.name), \(g.title), \(preset.summary)")
                .accessibilityAction(named: "Practice offline") { go(offline: true) }
                .accessibilityAction(named: "Delete preset") { PresetStore.shared.delete(preset) }
                .accessibilityIdentifier("preset-\(index)")
        }
    }

    @ViewBuilder private var menu: some View {
        Button { go(offline: false) } label: { Label("Start a room", systemImage: "person.3") }
        Button { go(offline: true) } label: { Label("Practice offline", systemImage: "airplane") }
        Button(role: .destructive) { PresetStore.shared.delete(preset) } label: { Label("Delete preset", systemImage: "trash") }
    }

    private func go(offline: Bool) {
        let p = preset
        let a = app
        Task { @MainActor in
            guard let g = p.gameValue else { return }
            if offline { a.startOffline(g) } else { await a.start(g) }
            a.room?.preset = p
        }
    }
}

struct PresetCard: View {
    let preset: Preset
    let game: Game
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: game.symbol).font(.title2).foregroundStyle(.white.opacity(0.92))
                .frame(width: 44, height: 44).background(game.tint, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(preset.name).font(.headline).foregroundStyle(T2P.text).lineLimit(1)
                Text(game.title + " · " + preset.summary).font(.caption).foregroundStyle(T2P.muted).lineLimit(1)
            }
        }
        .padding(10)
        .frame(width: 250, alignment: .leading)
        .background(T2P.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(T2P.line))
    }
}

/// The lobby's "Save as a preset" (the room's owner): names this room's game, bots and house rules.
struct SavePresetButton: View {
    @ObservedObject var room: RoomModel
    @State private var asking = false
    @State private var name = ""
    var body: some View {
        Button { name = "\(room.game.title) night"; asking = true } label: {
            Label("Save as a preset", systemImage: "bookmark").font(.footnote.weight(.semibold))
        }
        .foregroundStyle(T2P.goldText)
        .accessibilityIdentifier("save-preset")
        .alert("Save these settings", isPresented: $asking) {
            TextField("Name", text: $name).accessibilityIdentifier("preset-name")
            Button("Save") {
                let n = name.trimmingCharacters(in: .whitespaces)
                guard !n.isEmpty, let v = room.view else { return }
                PresetStore.shared.save(Preset.capture(name: n, game: room.game, view: v, offline: room.offline))
                room.toast = "Saved. It’s on Play, under Your presets."
                Haptics.select()
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("The game, its bots and the house rules, ready to start again in one tap.") }
    }
}
