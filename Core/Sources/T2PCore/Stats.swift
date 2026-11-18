import Foundation

/// Player stats (#540): wins, games played, best scores and favorite games. A signed-in player's come from the
/// account API the server is adding (wayloncore/tyleralocke#534); every field is optional, so an older or newer server
/// never breaks this. The phone also keeps its own ledger of finished games (online rooms only: practice doesn't
/// count), which is what earns the achievements that need a closer look than totals (a full Roll Call card).
public struct PlayerStats: Equatable, Sendable {
    public struct ForGame: Equatable, Sendable {
        public var played: Int = 0; public var wins: Int = 0; public var best: Int?
        public init(played: Int = 0, wins: Int = 0, best: Int? = nil) { self.played = played; self.wins = wins; self.best = best }
    }
    public var games: Int = 0
    public var wins: Int = 0
    public var byGame: [String: ForGame] = [:]
    /// Most played first (the server's order when it gives one).
    public var favorites: [String] = []
    public init() {}

    /// Reads `{ games, wins, byGame: { farkle: { played, wins, best } }, favorites: [...] }`, or the same under `stats`.
    /// Also takes `played` for games and `best: { game: score }`. Nil when there's nothing to read.
    public init?(_ j0: JSON) {
        let j = j0["stats"].object != nil ? j0["stats"] : j0
        guard j.object != nil else { return nil }
        games = j["games"].int ?? j["played"].int ?? 0
        wins = j["wins"].int ?? 0
        for (k, v) in j["byGame"].object ?? j["games"].object ?? [:] {
            byGame[k] = ForGame(played: v["played"].int ?? v["games"].int ?? 0, wins: v["wins"].int ?? 0, best: v["best"].int)
        }
        for (k, v) in j["best"].object ?? [:] {
            var g = byGame[k] ?? ForGame(); g.best = max(g.best ?? Int.min, v.int ?? Int.min); if g.best == Int.min { g.best = nil }
            byGame[k] = g
        }
        if games == 0 { games = byGame.values.map(\.played).reduce(0, +) }
        if wins == 0 { wins = byGame.values.map(\.wins).reduce(0, +) }
        favorites = j["favorites"].array.compactMap { $0.string ?? $0["game"].string }
        if favorites.isEmpty { favorites = PlayerStats.ranked(byGame) }
    }

    static func ranked(_ g: [String: ForGame]) -> [String] {
        g.filter { $0.value.played > 0 }.sorted { $0.value.played != $1.value.played ? $0.value.played > $1.value.played : $0.key < $1.key }.map(\.key)
    }

    /// The larger of each count (the server's totals and this phone's ledger can each know games the other doesn't).
    public func merged(with o: PlayerStats) -> PlayerStats {
        var m = PlayerStats()
        m.games = max(games, o.games); m.wins = max(wins, o.wins)
        for k in Set(byGame.keys).union(o.byGame.keys) {
            let a = byGame[k] ?? ForGame(), b = o.byGame[k] ?? ForGame()
            let best = [a.best, b.best].compactMap { $0 }.max()
            m.byGame[k] = ForGame(played: max(a.played, b.played), wins: max(a.wins, b.wins), best: best)
        }
        m.favorites = favorites.isEmpty ? o.favorites : favorites
        return m
    }
}

/// One finished online game, as this phone saw it. Saved data: add fields, never rename or remove.
public struct LedgerEntry: Codable, Equatable, Sendable {
    public var game: String
    public var won: Bool
    public var score: Int?
    /// What happened worth an achievement: "fullCard" (Roll Call, every box scored), "bullseye" (Close Enough, full
    /// points on a question), "target10k" (Hot Dice played to 10,000).
    public var flags: [String]
    public var at: Double
    public init(game: Game, won: Bool, score: Int?, flags: [String] = [], at: Double = Date().timeIntervalSince1970) {
        self.game = game.rawValue; self.won = won; self.score = score; self.flags = flags; self.at = at
    }
}

