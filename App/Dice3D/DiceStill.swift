import SwiftUI
import T2PCore

/// Still mode for the 3D dice's screenshots (#521): a made-up Hot Dice or Roll Call turn played on a timer through
/// the real game screen, the scene stopped at an exact moment, so a roll mid-tumble, the dice settled, two kept and
/// a Farkle are shot the same way every run. UI tests launch the app with
///   -t2p-dice-still "game=hot moment=tumble"     (game: hot or rollcall; moment: tumble, settled, kept, farkle, over;
///                                                  Roll Call also takes before: the turn before its first roll,
///                                                  and kept4: four held, #724)
/// Roll Call (Yacht Dice) has no arena since Nov 20: its still is the in-place board, a tumble stopped part way
/// (YachtTumble.frozenAt), and "yacht-ready" says when it's there.
/// ("over" is the end of the game: the painted winner screen, with the tip jar's quiet line when there are tips, #598)
/// and optionally after=<seconds> to stop that long after the moment instead (build 45: the camera still eased in
/// three seconds after the dice land).
/// Nothing here talks to a room.
struct DiceStill {
    var game = "hot"
    var moment = "settled"
    /// #523: the view zoomed this much (and turned a little), as a pinch would leave it.
    var zoom: Double?
    /// Seconds after the moment to stop (nil: the moment's own time).
    var after: Double?

    static func fromArgs(_ args: [String] = ProcessInfo.processInfo.arguments) -> DiceStill? {
        guard let i = args.firstIndex(of: "-t2p-dice-still") else { return nil }
        var s = DiceStill()
        for w in (i + 1 < args.count ? args[i + 1].split(separator: " ") : []) {
            let kv = w.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            if kv[0] == "game" { s.game = kv[1] }
            if kv[0] == "moment" { s.moment = kv[1] }
            if kv[0] == "zoom" { s.zoom = Double(kv[1]) }
            if kv[0] == "after" { s.after = Double(kv[1]) }
        }
        return s
    }

    /// When the scene stops: a moment of the arena, and how long after it.
    var freeze: (DiceArenaWorld.Moment, Double) {
        let f = momentFreeze
        return (f.0, after ?? f.1)
    }

    private var momentFreeze: (DiceArenaWorld.Moment, Double) {
        switch moment {
        case "tumble": return (.pour, 0.42)
        case "kept": return (.kept, 0.3)
        case "farkle": return (.landed, 1.1)
        default: return (.landed, 0.55)
        }
    }

    static let players: [[String: Any]] = [
        ["id": "p0", "name": "Sim", "face": 3, "score": 1250, "on": true, "connected": true],
        ["id": "p1", "name": "June (bot)", "face": 12, "bot": "steady", "score": 2400, "on": true, "connected": true],
        ["id": "p2", "name": "Rex (bot)", "face": 21, "bot": "bold", "score": 600, "on": true, "connected": true],
    ]

    static func json(_ o: [String: Any]) -> JSON { JSON.parse((try? JSONSerialization.data(withJSONObject: o)) ?? Data()) ?? .null }

    /// One Hot Dice view of your turn.
    static func hot(state: String, seq: Int, faces: [Int?], sel: [Int] = [], selPts: Int = 0, lost: Int = 0) -> HotDice.View {
        let dice: [[String: Any]] = faces.enumerated().map { i, v in v.map { ["id": i, "v": $0] } ?? ["id": i, "v": NSNull()] }
        let turn: [String: Any] = [
            "id": "p0", "n": 4, "state": state, "seq": seq, "pts": 0, "dice": dice, "kept": [Int](),
            "live": state == "start" ? [Int]() : Array(0..<6), "sel": sel, "selPts": selPts, "selName": "", "note": "",
            "lost": lost, "need": 0, "bot": false,
        ]
        return HotDice.View(json([
            "t": "you", "phase": "playing", "code": "SOLO", "you": ["id": "p0", "name": "Sim", "face": 3], "yourTurn": true,
            "hostless": true, "owner": "p0", "players": players, "turn": turn, "target": 10000, "ones": 1000,
            "rules": ["board": true, "three": true], "farkleSkip": true,
        ]))
    }

    /// The Hot Dice views in order, each with when it arrives (seconds after the screen opens).
    var hotSteps: [(Double, HotDice.View)] {
        if moment == "over" {
            let ps: [[String: Any]] = [
                ["id": "p0", "name": "Sim", "face": 3, "score": 10350, "on": true, "connected": true],
                ["id": "p1", "name": "June (bot)", "face": 12, "bot": "steady", "score": 8900, "on": true, "connected": true],
                ["id": "p2", "name": "Rex (bot)", "face": 21, "bot": "bold", "score": 6150, "on": true, "connected": true],
            ]
            let you: [String: Any] = ["id": "p0", "name": "Sim", "face": 3]
            let v: [String: Any] = ["t": "you", "phase": "done", "code": "SOLO", "you": you, "yourTurn": false, "hostless": true,
                                    "owner": "p0", "players": ps, "winners": ["p0"], "target": 10000, "ones": 1000,
                                    "rules": ["board": true, "three": true]]
            return [(0, HotDice.View(Self.json(v)))]
        }
        let rolled: [Int?] = moment == "farkle" ? [2, 3, 4, 6, 6, 3] : [5, 1, 3, 3, 6, 2]
        var steps: [(Double, HotDice.View)] = [
            (0, Self.hot(state: "start", seq: 0, faces: Array(repeating: 1, count: 6))),
            (0.9, Self.hot(state: "rolling", seq: 1, faces: Array(repeating: nil, count: 6))),
            (2.1, Self.hot(state: moment == "farkle" ? "farkle" : "choose", seq: 1, faces: rolled)),
        ]
        if moment == "kept" { steps.append((5.2, Self.hot(state: "choose", seq: 1, faces: rolled, sel: [0, 1], selPts: 150))) }
        return steps
    }

