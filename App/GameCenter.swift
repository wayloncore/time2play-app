import SwiftUI
import GameKit
import T2PCore

/// Game Center (#541): optional, off until a player turns it on in You, and never needed to play. When it's on, each
/// finished online game's score goes to its game's leaderboard (best score) and each achievement (#540) is reported as
/// it's earned. If Game Center isn't set up for the app yet, or the player isn't signed in to it, nothing changes.
@MainActor
final class GameCenter: ObservableObject {
    static let shared = GameCenter()
    static let key = "t2p.gameCenter"
    /// The leaderboards (App Store Connect, scripts/asc.py gamecenter): best scores, higher is better.
    static let leaderboards: [Game: String] = [.hotDice: "t2p.best.hotdice", .rollCall: "t2p.best.rollcall", .closeEnough: "t2p.best.closeenough"]

    @Published private(set) var signedIn = false
    @Published private(set) var problem: String?
    private var started = false

    var on: Bool { UserDefaults.standard.bool(forKey: GameCenter.key) }

    /// Wires the stats to Game Center (once, at launch) and signs in if the player turned it on.
    func start() {
        guard !started else { return }
        started = true
        StatsKeeper.shared.onFinished = { [weak self] e in Task { @MainActor in self?.report(e) } }
        StatsKeeper.shared.onEarned = { [weak self] a in Task { @MainActor in self?.report([a]) } }
        if on { signIn() }
    }

    func setOn(_ v: Bool) {
        UserDefaults.standard.set(v, forKey: GameCenter.key)
        if v { signIn() } else { GKAccessPoint.shared.isActive = false }
    }

    func signIn() {
        guard !ProcessInfo.processInfo.arguments.contains("-uitest-reset") || ProcessInfo.processInfo.arguments.contains("-t2p-gamecenter") else { return }
        GKLocalPlayer.local.authenticateHandler = { [weak self] vc, error in
            Task { @MainActor in
                guard let self else { return }
                if let vc { GameCenter.top()?.present(vc, animated: true); return }
                self.signedIn = GKLocalPlayer.local.isAuthenticated
                if let e = error as NSError? {
                    self.problem = e.code == GKError.Code.gameUnrecognized.rawValue || e.code == GKError.Code.notSupported.rawValue
                        ? "Game Center isn’t ready for Time2Play yet. Everything else works as usual."
                        : "Sign in to Game Center in Settings to use it here. Everything else works as usual."
                } else { self.problem = nil }
                if self.signedIn { self.report(StatsKeeper.shared.earned) }
            }
        }
    }

    private func report(_ e: LedgerEntry) {
        guard on, signedIn, let g = Game(rawValue: e.game), let board = GameCenter.leaderboards[g], let s = e.score else { return }
        GKLeaderboard.submitScore(s, context: 0, player: GKLocalPlayer.local, leaderboardIDs: [board]) { _ in }
    }

    private func report(_ list: [Achievement]) {
        guard on, signedIn, !list.isEmpty else { return }
        let a = list.map { x -> GKAchievement in
            let g = GKAchievement(identifier: x.id)
            g.percentComplete = 100
            // never Game Center's own banner: the app says each achievement once, itself (build 48), and a sign-in
            // re-sends every earned one, which must not announce them all again
            g.showsCompletionBanner = false
            return g
        }
        GKAchievement.report(a) { _ in }
    }

    func show(_ state: GKGameCenterViewControllerState) {
        guard signedIn else { signIn(); return }
        GKAccessPoint.shared.trigger(state: state) {}
    }

    private static func top() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
        var vc = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let p = vc?.presentedViewController { vc = p }
        return vc
    }
}

/// You → Game Center: the switch, and the leaderboards and achievements when signed in.
struct GameCenterSection: View {
    @ObservedObject private var gc = GameCenter.shared
    @AppStorage(GameCenter.key) private var on = false
    var body: some View {
        Section {
            Toggle("Game Center", isOn: Binding(get: { on }, set: { on = $0; gc.setOn($0) }))
                .tint(T2P.gold).accessibilityIdentifier("toggle-gamecenter")
            if on && gc.signedIn {
                Button("Leaderboards") { gc.show(.leaderboards) }.accessibilityIdentifier("gc-leaderboards")
                Button("Achievements in Game Center") { gc.show(.achievements) }
            }
        } footer: {
            Text(on ? (gc.problem ?? "Best scores in 10,000, Yacht Dice and Close Enough go to the leaderboards, and achievements show in Game Center. Practice games don’t count.")
                 : "Optional. Share best scores and achievements through Game Center. You never need it to play.")
                .foregroundStyle(T2P.muted)
        }
        .listRowBackground(T2P.panel)
    }
}
