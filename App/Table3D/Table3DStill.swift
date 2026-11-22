import Foundation
import SwiftUI
import T2PCore

/// Still mode for the 3D table's screenshots (#496): a made-up table, stopped at an exact moment, so each suit, your
/// turn, a card mid-throw and a scene mid-change can be shot the same way every run. UI tests launch the app with
///   -t2p-3d-still "suit=bolt n=5 mine=1 hand=9 throw=0.3 change=ember mix=0.5 strike=0.15 reverse=1.3"
/// (every key optional). Build 45: play=<seconds> stops your first card that long into its throw from your hand to
/// the pile, and draw=<seconds> a card drawn from the deck that long into its flight to your hand. Nothing here talks
/// to a room.
struct Table3DStill {
    var suit = "wave"
    var players = 5
    var mine = false
    var hand = 6
    var throwAt: Double?
    var change: String?
    var mix = 0.5
    var strikeAt: Double?
    /// Seconds into a Reverse of the turn flow (play turns from forward to backward).
    var reverseAt: Double?
    /// Seconds into your card's throw from your hand (Table3DView starts it once the hand is laid out).
    var playAt: Double?
    /// Seconds into a drawn card's flight to your hand.
    var drawAt: Double?
    /// #609: your hand holds every action card (+2, +4, Skip, Reverse, Change Suit) between number cards.
    var actions = false
    /// #609: the classic (flat) hand instead of the 3D table, with the same made-up hand.
    var classic = false
    /// #716: the table keeps playing (no freeze), with a Bolt aimed at you every few seconds, for a recording.
    var live = false

    static func fromArgs(_ args: [String] = ProcessInfo.processInfo.arguments) -> Table3DStill? {
        guard let i = args.firstIndex(of: "-t2p-3d-still") else { return nil }
        var s = Table3DStill()
        let words = i + 1 < args.count ? args[i + 1].split(separator: " ") : []
        for w in words {
            let kv = w.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            switch kv[0] {
            case "suit": s.suit = kv[1]
            case "n": s.players = min(10, max(2, Int(kv[1]) ?? 5))
            case "mine": s.mine = kv[1] == "1"
            case "hand": s.hand = min(14, max(1, Int(kv[1]) ?? 6))
            case "throw": s.throwAt = Double(kv[1])
            case "change": s.change = kv[1]
            case "mix": s.mix = Double(kv[1]) ?? 0.5
            case "strike": s.strikeAt = Double(kv[1])
            case "reverse": s.reverseAt = Double(kv[1])
            case "play": s.playAt = Double(kv[1])
            case "draw": s.drawAt = Double(kv[1])
            case "actions": s.actions = kv[1] == "1"
            case "classic": s.classic = kv[1] == "1"
            case "live": s.live = kv[1] == "1"
            default: break
            }
        }
        return s
    }

    /// Sets the scene going and stops it at the moment asked for.
    func run(_ w: Table3DWorld) {
        let st = self
        if playAt != nil || drawAt != nil { return }   // Table3DView starts these: they need the hand's place on screen
        w.post {
            let c0 = w.clock, start = 1.0
            if st.live {
                // #716's recordings: the storm runs as in a game, and a Bolt is aimed at you every 5 seconds (the
                // director's big moment; nothing extra without -t2p-cinema director)
                for k in 0..<8 { w.addTimer(c0 + 2.5 + 5 * Double(k)) { w.boltHit(mine: true) } }
                return
            }
            if let t = st.throwAt {
                let seat = max(0, min(1, st.players - 2)), art = Self.byNumber(st.suit, 6)
                w.addTimer(c0 + start) { w.throwFromSeat(seat, art: art, k: 9) }
                w.freezeAt = c0 + start + t
            } else if let to = st.change {
                // the table already shows the card that changed the suit; the scene starts on the old suit and turns
                w.addTimer(c0 + start) { w.setSuit(st.suit, instant: true); w.setSuit(to) }
                w.freezeAt = c0 + start + 2.1 * st.mix
            } else if let t = st.strikeAt {
                if w.cinema == .storm {
                    // #717: a staged strike; t is after its return stroke
                    w.addTimer(c0 + start) { w.strike(at: 0.3) }
                    w.freezeAt = c0 + start + StormStrike.strokeAt + t
                } else if w.cinema == .director || w.cinema == .moments {
                    // #716: the director's strike is a Bolt aimed at you: its held beat, then the strike; t is after the strike
                    w.addTimer(c0 + start) { w.boltHit(mine: true, at: 0.3) }
                    w.freezeAt = c0 + start + w.strikeLead + t
                } else {
                    w.addTimer(c0 + start) { w.strike(at: 0.3) }
                    w.freezeAt = c0 + start + t
                }
            } else if let t = st.reverseAt {
                // play was going forward from the seat that's on; a Reverse sends it back to the seat before
                // (you are -1, the others 0 up in turn order; the still's turn is yours or the second other seat's)
                let on = st.mine ? -1 : min(1, st.players - 2)
                w.addTimer(c0 + start) {
                    guard let l = w.layout, !l.seats.isEmpty else { return }
                    func rim(_ i: Int) -> Double { i < 0 ? 0 : l.seats[min(i, l.seats.count - 1)].s }
                    let back = on < 0 ? l.seats.count - 1 : on - 1
                    w.setFlow(from: rim(on), to: rim(back), dir: -1, pin: true)
                }
                w.freezeAt = c0 + start + t
            } else {
                w.freezeAt = c0 + 1.8
            }
        }
    }

