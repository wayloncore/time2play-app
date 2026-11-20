import Foundation

// The app's honest feedback (wayloncore/tyleralocke#594, parts 2 and 3) and the tip jar's products (#598). Nothing
// here leaves the phone by itself: a report goes only when the player taps Send, and the frame numbers are kept on
// this phone until then.

/// How smoothly the last game drew (#594): frames counted while a game is on screen, so a report can say "58 fps on
/// average, worst frame 140 ms". A pause (the app in the background) isn't a frame.
public struct FrameMeter: Equatable, Sendable {
    public private(set) var frames = 0
    public private(set) var seconds = 0.0
    /// The longest single frame, in seconds.
    public private(set) var worst = 0.0
    /// Frames that took more than half again as long as the screen's frame time (a stutter you can see).
    public private(set) var hitches = 0

    /// Longer than this between two frames is a pause, not a frame (the phone locked, the app switched away).
    public static let pause = 2.0

    public init() {}

    /// One frame took `interval` seconds; the screen's frame time was `expected` (1/60 s at 60 Hz).
    public mutating func add(_ interval: Double, expected: Double) {
        guard interval > 0, interval < Self.pause else { return }
        frames += 1
        seconds += interval
        worst = max(worst, interval)
        if interval > max(expected, 1.0 / 240) * 1.5 { hitches += 1 }
    }

    public var averageFPS: Double { seconds > 0 ? Double(frames) / seconds : 0 }

    /// What's kept for a report: only once the game has been on screen a few seconds.
    public func summary(game: String, at: Date = Date()) -> FrameSummary? {
        guard seconds >= 5, frames > 0 else { return nil }
        return FrameSummary(game: game, fps: Int(averageFPS.rounded()), worstMs: Int((worst * 1000).rounded()),
                            hitches: hitches, seconds: Int(seconds.rounded()), at: at)
    }
}

/// The last game's frame numbers, kept on this phone (UserDefaults "t2p.lastFrames"). Saved data: add fields, never
/// rename or remove them.
public struct FrameSummary: Codable, Equatable, Sendable {
    public var game: String
    public var fps: Int
    public var worstMs: Int
    public var hitches: Int
    public var seconds: Int
    public var at: Date

    public init(game: String, fps: Int, worstMs: Int, hitches: Int, seconds: Int, at: Date) {
        self.game = game; self.fps = fps; self.worstMs = worstMs; self.hitches = hitches; self.seconds = seconds; self.at = at
    }

    /// "10,000: 58 fps on average, worst frame 140 ms, 3 stutters in 4 min"
    public var line: String {
        let name = Game(rawValue: game)?.title ?? game
        let minutes = max(1, Int((Double(seconds) / 60).rounded()))
        let stutters = hitches == 1 ? "1 stutter" : "\(hitches) stutters"
        return "\(name): \(fps) fps on average, worst frame \(worstMs) ms, \(stutters) in \(minutes) min"
    }
}

/// "Something slow or broken? Send a report" (#594 part 2): what the player picked and wrote, and the phone's facts,
/// as the website's own report form takes them (POST /report on tyleralocke.com, src/lib/server/problems.js). It lands
/// on the studio's Problems page, and the morning digest files it as a to-do. No name, no account, no email.
public struct AppReport: Equatable, Sendable {
    public enum Choice: String, CaseIterable, Sendable, Identifiable {
        case slow, froze, looked, other
        public var id: String { rawValue }
        public var label: String {
            switch self {
            case .slow: return "Slow or laggy"
            case .froze: return "Froze or closed"
            case .looked: return "Something looked wrong"
            case .other: return "Something else"
            }
        }
    }

    public var choices: [Choice]
    public var words: String
    /// The phone's model identifier ("iPhone16,1"), its iOS version, the app's version and build.
    public var device: String
    public var system: String
    public var version: String
    public var build: String
    public var frames: FrameSummary?

    /// The website's limits (problems.js): 10 to 1,000 characters of text; words beyond this many are cut.
    public static let wordsMax = 600

    public init(choices: [Choice], words: String, device: String, system: String, version: String, build: String, frames: FrameSummary?) {
        self.choices = choices; self.words = words; self.device = device; self.system = system
        self.version = version; self.build = build; self.frames = frames
    }