    static func rollCall(rolls: Int, faces: [Int], held: [Bool]) -> RollCall.View {
        let rcPlayers: [[String: Any]] = [
            ["id": "p0", "name": "Sim", "face": 3, "total": 64, "scores": ["ones": 3, "fives": 15, "chance": 22, "full": 25], "connected": true],
            ["id": "p1", "name": "Rosa (bot)", "face": 9, "bot": "medium", "total": 71, "scores": ["sixes": 24, "three": 22, "chance": 25], "connected": true],
        ]
        let allowed = ["twos", "threes", "fours", "sixes", "three", "four", "small", "large", "five"]
        return RollCall.View(json([
            "t": "you", "phase": "playing", "code": "SOLO", "you": ["id": "p0", "name": "Sim", "face": 3], "yourTurn": true,
            "hostless": true, "owner": "p0", "players": rcPlayers, "quick": false, "rounds": 13,
            "turn": ["id": "p0", "dice": faces, "held": held, "rolls": rolls],
            "options": ["allowed": rolls > 0 ? allowed : [String](), "scores": ["twos": 2, "threes": 6, "fours": 0, "sixes": 6, "three": 0, "four": 0, "small": 0, "large": 0, "five": 0],
                        "instruction": "", "bonus": 0],
            "last": ["n": 7],
        ]))
    }

    var rollCallSteps: [(Double, RollCall.View)] {
        if moment == "over" {
            let ps: [[String: Any]] = [
                ["id": "p0", "name": "Sim", "face": 3, "total": 287, "extra": 100, "scores": ["five": 50, "chance": 24, "sixes": 24, "fives": 20, "fours": 16, "threes": 9, "twos": 6, "ones": 3], "connected": true],
                ["id": "p1", "name": "Rosa (bot)", "face": 9, "bot": "medium", "total": 214, "scores": ["chance": 25, "sixes": 24, "full": 25, "large": 40, "small": 30, "three": 22, "four": 24, "fives": 15, "fours": 9], "connected": true],
            ]
            let you: [String: Any] = ["id": "p0", "name": "Sim", "face": 3]
            let v: [String: Any] = ["t": "you", "phase": "done", "code": "SOLO", "you": you, "yourTurn": false, "hostless": true,
                                    "owner": "p0", "quick": false, "rounds": 13, "players": ps, "winners": ["p0"], "last": ["n": 26]]
            return [(0, RollCall.View(Self.json(v)))]
        }
        let faces = [3, 3, 5, 2, 6]
        var steps: [(Double, RollCall.View)] = [(0, Self.rollCall(rolls: 0, faces: [1, 1, 1, 1, 1], held: Array(repeating: false, count: 5)))]
        if moment == "before" { return steps }
        steps.append((0.9, Self.rollCall(rolls: 1, faces: faces, held: Array(repeating: false, count: 5))))
        if moment == "kept" { steps.append((2.4, Self.rollCall(rolls: 1, faces: faces, held: [true, true, false, false, false]))) }
        // #724: four held, for the gunmetal in the held dice's gold
        if moment == "kept4" { steps.append((2.4, Self.rollCall(rolls: 1, faces: faces, held: [true, true, true, true, false]))) }
        return steps
    }

    /// Roll Call: when its board is ready to shoot (seconds after the screen opens).
    var rollCallReady: Double {
        switch moment {
        case "before", "over": return 0.8
        case "tumble": return 1.4
        case "kept", "kept4": return 3.4
        default: return 2.4
        }
    }
}

/// The real Hot Dice or Roll Call screen with the 3D dice, fed the made-up turn.
struct DiceStillView: View {
    let still: DiceStill
    @StateObject private var app = AppModel()
    @State private var room: RoomModel?
    @State private var hot: HotDice.View?
    @State private var rc: RollCall.View?
    @State private var ready = false

    var body: some View {
        ZStack {
            (still.game == "rollcall" ? Color(hex: 0x0B1121) : T2P.felt).ignoresSafeArea()
            if let room {
                if let hot { HotDiceView(room: room, view: hot, onLeave: {}, arena: true) }
                if let rc { RollCallView(room: room, view: rc, onLeave: {}) }
                if ready { Text("ready").font(.caption2).foregroundStyle(.clear).accessibilityIdentifier("yacht-ready") }
            }
        }
        .environmentObject(app)
        .preferredColorScheme(.dark)
        .onAppear(perform: start)
    }

    private func start() {
        guard room == nil else { return }
        Task { await TipJar.shared.load() }   // #598: the end screen's tip line, when there are tips
        DiceArenaStage.stillFreeze = still.freeze
        DiceArenaStage.stillZoom = still.zoom
        room = RoomModel(game: still.game == "rollcall" ? .rollCall : .hotDice, code: "SOLO", app: app, taken: [], starting: false,
                         offline: app.offlineRules)
        if still.game == "rollcall" {
            if still.moment == "tumble" { YachtTumble.frozenAt = 0.42 }
            for (at, v) in still.rollCallSteps { DispatchQueue.main.asyncAfter(deadline: .now() + at) { rc = v } }
            DispatchQueue.main.asyncAfter(deadline: .now() + still.rollCallReady) { ready = true }
        } else {
            for (at, v) in still.hotSteps { DispatchQueue.main.asyncAfter(deadline: .now() + at) { hot = v } }
        }
    }
}
