import SwiftUI
import T2PCore

/// One room on screen: the session (Core), the socket, and what the screens draw from them.
@MainActor
final class RoomModel: ObservableObject, Identifiable {
    let id = UUID()
    let game: Game
    let code: String
    let starting: Bool
    /// An offline room (#402): the server's own rules and bots, run on this phone. Practice; nothing counts.
    let offline: Bool
    private let session: RoomSession
    private let transport: RoomTransport
    private weak var app: AppModel?
    private var retry: DispatchWorkItem?
    private var recorded = false

    @Published private(set) var status: RoomSession.Status = .connecting
    @Published private(set) var view: JSON?
    @Published var taken: [Int]
    /// A short line at the top of the room (a problem, a saved preset, an achievement). Every one goes away on its own
    /// after about 3 seconds (Tyler, build 48: an achievement's never did), and a tap or a swipe up clears it sooner.
    @Published var toast: String? { didSet { if toast != nil && toast != oldValue { toastEnds() } } }
    private var toastTimer: DispatchWorkItem?
    static let toastSeconds = 3.0
    @Published var reactions: [ShownReaction] = []
    @Published var back: String?
    /// #538: a preset to set this room up with, once its owner is in the lobby
    var preset: Preset? { didSet { if preset != nil { applyPreset() } } }

    struct ShownReaction: Identifiable, Equatable { let id = UUID(); let who: String; let words: String }

    init(game: Game, code: String, app: AppModel, taken: [Int], starting: Bool, offline: OfflineRules? = nil, session account: String? = nil) {
        self.game = game; self.code = code; self.app = app; self.taken = taken; self.starting = starting
        self.offline = offline != nil
        if let rules = offline {
            transport = app.offlineSeed.map { OfflineTransport(rules: rules, game: game, seed: $0) } ?? OfflineTransport(rules: rules, game: game)
            session = RoomSession(game: game, code: code, endpoints: app.endpoints, appVersion: AppModel.appVersion,
                                  transport: transport, store: MemorySeatStore())
        } else {
            transport = WebSocketTransport()
            // a signed-in player's session goes in the room's first message (never the address): their seat carries
            // their account, so the people they played with can become friends afterwards
            session = RoomSession(game: game, code: code, endpoints: app.endpoints, appVersion: AppModel.appVersion,
                                  sessionToken: account, transport: transport, store: app.seats)
        }
        // the UI test for "Please update" says it speaks a protocol older than the server's oldest
        if ProcessInfo.processInfo.arguments.contains("-t2p-old-protocol") { session.helloVersion = 0 }
        session.onChange = { [weak self] in self?.sync() }
        session.onNotice = { [weak self] n in self?.notice(n) }
    }

    var seat: Seat? { session.seat }
    /// #539: the room takes watchers (its /exists said so), and whether this phone is one.
    var canWatch = false
    var watching: Bool { session.watching }
    func watch(name: String?) { session.watch(name: name) }
    var hasSeat: Bool { session.seat != nil }

    func start() {
        // a name and face already picked: join as soon as the socket is open (a resume wins if there's a seat)
        if session.seat == nil, let p = app?.profile, p.name.count >= 2, starting {
            session.join(name: p.name, face: p.face)
        }
        session.start()
        Music.shared.start()   // only when You → Music is on
    }

    func join(name: String, face: Int?) { session.join(name: name, face: face) }

    private func toastEnds() {
        toastTimer?.cancel()
        let shown = toast
        let w = DispatchWorkItem { [weak self] in if let self, self.toast == shown { self.toast = nil } }
        toastTimer = w
        DispatchQueue.main.asyncAfter(deadline: .now() + RoomModel.toastSeconds, execute: w)
    }
    /// A tap or a swipe up on the line at the top.
    func dismissToast() { toastTimer?.cancel(); toast = nil }

    /// UI tests' debug line: what the room last refused, and an offline room's clock.
    private(set) var lastProblem: (String, Date)?
    var debugLine: String {
        let ago = { (d: Date) in String(format: "%.1fs ago", Date().timeIntervalSince(d)) }
        var parts = ["refused=\(lastProblem.map { "\($0.0) \(ago($0.1))" } ?? "-")"]
        if let o = transport as? OfflineTransport {
            let now = Date().timeIntervalSince1970 * 1000
            parts.append(String(format: "clock runs=%d last=%.1fs ago next=%@ sends=%d last=%@", o.clockRuns, (now - o.lastRun) / 1000,
                                o.nextAt > 0 ? String(format: "in %.1fs", (o.nextAt - now) / 1000) : "none", o.sends, o.lastSent))
        }
        parts.append(HangWatch.shared.line)
        return parts.joined(separator: " ")
    }
    func send(_ m: JSON) { session.send(m) }
    func move(_ t: String, _ fields: [String: JSON] = [:]) { session.move(t, fields) }
    /// The website's own Farkle scoring, for marking the dice that can score (#488).
    var rules: OfflineRules? { app?.offlineRules }

    func react(_ r: Reaction) { session.send(Out.react(r)); Haptics.select() }

    func pause() { if offline { return }; retry?.cancel(); session.pause() }
    func resume() { Music.shared.resumeIfStopped(); if offline { return }; retry?.cancel(); session.reconnect() }
    func leave() { retry?.cancel(); session.leave() }
    func close() { retry?.cancel(); transport.close(); Music.shared.stop() }

    private func sync() {
        status = session.status
        let before = view
        view = session.view
        if preset != nil { applyPreset() }
        StatsKeeper.shared.observe(self)   // #540: a finished game, recorded once
        // the game's feel (sounds, the Bolt's jolt): what this view means next to the one before it
        if let now = view, now != before { Feel.events(FeelEvents.between(before, now, game: game)) }
        // a room you're in goes on Play's recent rooms (and the widget's rejoin); practice rooms don't
        if !offline, !recorded, case .inRoom = status { recorded = true; app?.remember(code: code, game: game) }
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
            lastProblem = (msg, Date())
            toast = msg; Haptics.nope()   // it goes on its own (toastEnds)
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

/// UI tests only (-t2p-arena-debug): the longest the main thread went without answering, checked five times a second.
final class HangWatch: @unchecked Sendable {
    static let shared = HangWatch()
    private let lock = NSLock()
    private var worst = 0.0, worstAt = Date.distantPast, over = 0, started = false
    func start() {
        lock.lock(); defer { lock.unlock() }
        guard !started else { return }
        started = true
        Thread.detachNewThread { [self] in
            while true {
                let sent = Date(), sem = DispatchSemaphore(value: 0)
                DispatchQueue.main.async { sem.signal() }
                sem.wait()
                let lag = Date().timeIntervalSince(sent)
                lock.lock()
                if lag > 0.5 { over += 1 }
                if lag > worst { worst = lag; worstAt = Date() }
                lock.unlock()
                Thread.sleep(forTimeInterval: 0.2)
            }
        }
    }
    var line: String {
        lock.lock(); defer { lock.unlock() }
        return started ? String(format: "mainHang max=%.1fs (%.0fs ago) over0.5s=%d", worst, Date().timeIntervalSince(worstAt), over) : ""
    }
}
