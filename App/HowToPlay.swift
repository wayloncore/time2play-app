import SwiftUI
import T2PCore

/// How to play (#489): one tap from the table or the lobby, short and plain, and saying which house rules this room
/// has on. The words follow the website's own rules for each game. A game with no text here shows no button yet.
struct HowTo {
    struct Part: Identifiable { let title: String; let body: String; var id: String { title } }
    let lede: String
    let parts: [Part]
}

extension Game {
    /// This game's rules, for the room as it's set up (`view`, the room's latest view).
    func howTo(_ view: JSON?) -> HowTo? {
        switch self {
        case .overdraft:
            // the lobby's view says both house rules; a table's says Jump-in, and a train on the table means Stacking is on
            let stacking: Bool? = view?["stacking"].bool ?? ((view?["table"]["stack"].int ?? 0) > 0 ? true : nil)
            let jumpIn: Bool? = view?["jumpIn"].bool ?? view?["table"]["jumpIn"].bool
            let said = { (on: Bool?) -> String in on.map { $0 ? " · on in this room" : " · off in this room" } ?? "" }
            var parts: [HowTo.Part] = [
                .init(title: "Your turn", body: "Play a card that matches the suit or the number on the pile. An action card also goes on the same action. The cards that can go are lifted and lit."),
                .init(title: "Nothing to play?", body: "Tap the deck to draw one. If it goes, you can play it, or keep it and end your turn."),
                .init(title: "Action cards", body: "Skip: the next player misses a turn. Reverse: play turns around. +2 and +4: the next player draws two or four, then still takes their turn. Change Suit and +4: you pick the suit."),
                .init(title: "The clock", body: "Each turn has 45 seconds. If it runs out, the room draws a card for you and play moves on."),
            ]
            parts.append(.init(title: "Stacking" + said(stacking),
                               body: "A house rule the room’s owner sets in the lobby. When it’s on, you can pass a +2 or +4 along with one of your own, and the total grows. Whoever can’t add to it takes the whole total and loses their turn."))
            parts.append(.init(title: "Jump-in" + said(jumpIn),
                               body: "A house rule too. When it’s on and you hold the exact card just played, play it at once, even when it isn’t your turn. Your phone marks it. Play goes on from you."))
            return HowTo(lede: "First to empty their hand wins. One hand, no points.", parts: parts)
        case .closeEnough:
            let count = view?["opts"]["count"].int ?? 10
            let timer = view?["opts"]["timer"].int ?? 60
            return HowTo(lede: "Every answer is a number. Give a range, not a guess: narrow and right scores most.", parts: [
                .init(title: "Each question", body: "Move Low and High to set your range, then lock it in. Everyone answers at the same time, on their own phone."),
                .init(title: "Scoring", body: "If the answer is inside your range, you score up to 20 points: the narrower the range, the more it’s worth. A range that misses scores 0, however narrow."),
                .init(title: "The answer", body: "It shows once everyone has locked in, or when the clock runs out. Then you see everyone’s range and points."),
                .init(title: "This game", body: "\(count) questions, \(timer < 60 || timer == 90 ? "\(timer) seconds" : timer == 60 ? "1 minute" : "\(timer / 60) minutes") each. Highest total wins; a tie shares it."),
            ])
        case .hotDice:
            // the lobby's and the table's views both say the room's set-up: what three 1s score, the target, the house rules
            let ones = view?["ones"].int ?? 1000
            let target = view?["target"].int ?? 10000
            let said = { (on: Bool?) -> String in on.map { $0 ? " · on in this room" : " · off in this room" } ?? "" }
            return HowTo(lede: "Roll six dice, keep what scores, and bank before you Farkle. First to \(target.formatted()) wins.", parts: [
                .init(title: "Your turn", body: "Roll all six. Tap the dice you want to keep: they have to score. Then roll the rest to add more, or bank this turn’s points."),
                .init(title: "Farkle", body: "A roll with nothing that scores is a Farkle: you lose this turn’s points and the turn passes. Tap the Farkle to go on at once."),
                .init(title: "Hot dice", body: "When all six dice have scored, roll all six again and keep building the same turn."),
                .init(title: "What scores", body: "Each 1: 100. Each 5: 50. Three 1s: \(ones.formatted()). Three 2s to three 6s: 200 to 600. Four of a kind: 1,000. Five: 2,000. Six: 3,000. 1 through 6, three pairs, or four of a kind and a pair: 1,500. Two triplets: 2,500."),
                .init(title: "The last round", body: "Once someone banks to \(target.formatted()), everyone else gets one last turn. The highest score wins; a tie shares it."),
                .init(title: "500 to get on the board" + said(view?["rules"]["board"].bool), body: "A house rule the room’s owner sets in the lobby. Your first bank has to be at least 500 in one turn."),
                .init(title: "Three Farkles lose 1,000" + said(view?["rules"]["three"].bool), body: "A house rule too. A third Farkle in a row costs 1,000 (a score never goes below 0). A bank starts the count over."),
                .init(title: "The clock", body: "Each turn has a minute. If it runs out, the room finishes the turn for you."),
            ])
        case .rollCall:
            let quick = view?["quick"].bool ?? false
            let rounds = view?["rounds"].int ?? (quick ? 6 : 13)
            return HowTo(lede: "Five dice, three rolls, \(quick ? "six" : "thirteen") boxes to fill. Highest total wins.", parts: [
                .init(title: "Your turn", body: "Roll up to three times. Between rolls, tap dice to hold them, then roll the rest. Then put the roll in one open box. A box can take 0."),
                .init(title: "The upper boxes", body: "Ones to Sixes: add up the dice showing that number. 63 or more across all six earns a 35 bonus\(quick ? " in a full game (the quick game has none)" : "")."),
                .init(title: "The lower boxes", body: "3 of a Kind and 4 of a Kind: all five dice added. Full House: 25. Sm. Straight (four in a row): 30. Lg. Straight (five in a row): 40. Roll Call (five of a kind): 50. Chance: all five added."),
                .init(title: "Another Roll Call", body: "Once Roll Call has its 50, each five of a kind after it earns 100 more. It goes in its matching upper box if that’s open; if not, any open lower box at full value."),
                .init(title: "This game", body: quick ? "Quick game: \(rounds) rounds. The highest total wins; a tie shares it." : "\(rounds) rounds, one box each. The highest total wins; a tie shares it."),
            ])
        default:
            return nil
        }
    }
}

