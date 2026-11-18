import SwiftUI
import T2PCore

/// Stats and achievements (#540). The phone's ledger of finished online games (practice doesn't count), the account's
/// stats from the server when signed in, and the achievements earned from both. Kept on this phone in "t2p.ledger".
@MainActor
final class StatsKeeper: ObservableObject {
    static let shared = StatsKeeper()
    static let key = "t2p.ledger"
    /// The achievements already said on screen (build 48): each is announced once, ever. A new key; the version before
    /// never reads it.
    static let announcedKey = "t2p.announced"
    /// The finished games already recorded, by room and game (build 48): a room reopened on its winner screen, or
    /// rejoined, never counts the same game twice. A new key, kept short.
    static let recordedKey = "t2p.recordedGames"
    static let achievementPrefix = "Achievement: "
    /// UI tests only (-t2p-earn-test): see init.
    static var earnTest: Bool { ProcessInfo.processInfo.arguments.contains("-t2p-earn-test") }
    @Published private(set) var ledger: [LedgerEntry]
    @Published private(set) var server: PlayerStats?
    /// Called with each achievement as it's earned (Game Center reports it, #541).
    var onEarned: ((Achievement) -> Void)?
    /// Called with each finished game (Game Center's leaderboards, #541).
    var onFinished: ((LedgerEntry) -> Void)?

    private struct Track { var recorded = false; var bullseye = false }
    private var tracks: [UUID: Track] = [:]

    private var announced: Set<String>
    private var recordedGames: [String]

    init() {
        let d = UserDefaults.standard
        if ProcessInfo.processInfo.arguments.contains("-uitest-reset") {
            for k in [StatsKeeper.key, StatsKeeper.announcedKey, StatsKeeper.recordedKey] { d.removeObject(forKey: k) }
        }
        let saved = Ledger.decode(d.data(forKey: StatsKeeper.key))
        ledger = saved
        recordedGames = d.stringArray(forKey: StatsKeeper.recordedKey) ?? []
        if let a = d.stringArray(forKey: StatsKeeper.announcedKey) {
            announced = Set(a)
        } else {
            // first run with this key: whatever was earned before has had its moment, so it's never said again
            let before = Set(Achievement.all.filter { $0.earned(Ledger.stats(saved), saved) }.map(\.id))
            announced = before
            d.set(Array(before).sorted(), forKey: StatsKeeper.announcedKey)
        }
        // a UI test earns an achievement in one finished game: nine played already (one won), so the next earns Regular
        // (10 games) and nothing else, won or lost; its practice game counts
        if StatsKeeper.earnTest, ledger.isEmpty {
            ledger = [LedgerEntry(game: .rollCall, won: true, score: 100)] + (0..<8).map { _ in LedgerEntry(game: .rollCall, won: false, score: 100) }
        }
    }

    var local: PlayerStats { Ledger.stats(ledger) }
    var stats: PlayerStats { server.map { $0.merged(with: local) } ?? local }
    var earned: [Achievement] { Achievement.all.filter { $0.earned(stats, ledger) } }

    func refresh(_ api: API, signedIn: Bool) async {
        guard signedIn else { server = nil; return }
        if let s = try? await api.stats() { server = s }
    }

