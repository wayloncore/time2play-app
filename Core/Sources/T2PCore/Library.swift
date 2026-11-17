import Foundation

/// The Library, read from the server (/live/library.json on tyleralocke.com, #399): the same cards the website's
/// Library shows, less the ones named after real TV game shows (#487: the feed marks them `showName`; App Review
/// checks names for trademarks). The app keeps the last copy it read, so the Library opens with no signal.
public struct Library: Equatable, Sendable {
    public struct Category: Equatable, Sendable, Identifiable { public var id: String; public var name: String; public var line: String }
    public struct Item: Equatable, Sendable, Identifiable {
        public var key: String; public var title: String; public var category: String; public var blurb: String?
        public var thumb: String?; public var page: String
        public var players: (Int, Int)?; public var phones: String?
        public var game: Game?            // one of the app's own games: it starts here, in the app
        public var id: String { key }
        public static func == (a: Item, b: Item) -> Bool {
            a.key == b.key && a.title == b.title && a.category == b.category && a.blurb == b.blurb && a.thumb == b.thumb
                && a.page == b.page && a.players?.0 == b.players?.0 && a.players?.1 == b.players?.1 && a.phones == b.phones && a.game == b.game
        }
        /// "2–8 players", or nil.
        public var playersLine: String? {
            guard let p = players else { return nil }
            return p.0 == p.1 ? "\(p.0) player\(p.0 == 1 ? "" : "s")" : "\(p.0)–\(p.1) players"
        }
    }
    public var categories: [Category]
    public var items: [Item]

    public init(categories: [Category] = [], items: [Item] = []) { self.categories = categories; self.items = items }

    /// Reads the feed; anything it doesn't know is skipped. Nil if it isn't the feed at all.
    public init?(_ j: JSON) {
        guard j["v"].int != nil, case .array = j["items"] else { return nil }
        categories = j["categories"].array.compactMap {
            guard let id = $0["id"].string, let name = $0["name"].string else { return nil }
            return Category(id: id, name: name, line: $0["line"].string ?? "")
        }
        items = j["items"].array.compactMap {
            // #487: a card named after a real TV game show (the feed marks it) stays on the website, not in the app
            guard let key = $0["key"].string, let title = $0["title"].string, $0["showName"].bool != true else { return nil }
            let p = $0["facts"]["players"].array.compactMap(\.int)
            let game = $0["app"].string.flatMap(Game.init(rawValue:))
            return Item(key: key, title: game != nil ? ($0["appTitle"].string ?? title) : title,
                        category: $0["category"].string ?? "", blurb: $0["blurb"].string.map(Library.plain), thumb: $0["thumb"].string,
                        page: $0["page"].string ?? "/library/\(key)", players: p.count == 2 ? (p[0], p[1]) : nil,
                        phones: $0["facts"]["phones"].string, game: game)
        }
    }

    /// A blurb as plain words: some website blurbs carry HTML (<strong>, &amp;), which a Text would show as-is.
    public static func plain(_ html: String) -> String {
        var t = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (e, c) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&rsquo;", "’"),
                       ("&lsquo;", "‘"), ("&ldquo;", "“"), ("&rdquo;", "”"), ("&mdash;", "—"), ("&ndash;", "–"), ("&amp;", "&")] {
            t = t.replacingOccurrences(of: e, with: c)
        }
        return t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The cards in one category, in the Library's order.
    public func items(in category: Category) -> [Item] { items.filter { $0.category == category.name } }

    /// Cards whose title or blurb holds every word searched for.
    public func search(_ text: String) -> [Item] {
        let words = text.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return items }
        return items.filter { i in
            let hay = (i.title + " " + (i.blurb ?? "") + " " + i.category).lowercased()
            return words.allSatisfy { hay.contains($0) }
        }
    }

    /// The app's games, as the Library lists them (for Start a room when the feed hasn't loaded, the four are fixed).
    public var appGames: [Game] {
        var seen: [Game] = []
        for i in items { if let g = i.game, !seen.contains(g) { seen.append(g) } }
        return seen
    }
}

extension API {
    public func library() async throws -> (Library, Data) {
        let j = try await call(endpoints.api("live/library.json"))
        guard let lib = Library(j) else { throw Failure(status: 0, message: "The Library didn’t load. Try again.", code: nil) }
        return (lib, Data(j.text.utf8))
    }
}