public enum Ledger {
    public static let max = 500
    public static func stats(_ l: [LedgerEntry]) -> PlayerStats {
        var s = PlayerStats()
        for e in l {
            var g = s.byGame[e.game] ?? PlayerStats.ForGame()
            g.played += 1; if e.won { g.wins += 1 }
            if let sc = e.score { g.best = Swift.max(g.best ?? sc, sc) }
            s.byGame[e.game] = g
        }
        s.games = l.count; s.wins = l.filter(\.won).count
        s.favorites = PlayerStats.ranked(s.byGame)
        return s
    }
    public static func adding(_ e: LedgerEntry, to l: [LedgerEntry]) -> [LedgerEntry] { Array((l + [e]).suffix(max)) }
    public static func decode(_ d: Data?) -> [LedgerEntry] { d.flatMap { try? JSONDecoder().decode([LedgerEntry].self, from: $0) } ?? [] }
    public static func encode(_ l: [LedgerEntry]) -> Data? { try? JSONEncoder().encode(l) }
}

/// The achievements (#540): original ones, earned on the phone from the stats and the ledger. The ids are also the
/// Game Center achievements' (#541).
public struct Achievement: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var detail: String
    public var symbol: String
    /// How far along, 0 to 1 (1 is earned).
    public var progress: @Sendable (PlayerStats, [LedgerEntry]) -> Double
    public static func == (a: Achievement, b: Achievement) -> Bool { a.id == b.id }

    public func earned(_ s: PlayerStats, _ l: [LedgerEntry]) -> Bool { progress(s, l) >= 1 }

    private static func count(_ n: Int, of goal: Int) -> Double { Swift.min(1, Double(n) / Double(goal)) }
    private static func flag(_ f: String, _ l: [LedgerEntry]) -> Double { l.contains { $0.flags.contains(f) } ? 1 : 0 }

    public static let all: [Achievement] = [
        Achievement(id: "t2p.first_win", title: "First win", detail: "Win a game.", symbol: "star.fill") { s, _ in count(s.wins, of: 1) },
        Achievement(id: "t2p.games_10", title: "Regular", detail: "Play 10 games.", symbol: "10.circle.fill") { s, _ in count(s.games, of: 10) },
        Achievement(id: "t2p.games_50", title: "Part of the furniture", detail: "Play 50 games.", symbol: "sofa.fill") { s, _ in count(s.games, of: 50) },
        Achievement(id: "t2p.wins_5", title: "On a roll", detail: "Win 5 games.", symbol: "flame.fill") { s, _ in count(s.wins, of: 5) },
        Achievement(id: "t2p.all_four", title: "All-rounder", detail: "Play all four games.", symbol: "square.grid.2x2.fill") { s, _ in
            count(Game.allCases.filter { (s.byGame[$0.rawValue]?.played ?? 0) > 0 }.count, of: 4)
        },
        Achievement(id: "t2p.overdraft_win", title: "Empty-handed", detail: "Win a hand of Overdraft.", symbol: "rectangle.stack.fill") { s, _ in
            count(s.byGame[Game.overdraft.rawValue]?.wins ?? 0, of: 1)
        },
        Achievement(id: "t2p.hotdice_10k", title: "Ten thousand", detail: "Win a Hot Dice game played to 10,000.", symbol: "dice.fill") { _, l in
            l.contains { $0.game == Game.hotDice.rawValue && $0.won && $0.flags.contains("target10k") } ? 1 : 0
        },
        Achievement(id: "t2p.rollcall_full", title: "Full card", detail: "Finish Roll Call with points in every box.", symbol: "checklist") { _, l in flag("fullCard", l) },
        Achievement(id: "t2p.rollcall_300", title: "Three hundred club", detail: "Score 300 or more in Roll Call.", symbol: "die.face.5.fill") { s, _ in
            (s.byGame[Game.rollCall.rawValue]?.best ?? 0) >= 300 ? 1 : count(s.byGame[Game.rollCall.rawValue]?.best ?? 0, of: 300) * 0.99
        },
        Achievement(id: "t2p.closeenough_bullseye", title: "Bullseye", detail: "Score full points on a Close Enough question.", symbol: "scope") { _, l in flag("bullseye", l) },
    ]
}

extension API {
    /// A signed-in player's stats (#534's account API): nil while the server doesn't have them yet (a 404).
    public func stats() async throws -> PlayerStats? {
        do { return PlayerStats(try await call(endpoints.api("live/players/stats"), auth: true)) }
        catch let f as Failure where f.status == 404 { return nil }
    }
}