    public var ready: Bool { !choices.isEmpty || !trimmedWords.isEmpty }
    private var trimmedWords: String { String(words.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.wordsMax)) }

    /// The phone's facts, as the sheet shows them before sending (exactly what goes).
    public var facts: [String] {
        var f = ["Device: \(device)", "iOS: \(system)", "App: \(version) (build \(build))"]
        f.append("Last game: " + (frames?.line ?? "none measured yet"))
        return f
    }

    /// The report's text. Numbers are kept apart by words, so the digest's phone-number filter leaves them alone.
    public var text: String {
        var lines = ["From the Time2Play app (You, Send a report)."]
        let picked = Choice.allCases.filter { choices.contains($0) }.map(\.label)
        if !picked.isEmpty { lines.append("What happened: " + picked.joined(separator: ", ")) }
        if !trimmedWords.isEmpty { lines.append("In their words: " + trimmedWords) }
        lines += facts
        return String(lines.joined(separator: "\n").prefix(1000))
    }

    /// The report's "page": where it came from (the digest keeps letters, numbers, - . / and _ only).
    public var page: String {
        let clean = { (s: String) in s.filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" } }
        return "/app/ios/\(clean(version))/\(clean(build))"
    }

    /// The JSON body: the form's own fields. `elapsed` is how long the sheet was open (the form refuses under 3 s);
    /// `website` is the form's hidden field, left empty as a person leaves it.
    public func body(elapsedMs: Int) -> JSON {
        ["text": .string(text), "page": .string(page), "elapsed": .number(Double(elapsedMs)), "website": .string("")]
    }

    /// The form takes a report only after it has been open this long.
    public static let minimumOpenMs = 3000
}

extension API {
    /// Sends a player's report to the website's report form (#594). Throws with the site's own words if it refuses.
    public func sendReport(_ r: AppReport, elapsedMs: Int) async throws {
        _ = try await call(endpoints.api("report"), method: "POST", body: r.body(elapsedMs: elapsedMs))
    }
}

/// Apple's own rating request (#594 part 3): after a finished game, at most once per app version (iOS also keeps it
/// to three a year, and may show nothing).
public enum ReviewAsk {
    public static let key = "t2p.reviewAsked"
    public static func shouldAsk(finishedGame: Bool, lastAskedVersion: String?, version: String) -> Bool {
        finishedGame && !version.isEmpty && lastAskedVersion != version
    }
}

/// The logo as a joined room opens (#596): it plays when you join someone's room (by code, link or invite), never
/// when you start your own, practice offline, or come back to a seat you already hold (a "your turn" alert, Recent
/// rooms), and never with You → "Logo when you join a room" off.
public enum JoinIntroPlan {
    public static func plays(on: Bool, starting: Bool, offline: Bool, returning: Bool) -> Bool {
        on && !starting && !offline && !returning
    }
}

/// The tip jar (#598): three consumable in-app purchases. They say thanks and unlock nothing.
public enum Tips {
    public struct Kind: Equatable, Sendable, Identifiable {
        public let id: String
        public let name: String
        public let price: String      // the price set in App Store Connect (US); the app shows StoreKit's own
        public let line: String
        public let symbol: String
    }
    public static let all: [Kind] = [
        Kind(id: "live.time2play.app.tip.small", name: "Tip", price: "1.99", line: "A coffee’s worth of thanks", symbol: "cup.and.saucer.fill"),
        Kind(id: "live.time2play.app.tip.big", name: "Big tip", price: "4.99", line: "A round of thanks for the table", symbol: "gift.fill"),
        Kind(id: "live.time2play.app.tip.huge", name: "Huge tip", price: "9.99", line: "Game night’s on you", symbol: "star.circle.fill"),
    ]
    public static var ids: [String] { all.map(\.id) }
    public static func kind(_ id: String) -> Kind? { all.first { $0.id == id } }

    /// Tips given on this phone (UserDefaults, a new key): more than 0 shows the Supporter star on You.
    public static let countKey = "t2p.supporter"
    /// You → hide the Supporter star (a new key; missing reads as shown).
    public static let hideStarKey = "t2p.supporterStarHidden"
}
