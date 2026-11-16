import SwiftUI
import UIKit
import AVKit
import T2PCore

/// The table on a TV (#405): when the phone is mirrored to a TV over AirPlay, the app draws its own picture there,
/// the room's public view (the room's screen socket, ?as=screen: every seat's count, the top card, scores; never a
/// hand), and keeps your hand on your phone. Nobody needs a big screen; anyone in the room can be the TV.
@MainActor
final class TVModel: ObservableObject {
    static let shared = TVModel()
    @Published private(set) var floor: JSON?
    @Published private(set) var game: Game?
    @Published private(set) var code: String?
    @Published var connected = false   // a TV is showing the app's picture
    @Published var previewing = false  // the phone is showing what the TV would (Show on TV → See what the TV shows)
    private var task: URLSessionWebSocketTask?
    private var watching: (Game, String, Endpoints)?

    /// Follow a room on the TV (called when a room opens; a no-op without a TV).
    func watch(_ g: Game?, code: String?, endpoints: Endpoints) {
        if let g, let c = code { watching = (g, c, endpoints) } else { watching = nil }
        game = g; self.code = code; floor = nil
        reconnect()
    }

    func reconnect() {
        task?.cancel(with: .normalClosure, reason: nil); task = nil
        guard connected || previewing, let (g, c, e) = watching, c != "SOLO" else { return }
        let t = URLSession.shared.webSocketTask(with: e.screen(g, code: c))
        task = t; t.resume(); receive(t)
    }

    private func receive(_ t: URLSessionWebSocketTask) {
        t.receive { [weak self] r in
            Task { @MainActor in
                guard let self, t === self.task else { return }
                if case let .success(.string(s)) = r, let j = JSON.parse(s), j["t"].string == "floor" { self.floor = j }
                if case .success = r { self.receive(t) }
                else { DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.reconnect() } }
            }
        }
    }
}

/// The TV scene's own window (UIKit hands the app an external display scene, which can't be touched).
final class TVSceneDelegate: NSObject, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let ws = scene as? UIWindowScene else { return }
        let w = UIWindow(windowScene: ws)
        w.rootViewController = UIHostingController(rootView: TVTableView(model: TVModel.shared))
        w.isHidden = false
        window = w
        Task { @MainActor in TVModel.shared.connected = true; TVModel.shared.reconnect() }
    }
    func sceneDidDisconnect(_ scene: UIScene) {
        window = nil
        Task { @MainActor in TVModel.shared.connected = false; TVModel.shared.reconnect() }
    }
}

/// What the TV shows: the room's public table, big; or how to join when there's no room yet.
struct TVTableView: View {
    @ObservedObject var model: TVModel
    var body: some View {
        ZStack {
            (model.game == .hotDice ? T2P.felt : model.game == .overdraft ? T2P.table : Color(hex: 0x0B1121)).ignoresSafeArea()
            if let f = model.floor, let g = model.game {
                content(f, g)
            } else {
                VStack(spacing: 24) {
                    if let logo = Art.image("t2p-logo") { Image(uiImage: logo).resizable().scaledToFit().frame(height: 120) }
                    if let c = model.code, c != "SOLO" {
                        Text("Join at time2play.live").font(.system(size: 44, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                        Text(c).font(.system(size: 120, weight: .bold, design: .rounded)).tracking(16).foregroundStyle(.white)
                    } else {
                        Text("Start or join a room on your phone").font(.system(size: 40, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
        }
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private func content(_ f: JSON, _ g: Game) -> some View {
        let players = f["tables"][0]["seats"].array.isEmpty ? (f["players"].array.isEmpty ? f["roster"].array : f["players"].array) : f["tables"][0]["seats"].array
        HStack(spacing: 48) {
            VStack(alignment: .leading, spacing: 16) {
                Text(g.title).font(.system(size: 56, weight: .bold)).foregroundStyle(.white)
                Text("time2play.live · \(model.code ?? "")").font(.system(size: 28, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                ForEach(Array(players.prefix(10).enumerated()), id: \.offset) { _, p in
                    let turn = p["id"].string != nil && (p["id"].string == f["tables"][0]["turn"].string || p["id"].string == f["turn"]["id"].string)
                    HStack(spacing: 16) {
                        FaceView(face: p["face"].int ?? 0, size: 64).overlay(Circle().stroke(turn ? T2P.gold : .clear, lineWidth: 5).padding(-4))
                        Text(RoomPlayer.stripBot(p["name"].string ?? "")).font(.system(size: 34, weight: .semibold)).foregroundStyle(.white)
                        Spacer(minLength: 16)
                        Text(p["cards"].int.map { "\($0) cards" } ?? (p["score"].int ?? p["total"].int).map { $0.formatted() } ?? "")
                            .font(.system(size: 32, weight: .bold).monospacedDigit()).foregroundStyle(.white.opacity(0.9))
                    }
                    .frame(maxWidth: 560)
                }
            }
            if g == .overdraft, let top = f["tables"][0]["top"].object.map({ _ in f["tables"][0]["top"] }) {
                let card = Overdraft.Card(kind: top["kind"].string ?? "number", suit: top["suit"].string, n: top["n"].int)
                CardImage(name: card.artName, width: 300).shadow(radius: 24).accessibilityLabel(card.spoken)
            } else if g == .hotDice || g == .rollCall {
                let dice = f["turn"]["dice"].array.compactMap { $0["v"].int ?? $0.int }
                HStack(spacing: 20) { ForEach(Array(dice.enumerated()), id: \.offset) { _, v in DieView(value: v, size: 110) } }
            } else if g == .closeEnough, let q = f["question"]["q"].string {
                Text(q).font(.system(size: 48, weight: .bold)).foregroundStyle(.white).frame(maxWidth: 900)
            }
        }
        .padding(64)
    }
}

/// Show on TV: the phone's own AirPlay picker, and what to expect.
struct ShowOnTV: View {
    @Environment(\.dismiss) private var dismiss
    @State private var preview = false
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Put the table on a TV").font(.title2.bold()).foregroundStyle(T2P.text)
                Label("Open Control Center, tap Screen Mirroring, and pick your TV or Apple TV.", systemImage: "rectangle.on.rectangle")
                Label("The TV shows the table and the scores. Your hand stays on your phone.", systemImage: "eye.slash")
                Label("Anyone in the room can do this. No big screen is needed to play.", systemImage: "person.3")
                HStack { Spacer(); RoutePicker().frame(width: 60, height: 60); Spacer() }
                    .accessibilityLabel("AirPlay devices")
                Button("See what the TV shows") { preview = true }.buttonStyle(QuietButtonStyle()).accessibilityIdentifier("tv-preview")
                Spacer()
            }
            .foregroundStyle(T2P.text)
            .padding(24)
            .background(T2P.navy.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .fullScreenCover(isPresented: $preview) {
                TVTableView(model: TVModel.shared)
                    .overlay(alignment: .topTrailing) {
                        Button("Close") { preview = false }.buttonStyle(QuietButtonStyle()).padding().accessibilityIdentifier("tv-close")
                    }
                    .onAppear { TVModel.shared.previewing = true; TVModel.shared.reconnect() }
                    .onDisappear { TVModel.shared.previewing = false; TVModel.shared.reconnect() }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView(); v.prioritizesVideoDevices = true; v.activeTintColor = UIColor(hex: 0xE9B45A); v.tintColor = .white
        return v
    }
    func updateUIView(_ v: AVRoutePickerView, context: Context) {}
}
