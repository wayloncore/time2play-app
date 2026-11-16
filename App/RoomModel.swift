import SwiftUI
import T2PCore

/// One room on screen: the session (Core), the socket, and what the screens draw from them.
@MainActor
final class RoomModel: ObservableObject, Identifiable {
    let id = UUID()
    let game: Game
    let code: String
    let starting: Bool
    private let session: RoomSession
    private let transport = WebSocketTransport()
    private weak var app: AppModel?
    private var retry: DispatchWorkItem?

    @Published private(set) var status: RoomSession.Status = .connecting
    @Published private(set) var view: JSON?
    @Published var taken: [Int]
    @Published var toast: String?
    @Published var reactions: [ShownReaction] = []
    @Published var back: String?

    struct ShownReaction: Identifiable, Equatable { let id = UUID(); let who: String; let words: String }

    init(game: Game, code: String, app: AppModel, taken: [Int], starting: Bool) {
        self.game = game; self.code = code; self.app = app; self.taken = taken; self.starting = starting
        session = RoomSession(game: game, code: code, endpoints: app.endpoints, appVersion: AppModel.appVersion,
                              transport: transport, store: app.seats)
        session.onChange = { [weak self] in self?.sync() }
        session.onNotice = { [weak self] n in self?.notice(n) }
    }

    var seat: Seat? { session.seat }
    var hasSeat: Bool { session.seat != nil }

    func start() {
        // a name and face already picked: join as soon as the socket is open (a resume wins if there's a seat)
        if session.seat == nil, let p = app?.profile, p.name.count >= 2, starting {
            session.join(name: p.name, face: p.face)
        }
        session.start()
    }

    func join(name: String, face: Int?) { session.join(name: name, face: face) }
    func send(_ m: JSON) { session.send(m) }
    func move(_ t: String, _ fields: [String: JSON] = [:]) { session.move(t, fields) }
    func react(_ r: Reaction) { session.send(Out.react(r)); Haptics.select() }

    func pause() { retry?.cancel(); session.pause() }
    func resume() { retry?.cancel(); session.reconnect() }
    func leave() { retry?.cancel(); session.leave() }
    func close() { retry?.cancel(); transport.close() }

    private func sync() {
        status = session.status
        view = session.view
        if case .reconnecting = session.status {
            retry?.cancel()
            let w = DispatchWorkItem { [weak self] in self?.session.reconnect() }
            retry = w
            DispatchQueue.main.asyncAfter(deadline: .now() + session.reconnectDelay, execute: w)
        }
    }

    private func notice(_ n: RoomSession.Notice) {
        switch n {
        case let .reaction(pid, r):
            let who = playerName(pid) ?? "Someone"
            let shown = ShownReaction(who: who, words: r.words)
            reactions.append(shown)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in self?.reactions.removeAll { $0.id == shown.id } }
            UIAccessibility.post(notification: .announcement, argument: "\(who): \(r.words)")
        case let .problem(msg):
            toast = msg; Haptics.nope()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in if self?.toast == msg { self?.toast = nil } }
        case let .back(msg):
            back = msg
            UIAccessibility.post(notification: .announcement, argument: msg)
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in if self?.back == msg { self?.back = nil } }
        }
    }

    /// A player's name by id, from whichever list this game's view has.
    func playerName(_ id: String) -> String? {
        guard let v = view else { return nil }
        for list in [v["roster"], v["players"], v["table"]["seats"]] {
            if let p = list.array.first(where: { $0["id"].string == id }), let n = p["name"].string { return RoomPlayer.stripBot(n) }
        }
        return nil
    }

    var meId: String? { view?["you"]["id"].string ?? session.seat?.id }
    var isOwner: Bool { view?["hostless"].bool == true && view?["owner"].string == meId && meId != nil }
    var phase: String { view?["phase"].string ?? "lobby" }
    var inviteLink: URL { app?.endpoints.invite(code: code) ?? Endpoints.live.invite(code: code) }
}
