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
        let g = r.playable
        return Button { Task { await app.openRoom(code: r.code) } } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(g?.tint ?? T2P.panelHi)
                    Image(systemName: g?.symbol ?? "gamecontroller.fill").font(.title3).foregroundStyle(.white.opacity(0.92))
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(g?.title ?? "A game").font(.headline).foregroundStyle(T2P.text)
                    Text("Room \(r.code) · \(r.at.formatted(.relative(presentation: .named)))").font(.subheadline).foregroundStyle(T2P.muted)
                }
                Spacer(minLength: 8)
                Text("Rejoin").font(.subheadline.weight(.semibold)).foregroundStyle(T2P.ink)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(T2P.gold, in: Capsule())
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(app.busy)
        .contextMenu { Button("Remove from recent rooms", role: .destructive) { keep.forget(r.code) } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rejoin \(g?.title ?? "the game"), room \(r.code)")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("rejoin-\(r.code)")
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
