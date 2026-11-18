import Foundation

/// Quick-start presets (#538): a room's settings saved by name (the game, its bots, its house rules and timers), and
/// started again in one tap. Kept on the phone. Saved data: add fields, never rename or remove.
public struct Preset: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var game: String           // Game.rawValue, so a preset for a game a later version drops still reads
    public var bots: [String]         // bot levels, in the order they were added
    public var options: [String: JSON] // the house rules, as the room's options message takes them
    public var created: Double
    public var offline: Bool?         // made in a practice room: starts offline by default

    public init(id: String = UUID().uuidString, name: String, game: Game, bots: [String], options: [String: JSON],
                created: Double = Date().timeIntervalSince1970, offline: Bool? = nil) {
        self.id = id; self.name = name; self.game = game.rawValue; self.bots = bots; self.options = options
        self.created = created; self.offline = offline
    }

    public var gameValue: Game? { Game(rawValue: game) }
    public static let nameMax = 24
    public static let max = 12

    /// A room's settings now, read from the owner's lobby view.
    public static func capture(name: String, game: Game, view: JSON, offline: Bool) -> Preset {
        let list = game == .overdraft ? view["roster"].array : view["players"].array.filter { $0["left"].bool != true }
        let bots = list.compactMap { $0["bot"].string }
        return Preset(name: String(name.trimmingCharacters(in: .whitespaces).prefix(nameMax)), game: game, bots: bots,
                      options: options(game: game, view: view), offline: offline ? true : nil)
    }

    /// The house rules a lobby's view shows, as the options message sends them.
    public static func options(game: Game, view v: JSON) -> [String: JSON] {
        var o: [String: JSON] = [:]
        func put(_ k: String, _ j: JSON) { if !j.isNull { o[k] = j } }
        switch game {
        case .overdraft: put("jumpIn", v["jumpIn"]); put("stacking", v["stacking"])
        case .hotDice: put("ones", v["ones"]); put("target", v["target"]); put("board", v["rules"]["board"]); put("three", v["rules"]["three"])
        case .rollCall: put("quick", v["quick"])
        case .closeEnough: put("set", v["opts"]["set"]); put("count", v["opts"]["count"]); put("timer", v["opts"]["timer"])
        }
        return o
    }

    /// The bots still to add to a lobby that has `seated` (the other games' bots are one each, by name).
    public func botsToAdd(seated: [String], game: Game) -> [String] {
        guard game != .overdraft else { return Array(bots.dropFirst(seated.count)) }
        var have = Set(seated)
        return bots.filter { have.insert($0).inserted }
    }

    static func grouped(_ n: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.locale = Locale(identifier: "en_US")
        return f.string(from: NSNumber(value: n)) ?? String(n)
    }

    /// A line for the preset's button: "2 bots · Play to 5,000".
    public var summary: String {
        var parts: [String] = []
        parts.append(bots.isEmpty ? "no bots" : "\(bots.count) bot\(bots.count == 1 ? "" : "s")")
        if let t = options["target"]?.int { parts.append("to \(Preset.grouped(t))") }
        if options["quick"]?.bool == true { parts.append("quick") }
        if let n = options["count"]?.int { parts.append("\(n) questions") }
        if let s = options["timer"]?.int { parts.append("\(s)s each") }
        if options["jumpIn"]?.bool == true { parts.append("Jump-in") }
        if options["stacking"]?.bool == true { parts.append("Stacking") }
        if offline == true { parts.append("offline") }
        return parts.joined(separator: " · ")
    }
}

/// The presets list as it's saved: newest first, at most 12, names unique per game (saving the same name replaces it).
public enum Presets {
    public static func adding(_ p: Preset, to list: [Preset]) -> [Preset] {
        var l = list.filter { !($0.game == p.game && $0.name.lowercased() == p.name.lowercased()) }
        l.insert(p, at: 0)
        return Array(l.prefix(Preset.max))
    }
    public static func decode(_ d: Data?) -> [Preset] { d.flatMap { try? JSONDecoder().decode([Preset].self, from: $0) } ?? [] }
    public static func encode(_ l: [Preset]) -> Data? { try? JSONEncoder().encode(l) }
}
