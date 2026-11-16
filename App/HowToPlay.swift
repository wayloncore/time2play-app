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
