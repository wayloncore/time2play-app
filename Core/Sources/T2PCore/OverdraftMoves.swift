import Foundation

/// What happened at an Overdraft table between two of its views (#489): who played what, who drew, a Reverse, a Skip,
/// a jump-in, a train taken. The room only sends the table as it is now; the website's phone page works the moves out
/// the same way (static/live/overdraft.html tableMoves and flowEvents), so every phone tells the same story.
extension Overdraft {
    public enum Move: Equatable, Sendable {
        /// A card played. `jump`: played out of turn (Jump-in).
        case played(by: String, card: Card, jump: Bool)
        /// Cards drawn from the deck (a draw on your turn, or the room drawing for a turn that ran out).
        case drew(who: String, n: Int)
        /// Cards drawn because of somebody's +2 or +4, with no stacking: they still take their turn.
        case hit(who: String, n: Int, by: String, card: Card)
        /// A Reverse turned play around.
        case reversed(by: String)
        /// A Skip (or a Reverse with two at the table) made `who` miss a turn.
        case skipped(who: String, by: String)
        /// A train taken: `who` drew its whole total and lost the turn.
        case tookTrain(who: String, n: Int)

        /// The moments the table shows big, over the piles, for a moment.
        public var isBig: Bool {
            switch self {
            case .reversed, .skipped, .tookTrain: return true
            case let .played(_, _, jump): return jump
            default: return false
            }
        }
    }

    /// The moves between `was` and `now`, oldest first. Empty when it can't tell (a new hand, a hand already over).
    public static func moves(from was: Table?, to now: Table) -> [Move] {
        guard let was, !was.over else { return [] }
        let topWas = was.pile.last?.k ?? -1
        let topNow = now.pile.last?.k ?? -1
        if topNow < topWas { return [] }                     // the pile started again: a new hand
        var before: [String: Int] = [:]
        for s in was.seats { before[s.id] = s.cards }
        let fewer = now.seats.filter { s in before[s.id].map { s.cards < $0 } ?? false }
        let newJump = now.jumpBy != nil && !now.over && (was.jumpBy != now.jumpBy || was.jumpSeq != now.jumpSeq)

        var plays: [(from: String, card: Card)] = []
        for c in now.pile where (c.k ?? -1) > topWas {
            plays.append((fewer.first?.id ?? was.turn ?? "", c))
        }
        var played: [String: Int] = [:]
        for p in plays { played[p.from, default: 0] += 1 }

        var out: [Move] = []
        let turned = was.direction != now.direction
        for p in plays {
            let jump = newJump && p.from == now.jumpBy && p.card == plays.last?.card
            out.append(.played(by: p.from, card: p.card, jump: jump))
            if p.card.kind == "reverse" && turned { out.append(.reversed(by: p.from)) }
            if p.card.kind == "skip" || (p.card.kind == "reverse" && !turned) {
                if let who = seat(after: p.from, in: now) { out.append(.skipped(who: who, by: p.from)) }
            }
        }
        if turned && !plays.contains(where: { $0.card.kind == "reverse" }) { out.append(.reversed(by: was.turn ?? "")) }

        // cards gained: a draw, a +2 or +4 landing (no stacking), or a train taken
        let hitter = plays.last(where: { $0.card.kind == "draw2" || $0.card.kind == "wild4" })
        let trainTaken = was.stack > 0 && now.stack == 0 && !now.over && was.turn != now.turn && plays.isEmpty
        for s in now.seats {
            guard let b = before[s.id] else { continue }
            let got = s.cards - b + (played[s.id] ?? 0)
            guard got > 0 else { continue }
            if trainTaken && s.id == was.turn {
                out.append(.tookTrain(who: s.id, n: got))
            } else if let h = hitter, h.from != s.id, now.stack == 0 {
                out.append(.hit(who: s.id, n: got, by: h.from, card: h.card))
            } else {
                out.append(.drew(who: s.id, n: got))
            }
        }
        return out
    }

    /// The seat play reaches after `id`'s (who a Skip passes over), in the table's direction now.
    static func seat(after id: String, in t: Table) -> String? {
        guard let i = t.seats.firstIndex(where: { $0.id == id }), t.seats.count > 1 else { return nil }
        let n = t.seats.count
        let d = t.direction >= 0 ? 1 : -1
        return t.seats[((i + d) % n + n) % n].id
    }
}
