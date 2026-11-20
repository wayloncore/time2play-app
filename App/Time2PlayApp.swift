import SwiftUI
import UserNotifications
import StoreKit
import T2PCore

/// Push alerts (#404): this device's token goes to the server for a signed-in player; tapping an invite joins its room.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    weak var app: AppModel?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    /// A TV over AirPlay gets the table as its own picture (#405), not a mirror of the phone.
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if session.role == .windowExternalDisplayNonInteractive {
            let c = UISceneConfiguration(name: "TV", sessionRole: session.role)
            c.delegateClass = TVSceneDelegate.self
            return c
        }
        // opened by a link, a QR scan, an invite, an alert or the widget: straight in, no intro (#562)
        if !options.urlContexts.isEmpty || !options.userActivities.isEmpty || options.notificationResponse != nil {
            Intro.shared.skip()
        }
        return UISceneConfiguration(name: nil, sessionRole: session.role)
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in self.app?.registerDevice(deviceToken) }
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {}
    // an alert that arrives while the app is open still shows as a banner (a "your turn" for the room you're in
    // doesn't: you can see it's your turn)
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let info = notification.request.content.userInfo
        if (info["kind"] as? String) == "turn", let r = info["room"] as? String {
            let here = await MainActor.run { self.app?.room?.code == RoomCode.normalize(r) }
            if here { return [] }
        }
        // an invite (a room, and no kind) while the app is open: the painted banner with Join, not the system's (Nov 18)
        if info["kind"] == nil, let r = info["room"] as? String, let code = RoomCode.normalize(r) {
            let text = notification.request.content.body
            let game = (info["game"] as? String).flatMap(Game.init(rawValue:))
            await MainActor.run {
                guard let app = self.app, app.room?.code != code else { return }
                AppDialogs.shared.showBanner(InviteNote(text: text.isEmpty ? "You’re invited to \(game?.title ?? "a game")" : text, game: game, room: code))
                Task { await app.refreshSocial() }
            }
            return [.sound]
        }
        Task { @MainActor in await self.app?.refreshSocial() }
        return [.banner, .sound]
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        Intro.shared.skip()   // an invite or "your turn" goes straight in (#562)
        let room = info["room"] as? String
        let kind = info["kind"] as? String
        let friends = info["friends"] as? Bool ?? false
        await MainActor.run {
            guard let app = self.app else { return }
            // an invite or a "your turn" (#534): open its room (a room you're already in just carries on); an invite
            // also leaves Friends' list once it's used
            if let r = room, let c = RoomCode.normalize(r) {
                if kind == nil { Task { await app.openInvite(code: c) } } else { Task { await app.openRoom(code: c) } }
            }
            else if friends { app.tab = .friends; Task { await app.refreshSocial() } }
        }
    }
}

