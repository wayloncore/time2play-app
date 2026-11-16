import Foundation

/// A player as the dice and number games list them (Farkle Live, Roll Call, Close Enough cores in the website repo).
public struct ScorePlayer: Equatable, Sendable, Identifiable {
    public var id: String; public var name: String; public var face: Int
    public var bot: String?; public var held: Bool; public var connected: Bool; public var left: Bool
    public var seated: Bool
    public var score: Int          // Hot Dice score, Roll Call total, Close Enough points
    public var on: Bool            // Hot Dice: on the board
    public var strikes: Int        // Hot Dice: Farkles in a row
    public var scores: [String: Int]   // Roll Call: filled boxes
    public var extra: Int          // Roll Call bonuses
    public var hits: Int; public var misses: Int; public var lockedIn: Bool  // Close Enough
    init(_ j: JSON) {
        id = j["id"].string ?? ""; name = j["name"].string ?? ""; face = j["face"].int ?? 0
        bot = j["bot"].string; held = j["held"].bool ?? false; connected = j["connected"].bool ?? true
        left = j["left"].bool ?? false; seated = j["seated"].bool ?? true
        score = j["score"].int ?? j["total"].int ?? 0
        on = j["on"].bool ?? false; strikes = j["strikes"].int ?? 0
        scores = (j["scores"].object ?? [:]).compactMapValues(\.int); extra = j["extra"].int ?? 0
        hits = j["hits"].int ?? 0; misses = j["misses"].int ?? 0; lockedIn = j["in"].bool ?? false
    }
    public var asRoomPlayer: RoomPlayer { RoomPlayer(id: id, name: name, face: face, connected: connected, bot: bot) }
}

/// What every game's view shares: the phase, who you are, who owns the room.
public struct CommonView: Equatable, Sendable {
    public var phase: String
    public var code: String
    public var meId: String
    public var meName: String
    public var meFace: Int
    public var seated: Bool
    public var hostless: Bool
    public var owner: String?
    public var yourTurn: Bool
    public var held: Bool
    public var winners: [String]?
    init(_ j: JSON) {
        phase = j["phase"].string ?? "lobby"; code = j["code"].string ?? ""
        meId = j["you"]["id"].string ?? ""; meName = j["you"]["name"].string ?? ""; meFace = j["you"]["face"].int ?? 0
        seated = j["you"]["seated"].bool ?? true
        hostless = j["hostless"].bool ?? false; owner = j["owner"].string
        yourTurn = j["yourTurn"].bool ?? false; held = j["held"].bool ?? false
        winners = j["winners"].isNull ? nil : j["winners"].array.compactMap(\.string)
    }
    public var isOwner: Bool { hostless && owner != nil && owner == meId }
}

/// Hot Dice (the website's Farkle Live). Bots: Penny (cautious), June (steady), Rex (bold).
public enum HotDice {
    public static let bots: [(level: String, name: String)] = [("cautious", "Penny"), ("steady", "June"), ("bold", "Rex")]
    public static let tableMin = 2