    /// Watches a room's views for a finished game, and records it once.
    func observe(_ room: RoomModel) {
        guard !room.offline || StatsKeeper.earnTest, let v = room.view, let me = room.meId else { return }
        var t = tracks[room.id] ?? Track()
        defer { tracks[room.id] = t }
        guard v["you"]["seated"].bool ?? true else { return }
        switch room.game {
        case .overdraft:
            let over = v["table"]["over"].bool == true
            if !over { t.recorded = false; return }
            if t.recorded { return }
            t.recorded = true
            record(LedgerEntry(game: .overdraft, won: v["table"]["winner"].string == me, score: nil), room: room)
        case .closeEnough:
            let q = v["question"]
            if q["stage"].string == "reveal", let pts = q["results"][me]["points"].int, pts >= (v["maxPoints"].int ?? 20) { t.bullseye = true }
            guard done(v, &t) else { return }
            let won = v["winners"].array.compactMap(\.string).contains(me)
            record(LedgerEntry(game: .closeEnough, won: won, score: myScore(v, me), flags: t.bullseye ? ["bullseye"] : []), room: room)
            t.bullseye = false
        case .hotDice:
            guard done(v, &t) else { return }
            let won = v["winners"].array.compactMap(\.string).contains(me)
            record(LedgerEntry(game: .hotDice, won: won, score: myScore(v, me), flags: v["target"].int == 10000 ? ["target10k"] : []), room: room)
        case .rollCall:
            guard done(v, &t) else { return }
            let won = v["winners"].array.compactMap(\.string).contains(me)
            let mine = v["players"].array.first { $0["id"].string == me }
            let boxes = (mine?["scores"].object ?? [:]).compactMapValues(\.int)
            let full = boxes.count >= RollCall.boxes.count && boxes.values.allSatisfy { $0 > 0 }
            record(LedgerEntry(game: .rollCall, won: won, score: myScore(v, me), flags: full ? ["fullCard"] : []), room: room)
        }
    }

    private func done(_ v: JSON, _ t: inout Track) -> Bool {
        if v["phase"].string != "done" { t.recorded = false; return false }
        if t.recorded { return false }
        t.recorded = true
        return true
    }

    /// One finished game's name: the room, the winners and every seat's score. The same game seen again (the room
    /// reopened on its winner screen, a rejoin) has the same name; a game played again in the room has new scores.
    private func gameKey(_ room: RoomModel, _ v: JSON) -> String {
        let seats = v["players"].array.map { "\($0["id"].string ?? "")=\($0["score"].int ?? $0["total"].int ?? 0)" }.joined(separator: ",")
        let won = v["winners"].array.compactMap(\.string).joined(separator: ",")
        return "\(room.game.rawValue):\(room.code):\(v["table"]["winner"].string ?? won):\(seats)"
    }
    private func myScore(_ v: JSON, _ me: String) -> Int? {
        let p = v["players"].array.first { $0["id"].string == me }
        return p?["score"].int ?? p?["total"].int
    }

    private func record(_ e: LedgerEntry, room: RoomModel) {
        if let v = room.view {
            let key = gameKey(room, v)
            if recordedGames.contains(key) { return }
            recordedGames = Array((recordedGames + [key]).suffix(50))
            UserDefaults.standard.set(recordedGames, forKey: StatsKeeper.recordedKey)
        }
        let before = Set(earned.map(\.id))
        ledger = Ledger.adding(e, to: ledger)
        UserDefaults.standard.set(Ledger.encode(ledger), forKey: StatsKeeper.key)
        onFinished?(e)
        let new = earned.filter { !before.contains($0.id) }
        for a in new { onEarned?(a) }
        // said on screen once, ever: never one announced before (a server's stats can make one look new again)
        let fresh = new.filter { !announced.contains($0.id) }
        guard !fresh.isEmpty else { return }
        announced.formUnion(fresh.map(\.id))
        UserDefaults.standard.set(Array(announced).sorted(), forKey: StatsKeeper.announcedKey)
        let words = fresh.count == 1 ? fresh[0].title : "\(fresh[0].title) and \(fresh.count - 1) more"
        room.toast = StatsKeeper.achievementPrefix + words   // goes on its own after about 3 seconds
        UIAccessibility.post(notification: .announcement, argument: "Achievement earned: \(words)")
    }

    /// A test can fill the ledger (-t2p-ledger-demo) to show the stats and achievements screens.
    func demo() {
        guard ProcessInfo.processInfo.arguments.contains("-t2p-ledger-demo"), ledger.isEmpty else { return }
        ledger = [LedgerEntry(game: .hotDice, won: true, score: 10_250, flags: ["target10k"]), LedgerEntry(game: .hotDice, won: false, score: 6_400),
                  LedgerEntry(game: .rollCall, won: true, score: 287), LedgerEntry(game: .overdraft, won: true, score: nil),
                  LedgerEntry(game: .closeEnough, won: false, score: 74, flags: ["bullseye"]), LedgerEntry(game: .hotDice, won: false, score: 8_900)]
    }
}

