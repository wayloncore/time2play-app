import Foundation
#if canImport(JavaScriptCore)
import JavaScriptCore

/// The website's own room cores (rules and bots), bundled at build time (scripts/rules-bundle.mjs) and run in
/// JavaScriptCore, so bots can be played with no signal (#402). Offline games are practice: nothing reaches the server
/// and nothing counts.
public final class OfflineRules {
    private let ctx: JSContext
    private let api: JSValue

    /// The bundled rules, or nil if they can't be loaded.
    public static func load() -> OfflineRules? {
        guard let url = Bundle.module.url(forResource: "rules", withExtension: "js"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return OfflineRules(script: text)
    }

    init?(script: String) {
        guard let c = JSContext() else { return nil }
        var failed = false
        c.exceptionHandler = { _, e in failed = true; print("T2P offline rules:", e?.toString() ?? "?") }
        c.evaluateScript(script)
        guard !failed, let a = c.objectForKeyedSubscript("T2POffline"), !a.isUndefined else { return nil }
        ctx = c; api = a
    }

    func open(_ game: Game, seed: UInt32, now: Double) -> Int { Int(api.invokeMethod("open", withArguments: [game.rawValue, seed, now]).toInt32()) }
    func send(_ room: Int, _ text: String, now: Double) -> String { api.invokeMethod("send", withArguments: [room, text, now]).toString() }
    func tick(_ room: Int, now: Double) -> String { api.invokeMethod("tick", withArguments: [room, now]).toString() }
    func next(_ room: Int) -> Double { api.invokeMethod("next", withArguments: [room]).toDouble() }
    func close(_ room: Int) { api.invokeMethod("close", withArguments: [room]) }

    /// Hot Dice (#488): which faces in a roll can score, by the website's own scoring (its phone dims the rest).
    public func scoringFaces(_ values: [Int], ones: Int) -> Set<Int> {
        let text = api.invokeMethod("scoring", withArguments: ["[" + values.map(String.init).joined(separator: ",") + "]", ones]).toString() ?? "[]"
        return Set(JSON.parse(text)?.array.compactMap(\.int) ?? [])
    }

    /// One seeded game played start to end, as the parity check compares it with Node's.
    public func parity(_ game: String, seed: Int) -> JSON? { JSON.parse(api.invokeMethod("parity", withArguments: [game, seed]).toString()) }
}

/// A room with no server: the RoomSession talks to it exactly as to a socket, so every screen works the same offline.
public final class OfflineTransport: RoomTransport {
    public let rules: OfflineRules
    public let game: Game
    private let seed: UInt32
    private var room: Int?
    private var onEvent: ((TransportEvent) -> Void)?
    private var generation = 0
    /// When to run the room's clock next (bots' turns, reveals). The app uses the main queue; tests run it at once.
    public var schedule: (TimeInterval, @escaping () -> Void) -> Void = { d, f in DispatchQueue.main.asyncAfter(deadline: .now() + d, execute: f) }
    /// The room's clock, in ms. Tests move it by hand.
    public var now: () -> Double = { Date().timeIntervalSince1970 * 1000 }

    public init(rules: OfflineRules, game: Game, seed: UInt32 = .random(in: 1...UInt32.max)) {
        self.rules = rules; self.game = game; self.seed = seed
    }

    public func open(_ url: URL, onEvent: @escaping (TransportEvent) -> Void) {
        self.onEvent = onEvent
        if room == nil { room = rules.open(game, seed: seed, now: now()) }
        onEvent(.opened)
    }

    public func send(_ text: String) {
        guard let r = room else { return }
        deliver(rules.send(r, text, now: now()))
        arm()
    }

    public func close() {
        // the offline room lives as long as this transport: closing the "socket" only stops the clock
        generation += 1
    }

    /// Runs the clock up to now (tests call this after moving `now`).
    public func runClock() {
        guard let r = room else { return }
        deliver(rules.tick(r, now: now()))
        arm()
    }

    private func arm() {
        guard let r = room else { return }
        let next = rules.next(r)
        guard next > 0 else { return }
        let gen = generation
        schedule(max(0.05, (next - now()) / 1000)) { [weak self] in
            guard let self, gen == self.generation else { return }
            self.runClock()
        }
    }

    private func deliver(_ text: String) {
        for m in JSON.parse(text)?.array ?? [] {
            onEvent?(.text(m.text))
            if m["t"].string == "ended" { generation += 1; onEvent?(.closed(code: 4005)) }
        }
    }

    deinit { if let r = room { rules.close(r) } }
}
#endif
