import WidgetKit
import SwiftUI
import T2PCore

/// The home screen widget: the game of the day, and (medium) one-tap rejoin of your last room.
/// It reads the Library itself (the same feed the app reads, kept in its own defaults for no signal) and the last
/// room from the Keychain group it shares with the app (Shared/SharedRoom.swift). Nothing else leaves the phone.
struct Provider: TimelineProvider {
    private static let libraryKey = "t2p.widget.library"

    func placeholder(in context: Context) -> Entry { Entry(date: Date(), content: .sample) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: Date(), content: context.isPreview ? .sample : WidgetContent.make(Date(), library: cached(), last: SharedRoom.load())))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        Task {
            var lib = cached()
            if let got = try? await API().library() {
                lib = got.0
                UserDefaults.standard.set(got.1, forKey: Provider.libraryKey)
            }
            let now = Date(), last = SharedRoom.load()
            // today now, then tomorrow from just after midnight (a new game of the day); the last room drops off by
            // itself once it's six hours old
            let cal = Calendar.current
            let midnight = cal.startOfDay(for: now.addingTimeInterval(86_400)).addingTimeInterval(60)
            var entries = [Entry(date: now, content: .make(now, library: lib, last: last))]
            if let r = last, now.timeIntervalSince(r.at) < 6 * 3600 {
                let drop = r.at.addingTimeInterval(6 * 3600)
                if drop < midnight { entries.append(Entry(date: drop, content: .make(drop, library: lib, last: last))) }
            }
            entries.append(Entry(date: midnight, content: .make(midnight, library: lib, last: last)))
            completion(Timeline(entries: entries, policy: .after(midnight.addingTimeInterval(3600))))
        }
    }

    private func cached() -> Library {
        UserDefaults.standard.data(forKey: Provider.libraryKey).flatMap { JSON.parse($0) }.flatMap { Library($0) } ?? .appOnly
    }
}

struct Entry: TimelineEntry {
    let date: Date
    let content: WidgetContent
}

struct Time2PlayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry

    var body: some View {
        let c = entry.content
        Group {
            if family == .systemMedium {
                HStack(spacing: 12) {
                    Link(destination: AppLinks.game(c.key)) { GameOfTheDayView(c: c) }
                    Link(destination: c.last.map { AppLinks.join($0.code) } ?? URL(string: "time2play://play")!) { RejoinView(last: c.last) }
                        .frame(width: 132)
                }
            } else {
                GameOfTheDayView(c: c).widgetURL(AppLinks.game(c.key))
            }
        }
        .containerBackground(for: .widget) { WidgetBackdrop(game: c.game) }
    }
}

@main
struct Time2PlayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Time2PlayToday", provider: Provider()) { Time2PlayWidgetView(entry: $0) }
            .configurationDisplayName("Time2Play")
            .description("The game of the day, and a quick way back to your last room.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