/// The How to play sheet.
struct HowToSheet: View {
    let game: Game
    let howTo: HowTo
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(howTo.lede).font(.title3.weight(.semibold)).foregroundStyle(T2P.text)
                        .accessibilityIdentifier("how-to-lede")
                    ForEach(howTo.parts) { p in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(p.title).font(.headline).foregroundStyle(T2P.goldText).accessibilityAddTraits(.isHeader)
                            Text(p.body).foregroundStyle(T2P.text).fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(24)
                .frame(maxWidth: 640, alignment: .leading).frame(maxWidth: .infinity)
            }
            .background(T2P.navy.ignoresSafeArea())
            .navigationTitle("How to play \(game.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("how-to-done") } }
        }
        .presentationDetents([.medium, .large])
    }
}

/// The round "?" button that opens How to play.
struct HowToButton: View {
    let game: Game
    let view: JSON?
    @State private var open = false
    var body: some View {
        if let h = game.howTo(view) {
            Button { open = true } label: {
                Image(systemName: "questionmark").font(.headline).foregroundStyle(T2P.text)
                    .frame(width: 44, height: 44).background(Color.primary.opacity(0.08), in: Circle())
            }
            .accessibilityLabel("How to play").accessibilityIdentifier("how-to-play")
            .sheet(isPresented: $open) { HowToSheet(game: game, howTo: h) }
        }
    }
}
