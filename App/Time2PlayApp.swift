import SwiftUI
import UserNotifications
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
        return UISceneConfiguration(name: nil, sessionRole: session.role)
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in self.app?.registerDevice(deviceToken) }
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {}
    // an alert that arrives while the app is open still shows as a banner
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        Task { @MainActor in await self.app?.refreshSocial() }
        return [.banner, .sound]
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let room = info["room"] as? String
        let friends = info["friends"] as? Bool ?? false
        await MainActor.run {
            guard let app = self.app else { return }
            if let r = room, let c = RoomCode.normalize(r) { Task { await app.join(code: c) } }
            else if friends { app.tab = .friends; Task { await app.refreshSocial() } }
        }
    }
}

@main
struct Time2PlayApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var app = AppModel()
    var body: some Scene {
        WindowGroup {
            if let still = Table3DStill.fromArgs() {
                // #496's screenshots: the 3D table, made up and stopped at a moment
                Table3DView(view: still.view, onLeave: {}, still: still)
            } else if let dice = DiceStill.fromArgs() {
                // #521's screenshots: the 3D dice, a made-up turn stopped at a moment
                DiceStillView(still: dice)
            } else {
            RootView()
                .environmentObject(app)
                .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("-t2p-light") ? .light : nil)
                .onAppear { delegate.app = app; GameCenter.shared.start() }   // #541: only does anything once a player turns it on
                .onOpenURL { url in
                    // an invite link (time2play.live/K7QP), a friend or group link (time2play.live/f/CODE), or the app's
                    // own time2play://join/K7QP
                    if let f = FriendLink.code(url) { Task { await app.openFriendLink(f) } }
                    else if let c = RoomCode.fromLink(url) { Task { await app.join(code: c) } }
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { a in
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
        .alert("Can’t join", isPresented: Binding(get: { app.problem != nil }, set: { if !$0 { app.problem = nil; app.webFallback = nil } })) {
            if let u = app.webFallback { Button("Open on the website") { openURL(u) } }
            Button("OK", role: .cancel) {}
        } message: { Text(app.problem ?? "") }
        .alert("Account", isPresented: Binding(get: { app.accountProblem != nil }, set: { if !$0 { app.accountProblem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(app.accountProblem ?? "") }
        .alert(app.notice ?? "", isPresented: Binding(get: { app.notice != nil }, set: { if !$0 { app.notice = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .onChange(of: phase) { _, p in
            // the phone locked or the app was switched away: the room holds the seat (a bot plays); back, it resumes
            if p == .background { app.room?.pause() }
            if p == .active { app.room?.resume(); Task { await app.refreshSocial() } }
        }
    }
}