/// You → Your games: wins, games played, best scores and favorite games (signed in), and the achievements (everyone).
struct StatsSections: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject private var keeper = StatsKeeper.shared

    var body: some View {
        let s = keeper.stats
        Group {
            if app.signedIn || ProcessInfo.processInfo.arguments.contains("-t2p-ledger-demo") {
                Section {
                    HStack(spacing: 0) {
                        tile("\(s.games)", "Games")
                        tile("\(s.wins)", "Wins")
                        tile(s.games > 0 ? "\(Int((Double(s.wins) / Double(s.games) * 100).rounded()))%" : "–", "Win rate")
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("stats-totals")
                    ForEach(Game.allCases) { g in
                        if let b = s.byGame[g.rawValue], b.played > 0 {
                            HStack {
                                Image(systemName: g.symbol).foregroundStyle(T2P.gold).frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(g.title).foregroundStyle(T2P.text)
                                    Text("\(b.played) played · \(b.wins) won").font(.caption).foregroundStyle(T2P.muted)
                                }
                                Spacer()
                                if let best = b.best, g != .overdraft {
                                    VStack(alignment: .trailing, spacing: 0) {
                                        Text(best.formatted()).font(.headline.monospacedDigit()).foregroundStyle(T2P.text)
                                        Text("best").font(.caption2).foregroundStyle(T2P.faint)
                                    }
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    if let fav = s.favorites.first.flatMap(Game.init(rawValue:)) {
                        Label("Favorite: \(fav.title)", systemImage: "heart.fill").foregroundStyle(T2P.text)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("stats-favorite")
                    }
                } header: { Text("Your games") } footer: {
                    Text(keeper.server == nil ? "Online games on this phone. Practice games don’t count." : "From your account and this phone. Practice games don’t count.")
                        .foregroundStyle(T2P.muted)
                }
                .listRowBackground(T2P.panel)
            }
            Section {
                NavigationLink {
                    AchievementsList()
                } label: {
                    HStack {
                        Label("Achievements", systemImage: "rosette").foregroundStyle(T2P.text)
                        Spacer()
                        Text("\(keeper.earned.count) of \(Achievement.all.count)").foregroundStyle(T2P.muted)
                    }
                }
                .accessibilityIdentifier("achievements")
            }
            .listRowBackground(T2P.panel)
        }
        .task { keeper.demo(); await keeper.refresh(app.api, signedIn: app.signedIn) }
    }

    private func tile(_ n: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(n).font(.title2.bold().monospacedDigit()).foregroundStyle(T2P.text)
            Text(label).font(.caption).foregroundStyle(T2P.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

struct AchievementsList: View {
    @ObservedObject private var keeper = StatsKeeper.shared
    var body: some View {
        List {
            ForEach(Achievement.all) { a in
                let p = a.progress(keeper.stats, keeper.ledger)
                HStack(spacing: 14) {
                    Image(systemName: a.symbol).font(.title2)
                        .foregroundStyle(p >= 1 ? T2P.ink : T2P.faint)
                        .frame(width: 48, height: 48)
                        .background(p >= 1 ? T2P.gold : T2P.panelHi, in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(a.title).font(.headline).foregroundStyle(T2P.text)
                        Text(a.detail).font(.subheadline).foregroundStyle(T2P.muted)
                        if p < 1 && p > 0 { ProgressView(value: p).tint(T2P.gold) }
                    }
                    Spacer()
                    if p >= 1 { Image(systemName: "checkmark.seal.fill").foregroundStyle(T2P.gold) }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
                .accessibilityValue(p >= 1 ? "Earned" : "\(Int(p * 100)) percent")
                .accessibilityIdentifier("achievement-\(a.id)")
            }
            .listRowBackground(T2P.panel)
        }
        .scrollContentBackground(.hidden)
        .background(T2P.navy.ignoresSafeArea())
        .navigationTitle("Achievements")
    }
}
