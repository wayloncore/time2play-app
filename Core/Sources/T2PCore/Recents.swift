import Foundation

/// A room this phone was in, for Play's "Recent rooms" and the home screen widget's rejoin. Saved data (UserDefaults
/// "t2p.recentRooms", and the widget's shared copy): add fields, never rename or remove them.
public struct RecentRoom: Codable, Equatable, Sendable, Identifiable {
    public var code: String
    public var game: String          // Game's raw value ("overdraft", "farkle"…), kept as text so a new game reads
    public var at: Date
    public var id: String { code }
    public var playable: Game? { Game(rawValue: game) }

    public init(code: String, game: Game, at: Date = Date()) { self.code = code; self.game = game.rawValue; self.at = at }

    /// How long a room is worth offering again: rooms close well before a day is out (the seats go then too).
    public static let keepFor: TimeInterval = 86_400
    /// How many Play shows.
    public static let shown = 5

    /// The list with this room put first (once), the oldest dropped past the limit and anything past a day gone.
    public static func adding(_ r: RecentRoom, to list: [RecentRoom], now: Date = Date(), limit: Int = 8) -> [RecentRoom] {
        let rest = list.filter { $0.code != r.code && now.timeIntervalSince($0.at) < keepFor }
        return Array(([r] + rest).prefix(limit))
    }

    /// The ones still young enough to try, newest first.
    public static func fresh(_ list: [RecentRoom], now: Date = Date()) -> [RecentRoom] {
        list.filter { now.timeIntervalSince($0.at) < keepFor }.sorted { $0.at > $1.at }
    }
}

extension Library {
    /// The game of the day (the home screen widget): one Library card per day, the same for everyone on that day,
    /// stepping through the Library in a fixed order so every card comes round. Nil for an empty Library.
    public func gameOfTheDay(_ date: Date = Date(), calendar: Calendar = .current) -> Item? {
        let cards = items.sorted { $0.key < $1.key }
        guard !cards.isEmpty else { return nil }
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        // a day number that doesn't depend on the time zone's offset: days since 2026-01-01 on the local calendar
        var start = DateComponents(); start.year = 2026; start.month = 1; start.day = 1
        guard let from = calendar.date(from: start), let today = calendar.date(from: c),
              let days = calendar.dateComponents([.day], from: from, to: today).day else { return cards[0] }
        // a stride that's coprime with the count, so neighbors in the key order don't come up on neighboring days
        let n = cards.count
        var step = 7
        while gcd(step, n) != 1 { step += 1 }
        let i = ((days * step) % n + n) % n
        return cards[i]
    }

    private func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }

    /// The four games in the app, as Library cards: the widget's game of the day before the Library has loaded.
    public static var appOnly: Library {
        Library(categories: [], items: Game.allCases.map {
            Item(key: $0.rawValue, title: $0.title, category: "", blurb: nil, thumb: nil, page: "/library/\($0.rawValue)",
                 players: nil, phones: nil, game: $0)
        })
    }
}

extension API {
    /// Whether a room is still open (Play's recent rooms): in use and not ended. A failed check counts as closed.
    public func isOpen(_ g: Game, code: String) async -> Bool {
        guard let j = try? await call(endpoints.exists(g, code: code)) else { return false }
        return j["inUse"].bool == true && j["ended"].bool != true
    }
}
