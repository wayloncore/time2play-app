import SwiftUI
import T2PCore

/// What the home screen widget shows: the game of the day (a Library card, a new one each day) and, in the medium
/// size, one-tap rejoin of your last room. Compiled into the widget and the app (the app draws it for screenshots).
struct WidgetContent: Equatable {
    var day: Date
    var title: String
    var line: String?
    var players: String?
    var key: String
    var game: Game?
    var last: RecentRoom?
}

enum WidgetColors {
    static let navy = Color(red: 11 / 255, green: 17 / 255, blue: 33 / 255)
    static let panel = Color(red: 24 / 255, green: 34 / 255, blue: 58 / 255)
    static let gold = Color(red: 233 / 255, green: 180 / 255, blue: 90 / 255)
    static let ink = Color(red: 42 / 255, green: 26 / 255, blue: 5 / 255)
    static let text = Color(red: 238 / 255, green: 241 / 255, blue: 247 / 255)
    static let muted = Color(red: 184 / 255, green: 193 / 255, blue: 211 / 255)
    static func tint(_ g: Game?) -> Color {
        switch g {
        case .overdraft: return Color(red: 42 / 255, green: 26 / 255, blue: 46 / 255)
        case .hotDice: return Color(red: 31 / 255, green: 74 / 255, blue: 58 / 255)
        case .rollCall: return Color(red: 59 / 255, green: 43 / 255, blue: 31 / 255)
        case .closeEnough: return Color(red: 23 / 255, green: 40 / 255, blue: 58 / 255)
        case nil: return panel
        }
    }
    static func symbol(_ g: Game?) -> String {
        switch g {
        case .overdraft: return "rectangle.stack.fill"
        case .hotDice: return "dice.fill"
        case .rollCall: return "die.face.5.fill"
        case .closeEnough: return "arrow.left.and.right.circle.fill"
        case nil: return "sparkles"
        }
    }
}

/// The game of the day, as a block (the whole small widget, the left of the medium one).
struct GameOfTheDayView: View {
    let c: WidgetContent
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: WidgetColors.symbol(c.game)).font(.system(size: 13, weight: .bold))
                Text("GAME OF THE DAY").font(.system(size: 11, weight: .heavy)).tracking(0.6)
            }
            .foregroundStyle(WidgetColors.gold)
            Spacer(minLength: 2)
            Text(c.title).font(.system(size: 19, weight: .bold, design: .rounded)).foregroundStyle(WidgetColors.text)
                .lineLimit(2).minimumScaleFactor(0.75)
            if let l = c.line {
                Text(l).font(.system(size: 12)).foregroundStyle(WidgetColors.muted).lineLimit(2)
            } else if let p = c.players {
                Text(p).font(.system(size: 12)).foregroundStyle(WidgetColors.muted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The rejoin button (medium size), or a nudge to play when there's no recent room.
struct RejoinView: View {
    let last: RecentRoom?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let r = last {
                Text("LAST ROOM").font(.system(size: 11, weight: .heavy)).tracking(0.6).foregroundStyle(WidgetColors.muted)
                Text(r.code).font(.system(size: 26, weight: .heavy, design: .rounded)).foregroundStyle(WidgetColors.text)
                Text(r.playable?.title ?? "A game").font(.system(size: 12)).foregroundStyle(WidgetColors.muted).lineLimit(1)
                Spacer(minLength: 2)
                Label("Rejoin", systemImage: "arrow.uturn.backward")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(WidgetColors.ink)
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(WidgetColors.gold, in: Capsule())
            } else {
                Text("NO ROOM YET").font(.system(size: 11, weight: .heavy)).tracking(0.6).foregroundStyle(WidgetColors.muted)
                Spacer(minLength: 2)
                Text("Join with a code, or start a room.").font(.system(size: 13, weight: .semibold)).foregroundStyle(WidgetColors.text)
                Spacer(minLength: 2)
                Label("Play", systemImage: "gamecontroller.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(WidgetColors.ink)
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(WidgetColors.gold, in: Capsule())
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(WidgetColors.panel.opacity(0.9), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// The widget's background: navy, with the game's color coming up from below.
struct WidgetBackdrop: View {
    let game: Game?
    var body: some View {
        LinearGradient(colors: [WidgetColors.navy, WidgetColors.tint(game)], startPoint: .top, endPoint: .bottom)
    }
}

extension WidgetContent {
    /// The content for a day from a Library (the widget's own cached copy, or the four app games before it loads).
    static func make(_ day: Date, library: Library, last: RecentRoom?) -> WidgetContent {
        let i = library.gameOfTheDay(day) ?? Library.appOnly.gameOfTheDay(day)
        let fresh = last.flatMap { day.timeIntervalSince($0.at) < 6 * 3600 ? $0 : nil }   // rooms end; an old one isn't offered
        return WidgetContent(day: day, title: i?.title ?? "Overdraft", line: i?.blurb, players: i?.playersLine,
                             key: i?.key ?? "overdraft", game: i?.game, last: fresh)
    }

    static let sample = WidgetContent(day: Date(), title: "Hot Dice", line: "Roll six dice, keep what scores, and know when to stop.",
                                      players: "2–8 players", key: "farkle", game: .hotDice,
                                      last: RecentRoom(code: "K7QP", game: .overdraft))
}
