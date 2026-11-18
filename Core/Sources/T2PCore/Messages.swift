import Foundation

/// The protocol version this build speaks (the website's src/live/protocol.js). The server only ever adds; it never
/// changes an existing message, so a newer server never breaks this app, and the app ignores what it doesn't know.
public let protocolVersion = 1

/// A room code as players type it: 4 characters, no lookalikes (no I, O, 0 or 1).
public enum RoomCode {
    public static let alphabet = Set("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    public static let length = 4

    /// Upper-cases, drops spaces and dashes, and returns nil unless it's 4 allowed characters.
    public static func normalize(_ raw: String) -> String? {
        let cleaned = raw.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        guard cleaned.count == length, cleaned.allSatisfy({ alphabet.contains($0) }) else { return nil }
        return cleaned
    }

    /// What's typed so far, kept to allowed characters and at most 4 (the code boxes on Play).
    public static func partial(_ raw: String) -> String {
        String(raw.uppercased().filter { alphabet.contains($0) }.prefix(length))
    }

    /// Reads a code out of a join link or a room's QR: https://time2play.live/K7QP, time2play.live/?room=K7QP,
    /// the website's player pages (…?room=K7QP), or a bare code.
    public static func fromLink(_ url: URL) -> String? {
        if url.scheme == nil, url.host == nil { return normalize(url.absoluteString) }
        // the app's own scheme: time2play://join/K7QP (a notification or a test opens it)
        if url.scheme == "time2play" {
            return url.host == "join" ? normalize(url.lastPathComponent) : nil
        }
        guard let host = url.host?.lowercased() else { return nil }
        let ours = ["time2play.live", "www.time2play.live", "tyleralocke.com", "www.tyleralocke.com"]
        guard ours.contains(host) else { return nil }
        if let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            for name in ["room", "code", "watch"] { if let v = q.first(where: { $0.name == name })?.value, let c = normalize(v) { return c } }
        }
        if host.hasSuffix("time2play.live") { return normalize(url.lastPathComponent) }
        // the website's own join paths, which send phones to time2play.live: tyleralocke.com/j/K7QP, /join/K7QP
        let parts = url.pathComponents.filter { $0 != "/" }
        if parts.count == 2, ["j", "join"].contains(parts[0].lowercased()) { return normalize(parts[1]) }
        return nil
    }

    /// A scanned QR's text (a link, or a code on its own).
    public static func fromScan(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let c = normalize(t) { return c }
        if let u = URL(string: t), let c = fromLink(u) { return c }
        if let u = URL(string: "https://" + t), let c = fromLink(u) { return c }
        return nil
    }
}

/// What the phone sends. Every message is a JSON object with a `t` field, as the website's phones send them.
public enum Out {
    public static func hello(app: String, session: String? = nil, v: Int = protocolVersion) -> JSON {
        var o: [String: JSON] = ["t": "hello", "v": .number(Double(v)), "app": .string(app)]
        if let s = session { o["session"] = .string(s) }
        return .object(o)
    }
    public static func join(name: String, face: Int?) -> JSON {
        var o: [String: JSON] = ["t": "join", "name": .string(name)]
        if let f = face { o["face"] = .number(Double(f)) }
        return .object(o)
    }
    public static func resume(id: String, token: String) -> JSON { ["t": "resume", "id": .string(id), "token": .string(token)] }
    public static func leave(id: String, token: String) -> JSON { ["t": "leave", "id": .string(id), "token": .string(token)] }
    public static func react(_ r: Reaction) -> JSON { ["t": "react", "r": .string(r.rawValue)] }
    public static let ping: JSON = ["t": "ping"]
    public static let pingFresh: JSON = ["t": "ping", "fresh": true]

    // The room owner's (hostless rooms: no host token; the room checks it's the owner's own socket)
    public static func addBot(level: String) -> JSON { ["t": "addbot", "level": .string(level)] }
    public static func remove(_ target: String) -> JSON { ["t": "remove", "target": .string(target)] }
    public static let deal: JSON = ["t": "deal"]
    public static let again: JSON = ["t": "again"]
    public static let close: JSON = ["t": "close"]
    public static func options(_ fields: [String: JSON]) -> JSON {
        var o = fields; o["t"] = "options"; return .object(o)
    }

    /// A move: the room checks the seat with id and token on every one.
    public static func move(_ t: String, _ fields: [String: JSON] = [:], seat: Seat) -> JSON {
        var o = fields; o["t"] = .string(t); o["id"] = .string(seat.id); o["token"] = .string(seat.token)
        return .object(o)
    }
}

/// The four preset reactions (src/live/reactions.js). No typed text anywhere.
public enum Reaction: String, CaseIterable, Sendable, Identifiable {
    case nice, oof, ha, gg
    public var id: String { rawValue }
    public var words: String {
        switch self { case .nice: return "Nice"; case .oof: return "Oof"; case .ha: return "Ha!"; case .gg: return "Good game" }
    }
}

/// A seat in a room: the id is public, the token proves it's yours.
public struct Seat: Codable, Equatable, Sendable {
    public var id: String
    public var token: String
    public var name: String
    public init(id: String, token: String, name: String) { self.id = id; self.token = token; self.name = name }
}

/// A message from the server. Types this app doesn't know decode as `.unknown`, never as a failure.
public enum ServerMessage: Equatable {
    case hello(v: Int, min: Int, game: String?, update: Bool, account: String?)
    case pong
    case joined(Seat)
    case resumed(id: String)
    case view(JSON)                       // "you": this phone's own view
    case floor(JSON)                      // a screen's (TV's) view
    case react(id: String, r: String)
    case error(message: String, code: String?)
    case moved
    case removed(why: String)
    case ended
    case unknown(String)

    public static func decode(_ text: String) -> ServerMessage? {
        guard let j = JSON.parse(text), let t = j["t"].string else { return nil }
        switch t {
        case "hello":
            let min = j["min"].int ?? 1
            return .hello(v: j["v"].int ?? 1, min: min, game: j["game"].string,
                          update: (j["update"].bool ?? false) || min > protocolVersion, account: j["account"].string)
        case "pong": return .pong
        case "joined": return .joined(Seat(id: j["id"].string ?? "", token: j["token"].string ?? "", name: j["name"].string ?? ""))
        case "resumed": return .resumed(id: j["id"].string ?? "")
        case "you": return .view(j)
        case "floor": return .floor(j)
        case "react": return .react(id: j["id"].string ?? "", r: j["r"].string ?? "")
        case "error": return .error(message: j["error"].string ?? "Something went wrong.", code: j["code"].string)
        case "moved": return .moved
        case "removed": return .removed(why: j["why"].string ?? "removed")
        case "ended": return .ended
        default: return .unknown(t)
        }
    }
}