    static func byNumber(_ suit: String, _ n: Int) -> String { "\(suit)_\(n)" }

    /// The made-up table, as a room would send it.
    var view: Overdraft.View {
        let names = ["Sim", "Maya", "Dev", "Ada (bot)", "Jordan", "Sam", "Priya", "Leo", "Bea (bot)", "Marcus"]
        let faces = [3, 9, 12, 21, 31, 0, 1, 2, 4, 5]
        let counts = [actions ? 9 : hand, 3, 5, 4, 2, 5, 7, 3, 6, 4]
        let seats: [[String: Any]] = (0..<players).map { i in
            ["id": "p\(i)", "seat": i, "name": names[i], "face": faces[i], "cards": counts[i], "connected": true, "held": false]
        }
        // mid-change, the card that changed the suit is already on top (as in a game): the chip and header show it
        let shown = change ?? suit
        let under: [(String, Int)] = change == nil ? [("leaf", 6), ("ember", 6), ("ember", 2), (suit, 2), (suit, 7)]
            : [("leaf", 6), ("ember", 6), (suit, 2), (suit, 7), (shown, 7)]
        let pileCards: [[String: Any]] = under.enumerated().map { k, c in
            ["kind": "number", "suit": c.0, "n": c.1, "k": k + 4]
        }
        var handCards: [[String: Any]] = [
            ["id": "h0", "kind": "number", "suit": "wave", "n": 4], ["id": "h1", "kind": "reverse", "suit": "wave"],
            ["id": "h2", "kind": "number", "suit": "leaf", "n": 2], ["id": "h3", "kind": "number", "suit": "bolt", "n": 7],
            ["id": "h4", "kind": "number", "suit": "ember", "n": 9], ["id": "h5", "kind": "wild"],
        ]
        let extra: [(String, Int)] = [("ember", 3), ("leaf", 8), ("bolt", 1), ("wave", 5), ("leaf", 0), ("ember", 7), ("bolt", 4), ("wave", 2)]
        for (j, e) in extra.enumerated() where handCards.count < hand { handCards.append(["id": "x\(j)", "kind": "number", "suit": e.0, "n": e.1]) }
        handCards = Array(handCards.prefix(hand))
        if actions {
            handCards = [
                ["id": "a0", "kind": "number", "suit": "bolt", "n": 5], ["id": "a1", "kind": "draw2", "suit": "bolt"],
                ["id": "a2", "kind": "skip", "suit": "ember"], ["id": "a3", "kind": "reverse", "suit": "wave"],
                ["id": "a4", "kind": "wild4"], ["id": "a5", "kind": "wild"], ["id": "a6", "kind": "draw2", "suit": "leaf"],
                ["id": "a7", "kind": "skip", "suit": "bolt"], ["id": "a8", "kind": "number", "suit": "wave", "n": 3],
            ]
        }
        let legal: [String] = mine ? handCards.compactMap { c in
            let id = c["id"] as? String ?? ""
            if c["kind"] as? String == "wild" { return id }
            return (c["suit"] as? String == shown || c["n"] as? Int == 7) ? id : nil
        } : []
        let table: [String: Any] = [
            "n": 1, "turnEndsAt": (Date().timeIntervalSince1970 + 29) * 1000, "suit": shown,
            "top": ["kind": "number", "suit": shown, "n": 7], "pile": pileCards, "stack": 0, "jumpIn": false, "seq": 8,
            "taking": false, "direction": 1, "drawLeft": 60, "turn": mine ? "p0" : "p\(min(2, players - 1))",
            "over": false, "seats": seats,
        ]
        let root: [String: Any] = [
            "t": "you", "ok": true, "phase": "playing", "code": "SOLO", "you": ["id": "p0", "name": "Sim", "face": 3],
            "table": table, "yourTurn": mine, "hand": handCards, "legal": legal, "jump": [String](), "held": false,
            "hostless": true, "owner": "p0",
        ]
        let data = (try? JSONSerialization.data(withJSONObject: root)) ?? Data()
        return Overdraft.View(JSON.parse(data) ?? .null)
    }
}

/// #609's classic hand: the flat table's own hand (HandView) holding the still's made-up cards, on the table's color,
/// so each card's size can be checked beside its neighbors. Launched with -t2p-3d-still "classic=1 actions=1 mine=1".
struct ClassicHandStill: View {
    let still: Table3DStill
    var body: some View {
        ZStack(alignment: .bottom) {
            T2P.table.ignoresSafeArea()
            VStack(spacing: 12) {
                Spacer()
                Text("Your hand").font(.headline).foregroundStyle(T2P.text)
                HandView(view: still.view, onTap: { _ in }).frame(height: 230)
                Text("ready").font(.caption2).foregroundStyle(.clear).accessibilityIdentifier("od3d-ready")
            }
            .padding(.bottom, 24)
        }
        .preferredColorScheme(.dark)
    }
}
