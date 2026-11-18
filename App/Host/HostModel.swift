import SwiftUI
import T2PCore

/// Hosting a room from an iPad (#537): the iPad is the room's big screen. It starts a hosted room (the kind the website's
/// game pages start), opens the host's screen socket with the host token, shows the floor (everyone's public view) and
/// sends the host's messages. Players join on their phones with the code or the QR. A TV over AirPlay gets the same
/// floor, fed from here (a hosted room's screen needs the token, so the TV never opens a socket of its own).
/// The host token stays in memory only: never shown, logged or saved.
@MainActor
final class HostModel: ObservableObject, Identifiable {
    enum Status: Equatable { case connecting, live, reconnecting, ended(String) }
    let id = UUID()
    let room: HostedRoom
    private let endpoints: Endpoints
    @Published private(set) var floor: JSON?
    @Published private(set) var status: Status = .connecting
    @Published var toast: String?
    private var task: URLSessionWebSocketTask?
    private var pinger: Timer?
    private var stopped = false
    private var landedSent: Int?
    private var failures = 0

    init(room: HostedRoom, endpoints: Endpoints) { self.room = room; self.endpoints = endpoints }

    var game: Game { room.game }
    var phase: String { floor?["phase"].string ?? "lobby" }
    var invite: URL { endpoints.invite(code: room.code) }
    var players: [FloorPlayer] { floor.map { Floor.players($0, game: game) } ?? [] }

    func start() {
        TVModel.shared.host(game, code: room.code)
        connect()
        pinger = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sendRaw(Out.ping) }
        }
    }

    private func connect() {
        task?.cancel(with: .normalClosure, reason: nil)
        let t = URLSession.shared.webSocketTask(with: endpoints.hostScreen(room))
        task = t
        t.resume()
        receive(t)
    }

    private func receive(_ t: URLSessionWebSocketTask) {
        t.receive { [weak self] r in
            Task { @MainActor in
                guard let self, t === self.task, !self.stopped else { return }
                switch r {
                case let .success(.string(s)):
                    self.handle(s)
                    self.receive(t)
                case .success:
                    self.receive(t)
                case .failure:
                    if case .ended = self.status { return }
                    if t.closeCode.rawValue == 4010 { self.end("This room isn’t yours to host any more.") ; return }
                    if t.closeCode.rawValue == 4005 { self.end("The room has ended."); return }
                    self.failures += 1
                    self.status = .reconnecting
                    DispatchQueue.main.asyncAfter(deadline: .now() + min(8, Double(self.failures) * 1.5)) { [weak self] in
                        guard let self, !self.stopped else { return }
                        self.connect()
                    }
                }
            }
        }
    }

    private func handle(_ s: String) {
        guard let j = JSON.parse(s) else { return }
        switch j["t"].string {
        case "floor":
            floor = j; status = .live; failures = 0
            TVModel.shared.feed(j)
            showDice(j)
        case "error":
            if j["code"].string == "host" { end(j["error"].string ?? "This room isn’t yours to host any more.") }
            else { show(j["error"].string ?? "Something went wrong.") }
        case "ended":
            end("The room has ended.")
        default: break   // pong, and whatever a newer server adds
        }
    }

    /// Hot Dice: the phones wait for the big screen to show a roll. The iPad shows it, then says so.
    private func showDice(_ f: JSON) {
        guard game == .hotDice, let seq = Floor.rolling(f), seq != landedSent else { return }
        landedSent = seq
        let wait = UIAccessibility.isReduceMotionEnabled ? 0.4 : 1.3
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self, Floor.rolling(self.floor ?? .null) == seq else { return }
            self.send(Out.landed(seq: seq))
        }
    }

    func send(_ m: JSON) { sendRaw(Out.host(m, token: room.hostToken)) }
    private func sendRaw(_ m: JSON) { task?.send(.string(m.text)) { _ in } }

    func show(_ text: String) {
        toast = text; Haptics.nope()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in if self?.toast == text { self?.toast = nil } }
    }

    private func end(_ why: String) {
        status = .ended(why)
        stop()
    }

    /// Ends the room for everyone (the host's End room).
    func endRoom() { send(Out.close); DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.stop() } }

    func stop() {
        stopped = true
        pinger?.invalidate(); pinger = nil
        task?.cancel(with: .normalClosure, reason: nil); task = nil
        TVModel.shared.unhost()
    }
}

extension AppModel {
    /// Whether this device can host (the plan: an iPad runs the big screen; phones play).
    static var canHost: Bool { UIDevice.current.userInterfaceIdiom == .pad || ProcessInfo.processInfo.arguments.contains("-t2p-host") }
}