    public struct Die: Equatable, Sendable, Identifiable { public var id: Int; public var v: Int? }
    public struct Highlight: Equatable, Sendable { public var tier: Int; public var name: String; public var points: Int; public var seq: Int }
    public struct Turn: Equatable, Sendable {
        public var id: String; public var n: Int; public var state: String; public var seq: Int; public var pts: Int
        public var dice: [Die]; public var kept: [Int]; public var live: [Int]; public var sel: [Int]
        public var selPts: Int; public var selName: String; public var note: String
        public var hl: Highlight?; public var lost: Int; public var auto: Bool; public var three: Bool
        public var penalty: Int; public var need: Int; public var endsAt: Double?; public var bot: Bool
        init(_ j: JSON) {
            id = j["id"].string ?? ""; n = j["n"].int ?? 0; state = j["state"].string ?? "start"
            seq = j["seq"].int ?? 0; pts = j["pts"].int ?? 0
            dice = j["dice"].array.map { Die(id: $0["id"].int ?? 0, v: $0["v"].int) }
            kept = j["kept"].array.compactMap(\.int); live = j["live"].array.compactMap(\.int)
            sel = j["sel"].array.compactMap(\.int); selPts = j["selPts"].int ?? 0
            selName = j["selName"].string ?? ""; note = j["note"].string ?? ""
            hl = j["hl"].object == nil ? nil : Highlight(tier: j["hl"]["tier"].int ?? 1, name: j["hl"]["name"].string ?? "",
                                                          points: j["hl"]["points"].int ?? 0, seq: j["hl"]["seq"].int ?? 0)
            lost = j["lost"].int ?? 0; auto = j["auto"].bool ?? false; three = j["three"].bool ?? false
            penalty = j["penalty"].int ?? 0; need = j["need"].int ?? 0; endsAt = j["endsAt"].double; bot = j["bot"].bool ?? false
        }
        public func value(_ die: Int) -> Int? { dice.first { $0.id == die }?.v }
    }
    public struct View: Equatable, Sendable {
        public var common: CommonView
        public var ones: Int; public var target: Int; public var board: Bool; public var three: Bool
        public var players: [ScorePlayer]
        public var turn: Turn?
        public var finalBy: String?
        public var lastLine: String?
        public init(_ j: JSON) {
            common = CommonView(j); ones = j["ones"].int ?? 1000; target = j["target"].int ?? 10000
            board = j["rules"]["board"].bool ?? true; three = j["rules"]["three"].bool ?? true
            players = j["players"].array.map(ScorePlayer.init)
            turn = j["turn"].object == nil ? nil : Turn(j["turn"])
            finalBy = j["final"]["by"].string
            let l = j["last"]
            if let kind = l["kind"].string, let who = l["id"].string {
                let name = j["players"].array.first { $0["id"].string == who }?["name"].string ?? "Someone"
                switch kind {
                case "bank": lastLine = "\(name) banked \(l["pts"].int ?? 0)"
                case "farkle": lastLine = l["three"].bool == true ? "\(name): three Farkles, −\(l["penalty"].int ?? 1000)" : "\(name) Farkled"
                default: lastLine = nil
                }
            }
        }
        public func player(_ id: String?) -> ScorePlayer? { players.first { $0.id == id } }
        public var me: ScorePlayer? { player(common.meId) }
    }
}

/// Roll Call (five dice, thirteen boxes). Bots: Pip (easy), Rosa (medium), Viktor (hard).
public enum RollCall {
    public static let bots: [(level: String, name: String)] = [("easy", "Pip"), ("medium", "Rosa"), ("hard", "Viktor")]
    public static let boxes: [(key: String, name: String)] = [
        ("ones", "Ones"), ("twos", "Twos"), ("threes", "Threes"), ("fours", "Fours"), ("fives", "Fives"), ("sixes", "Sixes"),
        ("three", "3 of a Kind"), ("four", "4 of a Kind"), ("full", "Full House"), ("small", "Sm. Straight"),
        ("large", "Lg. Straight"), ("five", "Roll Call"), ("chance", "Chance"),
    ]
    public static let maxRolls = 3

    public struct Turn: Equatable, Sendable {
        public var id: String; public var dice: [Int]; public var held: [Bool]; public var rolls: Int; public var endsAt: Double?
    }
    public struct Options: Equatable, Sendable {
        public var allowed: [String]; public var scores: [String: Int]; public var instruction: String; public var bonus: Int
    }
    public struct View: Equatable, Sendable {
        public var common: CommonView
        public var quick: Bool; public var rounds: Int
        public var players: [ScorePlayer]
        public var turn: Turn?
        public var options: Options?
        public var lastLine: String?
        public init(_ j: JSON) {
            common = CommonView(j); quick = j["quick"].bool ?? false; rounds = j["rounds"].int ?? 13
            players = j["players"].array.map(ScorePlayer.init)
            let t = j["turn"]
            turn = t.object == nil ? nil : Turn(id: t["id"].string ?? "", dice: t["dice"].array.compactMap(\.int),
                                               held: t["held"].array.map { $0.bool ?? false }, rolls: t["rolls"].int ?? 0,
                                               endsAt: t["endsAt"].double)
            let o = j["options"]
            options = o.object == nil ? nil : Options(allowed: o["allowed"].array.compactMap(\.string),
                                                     scores: (o["scores"].object ?? [:]).compactMapValues(\.int),
                                                     instruction: o["instruction"].string ?? "", bonus: o["bonus"].int ?? 0)
            let l = j["last"]
            if let who = l["id"].string, let key = l["key"].string {
                let name = j["players"].array.first { $0["id"].string == who }?["name"].string ?? "Someone"
                let box = RollCall.boxes.first { $0.key == key }?.name ?? key
                lastLine = "\(name) scored \(l["points"].int ?? 0) in \(box)"
            }
        }
        public var me: ScorePlayer? { players.first { $0.id == common.meId } }
        /// The dice are stale until the turn's first roll (they're the last turn's), so the app hides them.
        public var diceShown: Bool { (turn?.rolls ?? 0) > 0 }
        public var round: Int {
            guard let t = turn, let p = players.first(where: { $0.id == t.id }) else { return 1 }
            return min(rounds, p.scores.count + 1)
        }
    }
}