@main
struct Time2PlayApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var app = AppModel()
    #if DEBUG
    private var artGallery: Bool { ArtGallery.requested }
    private var galleryView: some View {
        ArtGallery().preferredColorScheme(ProcessInfo.processInfo.arguments.contains("-t2p-light") ? .light : .dark)
    }
    #else
    private var artGallery: Bool { false }
    private var galleryView: some View { EmptyView() }
    #endif
    var body: some Scene {
        WindowGroup {
            if let still = Table3DStill.fromArgs(), still.classic {
                // #609's screenshots: the classic hand with the same made-up cards
                ClassicHandStill(still: still)
            } else if let still = Table3DStill.fromArgs() {
                // #496's screenshots: the 3D table, made up and stopped at a moment
                Table3DView(view: still.view, onLeave: {}, still: still)
            } else if let dice = DiceStill.fromArgs() {
                // #521's screenshots: the 3D dice, a made-up turn stopped at a moment
                DiceStillView(still: dice)
            } else if let w = WidgetStill.fromArgs() {
                // the home screen widget's screenshots, at its real sizes
                WidgetStillView(still: w)
            } else if SpinnerGallery.requested {
                // #543's screenshots: the loading spinner at its sizes
                SpinnerGallery()
            } else if artGallery {
                // Nov 18's screenshots: each game's picture at its real sizes (the test build only)
                galleryView
            } else {
            RootView()
                .overlay { IntroOverlay() }   // the intro at a fresh launch, over Play, which starts underneath (#562)
                .environmentObject(app)
                .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("-t2p-light") ? .light : nil)
                .onAppear {
                    delegate.app = app; GameCenter.shared.start()   // #541: only does anything once a player turns it on
                    TipJar.shared.listen(); Task { await TipJar.shared.load() }   // #598: hidden unless the App Store has the tips
                }
                .onOpenURL { url in
                    Intro.shared.skip()   // links go straight in, never through the intro (#562)
                    // an invite link (time2play.live/K7QP), a friend or group link (time2play.live/f/CODE), or the app's
                    // own time2play://join/K7QP (the widget's rejoin) and time2play://game/<key> (its game of the day)
                    if let f = FriendLink.code(url) { Task { await app.openFriendLink(f) } }
                    else if let k = AppLinks.gameKey(url) { app.showLibraryItem(k) }
                    else if url.scheme == "time2play" && url.host == "play" { app.tab = .play }
                    else if let c = RoomCode.fromLink(url) { Task { await app.openRoom(code: c) } }
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { a in
                    Intro.shared.skip()
                    guard let url = a.webpageURL else { return }
                    if let f = FriendLink.code(url) { Task { await app.openFriendLink(f) } }
                    else if let c = RoomCode.fromLink(url) { Task { await app.join(code: c) } }
                }
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.scenePhase) private var phase
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview

    var body: some View {
        TabView(selection: $app.tab) {
            PlayView()
                .tabItem { Label("Play", systemImage: "gamecontroller.fill") }
                .tag(AppModel.Tab.play)
            FriendsView()
                .tabItem { Label("Friends", systemImage: "person.2.fill") }
                .badge(app.challenges.count + app.friends.incoming.count)
                .tag(AppModel.Tab.friends)
            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical.fill") }
                .tag(AppModel.Tab.library)
            YouView()
                .tabItem { Label("You", systemImage: "person.crop.circle") }
                .tag(AppModel.Tab.you)
        }
        .tint(T2P.gold)
        .fullScreenCover(item: $app.room) { room in
            RoomView(room: room)
                .environmentObject(app)
        }
        // the app's own messages, painted (Nov 18): over everything, the way an iOS alert was
        .onChange(of: app.problem) { _, p in
            guard let p else { return }
            let a = app, web = app.webFallback, open = openURL
            let clear = { a.problem = nil; a.webFallback = nil }
            AppDialogs.shared.show(GameDialog(
                title: "Can’t join", message: p,
                choices: web.map { u in [GameChoice(label: "Open on the website", kind: .gold, identifier: "open-website") { open(u); clear() }] } ?? [],
                cancel: "OK", onCancel: clear, identifier: "dialog-problem"))
        }
        // #594 part 3: back from a finished game, Apple's own rating request, at most once a version (iOS may show
        // nothing; it keeps it to three a year). Never during a game, and never in the UI tests unless they ask.
        .onChange(of: app.reviewDue) { _, due in
            guard due else { return }
            app.reviewDue = false
            let d = UserDefaults.standard, v = AppModel.appVersion
            let args = ProcessInfo.processInfo.arguments
            guard ReviewAsk.shouldAsk(finishedGame: true, lastAskedVersion: d.string(forKey: ReviewAsk.key), version: v),
                  !args.contains("-uitest-reset") || args.contains("-t2p-review") else { return }
            let a = app, ask = requestReview
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                guard a.room == nil else { return }   // they went straight into another room: not now
                d.set(v, forKey: ReviewAsk.key)
                ask()
            }
        }
        .onChange(of: app.accountProblem) { _, p in
            guard let p else { return }
            let a = app
            AppDialogs.shared.say("That didn’t work", p, identifier: "dialog-account") { a.accountProblem = nil }
        }
        .onChange(of: app.notice) { _, n in
            guard let n else { return }
            let a = app
            AppDialogs.shared.say(n, ok: "OK", identifier: "dialog-notice") { a.notice = nil }
        }
        .onAppear {
            let a = app
            AppDialogs.shared.onJoin = { code in Task { await a.openInvite(code: code) } }
            // the test build's banner, for its screenshot
            if SocialDemo.banner {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    MainActor.assumeIsolated {
                        AppDialogs.shared.showBanner(InviteNote(text: "Sam invited you to 10,000", game: .hotDice, room: "DEMO", face: 3))
                    }
                }
            }
        }
        .onChange(of: phase) { _, p in
            // the phone locked or the app was switched away: the room holds the seat (a bot plays); back, it resumes
            if p == .background { if let r = app.room { app.keep.note(r) }; app.room?.pause() }
            if p == .active { app.room?.resume(); Task { await app.refreshSocial(); await TipJar.shared.load() } }
        }
    }
}
