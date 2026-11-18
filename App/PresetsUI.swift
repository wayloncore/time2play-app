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
    @State private var longPressed = false

    var body: some View {
        if let g = preset.gameValue {
            Button {
                if longPressed { longPressed = false; return }   // the long press asked instead
                go(offline: preset.offline == true)
            } label: { PresetCard(preset: preset, game: g) }
                .buttonStyle(.plain)
                .disabled(app.busy)
                // a long press: the painted choices (Nov 18; was an iOS menu)
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in longPressed = true; menu() })
                .accessibilityLabel("Start \(preset.name), \(g.title), \(preset.summary)")
                .accessibilityAction(named: "Practice offline") { go(offline: true) }
                .accessibilityAction(named: "Delete preset") { askDelete() }
                .accessibilityIdentifier("preset-\(index)")
        }
    }

    private func menu() {
        AppDialogs.shared.show(GameDialog(title: preset.name, message: preset.gameValue.map { "\($0.title) · \(preset.summary)" },
            choices: [GameChoice(label: "Start a room", kind: .gold, icon: "person.3", identifier: "preset-start") { go(offline: false) },
                      GameChoice(label: "Practice offline", icon: "airplane", identifier: "preset-offline") { go(offline: true) },
                      GameChoice(label: "Delete preset", kind: .danger, icon: "trash", identifier: "preset-delete") { askDelete() }],
            cancel: "Back", identifier: "dialog-preset"))
    }

    private func askDelete() {
        let p = preset
        AppDialogs.shared.show(GameDialog(title: "Delete “\(p.name)”?", message: "It comes off Play. Rooms you started from it carry on.",
            choices: [GameChoice(label: "Delete preset", kind: .danger, identifier: "preset-delete-confirm") { PresetStore.shared.delete(p) }],
            cancel: "Keep it", identifier: "dialog-preset-delete"))
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
            GameArt(game: game).frame(width: 56, height: 44).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
    @Environment(\.gameDialogs) private var dialogs
    var body: some View {
        Button { ask() } label: {
            Label("Save as a preset", systemImage: "bookmark").font(.footnote.weight(.semibold))
        }
        .foregroundStyle(T2P.goldText)
        .accessibilityIdentifier("save-preset")
    }

    /// Naming it, painted (Nov 18; was an iOS alert with a text field).
    private func ask() {
        let r = room
        let field = DialogField("\(room.game.title) night", placeholder: "Name", identifier: "preset-name", limit: 30)
        let d = GameDialog(title: "Save these settings", message: "The game, its bots and the house rules, ready to start again in one tap.",
                           choices: [GameChoice(label: "Save", kind: .gold, identifier: "preset-save") {
                               let n = field.trimmed
                               guard !n.isEmpty, let v = r.view else { return }
                               PresetStore.shared.save(Preset.capture(name: n, game: r.game, view: v, offline: r.offline))
                               r.toast = "Saved. It’s on Play, under Your presets."
                               Haptics.select()
                           }],
                           identifier: "dialog-save-preset", field: field)
        if let dialogs { dialogs.show(d) } else { AppDialogs.shared.show(d) }
    }
}
