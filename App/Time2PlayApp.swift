import SwiftUI
import T2PCore

@main
struct Time2PlayApp: App {
    @StateObject private var app = AppModel()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("-t2p-light") ? .light : nil)
                .onOpenURL { url in
                    // an invite link (time2play.live/K7QP) or a room's QR opened from elsewhere
                    if let c = RoomCode.fromLink(url) { Task { await app.join(code: c) } }
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
        .onChange(of: phase) { _, p in
            // the phone locked or the app was switched away: the room holds the seat (a bot plays); back, it resumes
            if p == .background { app.room?.pause() }
            if p == .active { app.room?.resume() }
        }
    }
}
