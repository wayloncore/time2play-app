import Foundation

/// Overdraft's cards and views, as the room sends them (src/live/overdraft/room-core.cjs viewFor in the website repo).
public enum Overdraft {
    public static let suits = ["ember", "wave", "bolt", "leaf"]
    public static let suitNames = ["ember": "Ember", "wave": "Wave", "bolt": "Bolt", "leaf": "Leaf"]
    /// The fewest players a hand is dealt to (TABLE_MIN); bots count.
    public static let tableMin = 3

    public struct Card: Equatable, Hashable, Sendable, Identifiable {
        public var id: String        // only in a hand; a table's cards carry none
        public var kind: String      // number, reverse, skip, draw2, wild, wild4
        public var suit: String?     // nil for wild and wild4 in a hand; the named suit isn't on the card
        public var n: Int?
        public var k: Int?           // a table pile card's place in the pile (fixes how it lies)

        public init(id: String = "", kind: String, suit: String?, n: Int? = nil, k: Int? = nil) {
            self.id = id; self.kind = kind; self.suit = suit; self.n = n; self.k = k
        }
        init(_ j: JSON) {
            id = j["id"].string ?? ""; kind = j["kind"].string ?? "number"; suit = j["suit"].string
            n = j["n"].int; k = j["k"].int
        }

        public var isWild: Bool { kind == "wild" || kind == "wild4" }

        /// The words a card is read as: "Wave 7", "Bolt Skip", "Ember +2", "Change Suit", "+4".
        public var label: String {
            let s = suit.flatMap { Overdraft.suitNames[$0] }
            switch kind {
            case "number": return [s, n.map(String.init)].compactMap { $0 }.joined(separator: " ")
            case "reverse": return [s, "Reverse"].compactMap { $0 }.joined(separator: " ")
            case "skip": return [s, "Skip"].compactMap { $0 }.joined(separator: " ")
            case "draw2": return [s, "+2"].compactMap { $0 }.joined(separator: " ")
            case "wild": return "Change Suit"
            case "wild4": return "+4"
            default: return kind
            }
        }

        /// What VoiceOver says: "Draw Two" spelled out, so "+2" isn't read as "plus two" in a way that's unclear.
        public var spoken: String {
            let s = suit.flatMap { Overdraft.suitNames[$0] }
            switch kind {
            case "draw2": return [s, "Draw Two"].compactMap { $0 }.joined(separator: " ")
            case "wild4": return "Draw Four"
            default: return label
            }
        }

        /// The art file this card is drawn with (the website's own card art, bundled in the app).
        public var artName: String {
            switch kind {
            case "wild": return "change_suit"
            case "wild4": return "draw_four"
            case "number": return "\(suit ?? "wave")_\(n ?? 0)"
            default: return "\(suit ?? "wave")_\(kind)"
            }
        }
    }

    public struct Seat: Equatable, Sendable, Identifiable {
        public var id: String; public var seat: Int; public var name: String; public var face: Int
        public var cards: Int; public var connected: Bool; public var held: Bool
        init(_ j: JSON) {
            id = j["id"].string ?? ""; seat = j["seat"].int ?? 0; name = j["name"].string ?? ""
            face = j["face"].int ?? 0; cards = j["cards"].int ?? 0
            connected = j["connected"].bool ?? true; held = j["held"].bool ?? false
        }
    }

    public struct Table: Equatable, Sendable {
        public var n: Int?
        public var turnEndsAt: Double?
        public var suit: String?
        public var top: Card?
        public var pile: [Card]
        public var stack: Int
        public var jumpIn: Bool
        public var seq: Int
        public var jumpBy: String?
        public var taking: Bool
        public var direction: Int
        public var drawLeft: Int
        public var turn: String?
        public var over: Bool
        public var winner: String?
        public var seats: [Seat]
        init(_ j: JSON) {
            n = j["n"].int; turnEndsAt = j["turnEndsAt"].double; suit = j["suit"].string
            top = j["top"].isNull ? nil : Card(j["top"]); pile = j["pile"].array.map(Card.init)
            stack = j["stack"].int ?? 0; jumpIn = j["jumpIn"].bool ?? false; seq = j["seq"].int ?? 0
            jumpBy = j["jump"]["id"].string; taking = j["taking"].bool ?? false
            direction = j["direction"].int ?? 1; drawLeft = j["drawLeft"].int ?? 0
            turn = j["turn"].string; over = j["over"].bool ?? false; winner = j["winner"].string
            seats = j["seats"].array.map(Seat.init)
        }
    }

    /// One phone's view: the lobby (roster, house rules) or the table (its own hand and everyone's counts).
    public struct View: Equatable, Sendable {
        public var phase: String          // lobby | playing | done
        public var code: String
        public var me: RoomPlayer
        public var hostless: Bool
        public var owner: String?
        public var stacking: Bool
        public var jumpIn: Bool
        public var roster: [RoomPlayer]
        public var table: Table?
        public var yourTurn: Bool
        public var hand: [Card]
        public var legal: Set<String>
        public var jump: Set<String>
        public var drawn: String?
        public var held: Bool
        public var tournament: Bool       // a tournament is on (tour); the app shows the board in words only

        public init(_ j: JSON) {
            phase = j["phase"].string ?? "lobby"; code = j["code"].string ?? ""
            me = RoomPlayer(j["you"]); hostless = j["hostless"].bool ?? false; owner = j["owner"].string
            stacking = j["stacking"].bool ?? false; jumpIn = j["jumpIn"].bool ?? false
            roster = j["roster"].array.map(RoomPlayer.init)
            table = j["table"].object == nil ? nil : Table(j["table"])
            yourTurn = j["yourTurn"].bool ?? false; hand = j["hand"].array.map(Card.init)
            legal = Set(j["legal"].array.compactMap(\.string)); jump = Set(j["jump"].array.compactMap(\.string))
            drawn = j["drawn"].string; held = j["held"].bool ?? false
            tournament = !j["tour"].isNull
        }

        public var isOwner: Bool { hostless && owner == me.id }
        public var atTable: Bool { table != nil }

        /// "Match Wave or 4", for the line under Your turn.
        public var matchLine: String? {
            guard let t = table, let top = t.top else { return nil }
            if t.stack > 0 { return "Add to the +\(t.stack) or take it" }
            let suit = (t.suit ?? top.suit).flatMap { Overdraft.suitNames[$0] }
            let what: String? = top.kind == "number" ? top.n.map(String.init) : (top.isWild ? nil : Card(kind: top.kind, suit: nil).label)
            return "Match " + [suit, what].compactMap { $0 }.joined(separator: " or ")
        }
    }
}

/// A player as a lobby lists them.
public struct RoomPlayer: Equatable, Sendable, Identifiable {
    public var id: String; public var name: String; public var face: Int
    public var connected: Bool; public var bot: String?
    public init(id: String, name: String, face: Int, connected: Bool = true, bot: String? = nil) {
        self.id = id; self.name = name; self.face = face; self.connected = connected; self.bot = bot
    }
    public init(_ j: JSON) {
        id = j["id"].string ?? ""; name = j["name"].string ?? ""; face = j["face"].int ?? 0
        connected = j["connected"].bool ?? true
        bot = j["bot"].string ?? (j["bot"].bool == true ? "normal" : nil)
    }
    /// A bot's name without the room's " (bot)" ending (the app shows a BOT badge instead).
    public var displayName: String { Self.stripBot(name) }
    public static func stripBot(_ s: String) -> String { s.hasSuffix(" (bot)") ? String(s.dropLast(6)) : s }
}
