import Foundation

/// What a new view means for the game's feel (sounds and haptics): worked out from the view before and the view now,
/// the same for every phone, so the app plays them from one place (App/Feel.swift) instead of each screen.
/// The dice landing and a Farkle wait for the dice on screen, so those stay with the dice screens.
public enum FeelEvent: Equatable, Sendable {
    case yourTurn       // your turn came round
    case cardPlayed     // a card went on the pile (anyone's)
    case drew           // a card came into your hand
    case bolt           // a +2 or +4 aimed at you
    case diceRolled     // someone's dice are in the air
    case won            // the game ended and you won
}

public enum FeelEvents {
    /// The events between two views of one room. No old view (the first one in) gives nothing: opening a room
    /// mid-game isn't your turn "coming round".
    public static func between(_ old: JSON?, _ new: JSON, game: Game) -> [FeelEvent] {
        guard let old else { return [] }
        var out: [FeelEvent] = []
        let playing = (new["phase"].string ?? "lobby") == "playing"
        if playing && new["yourTurn"].bool == true && old["yourTurn"].bool != true { out.append(.yourTurn) }

        switch game {
        case .overdraft:
            let was = Overdraft.View(old), now = Overdraft.View(new)
            // seq counts the plays in a hand (a new hand starts again, and its first card is dealt, not played)
            if let t = now.table, let top = t.top, let before = was.table, t.n == before.n, t.seq > before.seq {
                out.append(.cardPlayed)
                // a +2 or +4 lands on the next player: with stacking a train they face, without it the cards they draw
                if (top.kind == "draw2" || top.kind == "wild4") && now.yourTurn && t.turn == now.me.id
                    && (t.stack > before.stack || now.hand.count >= was.hand.count + 2) {
                    out.append(.bolt)
                }
            }
            if was.table != nil && now.table?.n == was.table?.n && now.hand.count > was.hand.count && !out.contains(.bolt) {
                out.append(.drew)
            }
            if let t = now.table, t.over, !(was.table?.over ?? false), let w = t.winner, w == now.me.id { out.append(.won) }
        case .hotDice:
            let was = HotDice.View(old).turn, now = HotDice.View(new).turn
            if let t = now, t.state == "rolling", t.n != was?.n || t.seq != was?.seq || was?.state != "rolling" {
                out.append(.diceRolled)
            }
        case .rollCall:
            let was = RollCall.View(old).rollKey, now = RollCall.View(new).rollKey
            if let k = now, k != was { out.append(.diceRolled) }
        case .closeEnough:
            break
        }

        if game != .overdraft {
            let me = new["you"]["id"].string ?? ""
            let won = (new["winners"].array.compactMap(\.string)).contains(me)
            let wasWon = (old["winners"].array.compactMap(\.string)).contains(me)
            if !me.isEmpty && won && !wasWon { out.append(.won) }
        }
        return out
    }
}
