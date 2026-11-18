import SwiftUI
import WidgetKit
import T2PCore

/// What Play remembers on this phone: your recent rooms (to rejoin while they're open) and the games you starred.
/// Saved data (UserDefaults "t2p.recentRooms", "t2p.favoriteGames"): new keys; add fields, never rename or remove.
@MainActor
final class Keepsakes: ObservableObject {
    static let recentKey = "t2p.recentRooms"
    static let favoritesKey = "t2p.favoriteGames"

    @Published private(set) var recents: [RecentRoom]
    @Published private(set) var favorites: [String]
    /// The recent rooms the server says are still open (checked when Play shows).
    @Published private(set) var open: [RecentRoom] = []
    /// A Library card to show (the widget's game of the day): the Library tab searches for it.
    @Published var focus: String?

    init() {
        recents = UserDefaults.standard.data(forKey: Keepsakes.recentKey).flatMap { try? JSONDecoder().decode([RecentRoom].self, from: $0) } ?? []
        favorites = UserDefaults.standard.stringArray(forKey: Keepsakes.favoritesKey) ?? []
    }

    func remember(code: String, game: Game) {
        let r = RecentRoom(code: code, game: game)
        recents = RecentRoom.adding(r, to: recents)
        UserDefaults.standard.set(try? JSONEncoder().encode(recents), forKey: Keepsakes.recentKey)
        if !open.contains(where: { $0.code == code }) { open.insert(r, at: 0) }
        SharedRoom.save(r)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Who's in a room right now (seats, bots, the other people's names) and whether it's a solo room, saved on its
    /// recent-rooms entry when this phone steps away from it (the room closed on screen, the app went to the
    /// background). Only updates an entry already there: a confirmed Leave has already taken the room off.
    func note(_ r: RoomModel) {
        guard !r.offline, let i = recents.firstIndex(where: { $0.code == r.code }) else { return }
        let ps = r.lobbyPlayers
        guard !ps.isEmpty else { return }
        var e = recents[i]
        e.players = ps.count
        e.bots = ps.filter { $0.bot != nil }.count
        e.others = Array(ps.filter { $0.bot == nil && $0.id != r.meId }.map(\.name).prefix(4))
        e.solo = r.isSolo
        e.at = Date()
        recents[i] = e
        if let j = open.firstIndex(where: { $0.code == r.code }) { open[j] = e }
        UserDefaults.standard.set(try? JSONEncoder().encode(recents), forKey: Keepsakes.recentKey)
    }

    func forget(_ code: String) {
        recents.removeAll { $0.code == code }
        open.removeAll { $0.code == code }
        UserDefaults.standard.set(try? JSONEncoder().encode(recents), forKey: Keepsakes.recentKey)
        if SharedRoom.load()?.code == code { SharedRoom.clear(); WidgetCenter.shared.reloadAllTimelines() }
    }

    /// Asks the server which recent rooms are still open; the closed ones drop off Play (they stay saved for a day).
    func refreshOpen(_ api: API) async {
        let fresh = Array(RecentRoom.fresh(recents).prefix(RecentRoom.shown))
        let checked = await withTaskGroup(of: (RecentRoom, Bool).self) { g -> [String: Bool] in
            for r in fresh {
                guard let game = r.playable else { continue }
                g.addTask { (r, await api.isOpen(game, code: r.code)) }
            }
            var out: [String: Bool] = [:]
            for await (r, ok) in g { out[r.code] = ok }
            return out
        }
        open = fresh.filter { checked[$0.code] == true }
    }

    func isFavorite(_ g: Game) -> Bool { favorites.contains(g.rawValue) }
    func toggleFavorite(_ g: Game) {
        if let i = favorites.firstIndex(of: g.rawValue) { favorites.remove(at: i) } else { favorites.append(g.rawValue) }
        UserDefaults.standard.set(favorites, forKey: Keepsakes.favoritesKey)
        Haptics.select()
    }
    /// The games for Start a room: starred ones first, each group in the usual order.
    func ordered(_ games: [Game]) -> [Game] { games.filter(isFavorite) + games.filter { !isFavorite($0) } }
}