/// Close Enough (guess a range that holds the answer). Bots: Pip, Rosa, Viktor.
public enum CloseEnough {
    public static let bots = RollCall.bots
    public static let counts = [6, 10, 16]
    public static let timers = [30, 45, 60, 90, 120]

    public struct Result: Equatable, Sendable { public var lo: Double?; public var hi: Double?; public var points: Int; public var verdict: String }
    public struct Question: Equatable, Sendable {
        public var n: Int; public var of: Int; public var q: String; public var note: String; public var unit: String
        public var floor: Double; public var ceiling: Double; public var step: Double; public var stage: String
        public var endsAt: Double?; public var answer: Double?; public var why: String?
        public var results: [String: Result]
        init(_ j: JSON) {
            n = j["n"].int ?? 1; of = j["of"].int ?? 1; q = j["q"].string ?? ""; note = j["note"].string ?? ""
            unit = j["unit"].string ?? ""; floor = j["floor"].double ?? 0; ceiling = j["ceiling"].double ?? 100
            step = j["step"].double ?? 1; stage = j["stage"].string ?? "ask"; endsAt = j["endsAt"].double
            answer = j["answer"].double; why = j["why"].string
            results = (j["results"].object ?? [:]).mapValues {
                Result(lo: $0["lo"].double, hi: $0["hi"].double, points: $0["points"].int ?? 0, verdict: $0["verdict"].string ?? "none")
            }
        }
        /// "1,200 m", "45%", "1969": no space before % or °.
        public func format(_ v: Double) -> String {
            let fmt = NumberFormatter(); fmt.numberStyle = .decimal
            fmt.maximumFractionDigits = step < 1 ? max(1, Int((-log10(step)).rounded(.up))) : 0
            fmt.usesGroupingSeparator = !(unit.isEmpty && v >= 1000 && v <= 2100 && v.rounded() == v)
            let s = fmt.string(from: NSNumber(value: v)) ?? "\(v)"
            if unit.isEmpty { return s }
            return unit.hasPrefix("%") || unit.hasPrefix("°") ? s + unit : s + " " + unit
        }
        public func snap(_ v: Double) -> Double {
            let s = step > 0 ? step : 1
            return min(ceiling, max(floor, (( v - floor) / s).rounded() * s + floor))
        }
        /// What a range is worth if it holds the answer: round(20 × (1 − width/span)²).
        public func worth(lo: Double, hi: Double, maxPoints: Int = 20) -> Int {
            let span = max(1, ceiling - floor)
            let r = 1 - (hi - lo) / span
            return Int((Double(maxPoints) * r * r).rounded())
        }
    }
    public struct View: Equatable, Sendable {
        public var common: CommonView
        public var set: String; public var count: Int; public var timer: Int
        public var sets: [(key: String, name: String, size: Int)]
        public var players: [ScorePlayer]
        public var question: Question?
        public var answerLo: Double?; public var answerHi: Double?
        public var maxPoints: Int
        public init(_ j: JSON) {
            common = CommonView(j); set = j["opts"]["set"].string ?? "general"; count = j["opts"]["count"].int ?? 10
            timer = j["opts"]["timer"].int ?? 60
            sets = j["sets"].array.map { ($0["key"].string ?? "", $0["name"].string ?? "", $0["size"].int ?? 0) }
            players = j["players"].array.map(ScorePlayer.init)
            question = j["question"].object == nil ? nil : Question(j["question"])
            answerLo = j["answer"]["lo"].double; answerHi = j["answer"]["hi"].double
            maxPoints = j["maxPoints"].int ?? 20
        }
        public static func == (a: View, b: View) -> Bool {
            a.common == b.common && a.set == b.set && a.count == b.count && a.timer == b.timer && a.players == b.players
                && a.question == b.question && a.answerLo == b.answerLo && a.answerHi == b.answerHi
        }
        public var me: ScorePlayer? { players.first { $0.id == common.meId } }
        public var lockedIn: Bool { answerLo != nil }
    }
}
