import Foundation

/// The four games the app plays, all run by the server (one rules file each, on the website).
public enum Game: String, CaseIterable, Codable, Sendable, Identifiable {
    case overdraft
    case hotDice = "farkle"      // the app's name for the website's Farkle Live ("Farkle" is a trademark, #385)
    case rollCall = "rollcall"
    case closeEnough = "closeenough"

    public var id: String { rawValue }
    /// The path the server uses: /live/<path>/new, /live/<path>/<CODE>.
    public var path: String { rawValue }
    public var title: String {
        switch self {
        case .overdraft: return "Overdraft"
        case .hotDice: return "Hot Dice"
        case .rollCall: return "Roll Call"
        case .closeEnough: return "Close Enough"
        }
    }
    /// One line on how it plays (Start cards, the Library's app games, the widget before the Library loads).
    public var blurb: String {
        switch self {
        case .overdraft: return "Match the suit or the number, and be first to empty your hand."
        case .hotDice: return "Roll six dice, keep what scores, and know when to bank."
        case .rollCall: return "Five dice, three rolls, thirteen boxes to fill."
        case .closeEnough: return "Give a range that holds the answer. Tighter scores more."
        }
    }
    /// The game the room's hello names (src/live/protocol.js): the same strings as the paths.
    public init?(serverName: String) { self.init(rawValue: serverName) }
}

/// Where the server is. The app talks to tyleralocke.com's live paths (the public site makes no outside requests;
/// the app is the one calling) and shares invite links on time2play.live.
public struct Endpoints: Equatable, Sendable {
    public var base: URL
    public var joinSite: URL

    public static let live = Endpoints(base: URL(string: "https://tyleralocke.com")!, joinSite: URL(string: "https://time2play.live")!)

    public init(base: URL, joinSite: URL) { self.base = base; self.joinSite = joinSite }

    public func newRoom(_ g: Game) -> URL { base.appendingPathComponent("live/\(g.path)/new").adding(query: "hostless", "1") }
    public func exists(_ g: Game, code: String) -> URL { base.appendingPathComponent("live/\(g.path)/\(code)/exists") }
    public func socket(_ g: Game, code: String) -> URL {
        var c = URLComponents(url: base.appendingPathComponent("live/\(g.path)/\(code)"), resolvingAgainstBaseURL: false)!
        c.scheme = c.scheme == "http" ? "ws" : "wss"
        return c.url!
    }
    /// The TV's view of a hostless room (no powers): opened in a browser or drawn by the app on an external display.
    public func screen(_ g: Game, code: String) -> URL {
        var c = URLComponents(url: socket(g, code: code), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "as", value: "screen")]
        return c.url!
    }
    public func leave(_ g: Game, code: String) -> URL { base.appendingPathComponent("live/\(g.path)/\(code)/leave") }
    /// What a room's QR code and Share hold: time2play.live/K7QP.
    public func invite(code: String) -> URL { joinSite.appendingPathComponent(code) }
    public func api(_ path: String) -> URL { base.appendingPathComponent(path) }
}

extension URL {
    func adding(query name: String, _ value: String) -> URL {
        var c = URLComponents(url: self, resolvingAgainstBaseURL: false)!
        c.queryItems = (c.queryItems ?? []) + [URLQueryItem(name: name, value: value)]
        return c.url!
    }
}