extension RoomModel {
    /// A solo room (Tyler, Nov 18: Rejoin "is for solo not live games"): Roll Call or Close Enough on the server with
    /// nobody else in it but bots. Leave keeps a solo room in Recent rooms, seat and all, to pick it back up; a live
    /// room (anyone else in it, or Overdraft and Hot Dice, which need others) leaves Recent rooms on a confirmed Leave.
    var isSolo: Bool {
        guard !offline, game == .rollCall || game == .closeEnough else { return false }
        return !lobbyPlayers.contains { $0.bot == nil && $0.id != meId }
    }
}

extension AppModel {
    func remember(code: String, game: Game) { keep.remember(code: code, game: game) }

    /// A "your turn" alert, or the widget's rejoin: if you're already in that room, stay; otherwise join it.
    func openRoom(code: String) async {
        if let r = room, r.code == code { r.resume(); return }
        await join(code: code)
    }

    /// The widget's game of the day: the Library, searched for that card.
    func showLibraryItem(_ key: String) {
        tab = .library
        keep.focus = key
    }
}

/// Play's recent rooms: the ones still open, newest first; a tap rejoins (your seat comes back if it's still held).
struct RecentRoomsPanel: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var keep: Keepsakes

    var body: some View {
        Group {
            if !keep.open.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Recent rooms").font(.title3.bold()).foregroundStyle(T2P.text).accessibilityAddTraits(.isHeader)
                    VStack(spacing: 0) {
                        ForEach(Array(keep.open.enumerated()), id: \.element.code) { i, r in
                            if i > 0 { Divider().overlay(T2P.line) }
                            row(r)
                        }
                    }
                    .background(T2P.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(T2P.line))
                }
                .accessibilityIdentifier("recent-rooms")
            }
        }
        .task { await keep.refreshOpen(app.api) }
    }

    private func row(_ r: RecentRoom) -> some View {
        RecentRoomRow(r: r, keep: keep)
    }
}

/// One recent room: the game's own picture, its name, who's in it, the code smaller, and Rejoin (a live room you
/// dropped out of) or Resume (a solo one). A long press asks, painted, whether to take it off the list.
struct RecentRoomRow: View {
    @EnvironmentObject var app: AppModel
    let r: RecentRoom
    @ObservedObject var keep: Keepsakes
    @State private var longPressed = false

    var body: some View {
        let g = r.playable
        let solo = r.solo == true
        let verb = solo ? "Resume" : "Rejoin"
        Button {
            if longPressed { longPressed = false; return }   // the long press asked instead
            Task { await app.openRoom(code: r.code) }
        } label: {
            GameRowLabel(game: g, title: g?.title ?? "A game", tag: solo ? "Solo" : "Live", line: r.whoLine,
                         small: "Room \(r.code) · \(r.at.formatted(.relative(presentation: .named)))", action: verb)
                .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .disabled(app.busy)
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in longPressed = true; askRemove() })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(["\(verb) \(g?.title ?? "the game")", solo ? "solo" : "live", r.whoLine, "room \(r.code)"].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { Task { await app.openRoom(code: r.code) } }
        .accessibilityAction(named: "Remove from recent rooms") { askRemove() }
        .accessibilityIdentifier("rejoin-\(r.code)")
    }

    private func askRemove() {
        let code = r.code
        let k = keep
        AppDialogs.shared.show(GameDialog(
            title: "Remove room \(code)?", message: "It comes off Recent rooms on this phone. The room itself carries on.",
            choices: [GameChoice(label: "Remove it", kind: .danger, identifier: "recent-remove") { k.forget(code) }],
            cancel: "Keep it", identifier: "dialog-recent-remove"))
    }
}

/// The star on a game's Start card.
struct FavoriteStar: View {
    @ObservedObject var keep: Keepsakes
    let game: Game
    var body: some View {
        let on = keep.isFavorite(game)
        Button { withAnimation(.snappy) { keep.toggleFavorite(game) } } label: {
            Image(systemName: on ? "star.fill" : "star")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(on ? T2P.gold : .white.opacity(0.85))
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.28), in: Circle().inset(by: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(on ? "Remove \(game.title) from favorites" : "Add \(game.title) to favorites")
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("favorite-\(game.rawValue)")
    }
}
