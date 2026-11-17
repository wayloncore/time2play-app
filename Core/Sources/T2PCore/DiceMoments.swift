import Foundation

/// What just happened at a Hot Dice table between two of its views (#489): dice set aside, hot dice, a bank, a
/// Farkle, a turn the room finished, the last round. The room sends the table as it is now; this works out the moves,
/// the way Overdraft.moves does for cards, so a bot's turn (or a friend's) never just vanishes.
extension HotDice {
    public enum Moment: Equatable, Sendable {
        /// Dice set aside to roll again: "Three 4s" (or "" for 1s and 5s) for `points`.
        case kept(who: String, name: String, points: Int)
        /// All six dice scored: they roll all six again.
        case hot(who: String)
        /// A turn banked: `points` this turn, `total` after it.
        case banked(who: String, points: Int, total: Int)
        /// A Farkle: this turn's points lost.
        case farkled(who: String, lost: Int)
        /// The third Farkle in a row (the house rule on): `penalty` off their score.
        case threeFarkles(who: String, penalty: Int)
        /// Their turn's clock ran out: the room finishes the turn for them.
        case timedOut(who: String)
        /// A game over days: their turn ran out and passed.
        case missed(who: String)
        /// They left in their turn.
        case left(who: String)
        /// `by` reached the target: everyone else gets one last turn.
        case lastRound(by: String)

        /// The moments shown big for a moment, not only in the list.
        public var isBig: Bool {
            switch self {
            case .banked, .hot, .lastRound, .threeFarkles: return true
            default: return false
            }
        }
    }

    /// The moments between `was` and `now`, oldest first. Empty for a game just dealt or one not being played.
    public static func moments(from was: View?, to now: View) -> [Moment] {
        guard let was, was.common.phase == "playing", now.common.phase != "lobby" else { return [] }
        var out: [Moment] = []
        if let wt = was.turn, let nt = now.turn, wt.n == nt.n {
            if let s = nt.lastSet, s != wt.lastSet { out.append(.kept(who: nt.id, name: s.name, points: s.pts)) }
            if nt.hot > wt.hot { out.append(.hot(who: nt.id)) }
            if nt.auto && !wt.auto { out.append(.timedOut(who: nt.id)) }
        }
        if let l = now.last, l.n != (was.last?.n ?? 0) {
            switch l.kind {
            case "bank": out.append(.banked(who: l.id, points: l.pts, total: l.score))
            case "farkle": out.append(l.three ? .threeFarkles(who: l.id, penalty: l.penalty) : .farkled(who: l.id, lost: l.pts))
            case "missed": out.append(.missed(who: l.id))
            case "gone": out.append(.left(who: l.id))
            default: break
            }
        }
        if let by = now.finalBy, was.finalBy == nil { out.append(.lastRound(by: by)) }
        return out
    }
}

/// What just happened at a Roll Call table between two views (#489): a box scored (with the dice it was scored
/// with), an upper bonus earned, a new round.
extension RollCall {
    public enum Moment: Equatable, Sendable {
        /// `who` put `points` in `box`; `extra` is the 100 for another Roll Call.
        case scored(who: String, box: String, points: Int, extra: Int, dice: [Int])
        /// `who`'s upper boxes reached 63: +35.
        case upperBonus(who: String, points: Int)
        /// A new round has started.
        case round(Int)
    }

    public static func moments(from was: View?, to now: View) -> [Moment] {
        guard let was, was.common.phase == "playing", now.common.phase != "lobby" else { return [] }
        var out: [Moment] = []
        if let l = now.last, l.n != (was.last?.n ?? 0) {
            out.append(.scored(who: l.id, box: l.key, points: l.points, extra: l.extra, dice: l.dice))
        }
        for p in now.players {
            guard let before = was.players.first(where: { $0.id == p.id }) else { continue }
            let b = now.bonus(p)
            if b > 0 && was.bonus(before) == 0 { out.append(.upperBonus(who: p.id, points: b)) }
        }
        if now.common.phase == "playing", now.turn != nil, was.turn != nil, now.round > was.round { out.append(.round(now.round)) }
        return out
    }
}
