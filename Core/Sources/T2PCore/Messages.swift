import Foundation

/// The protocol version this build speaks. The server only ever adds; it never changes an existing message.
public let protocolVersion = 1

/// A room code as players type it: 4 characters, no lookalikes.
public enum RoomCode {
    public static let alphabet = Set("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    /// Upper-cases, drops spaces and dashes, and returns nil unless it's 4 allowed characters.
    public static func normalize(_ raw: String) -> String? {
        let cleaned = raw.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        guard cleaned.count == 4, cleaned.allSatisfy({ alphabet.contains($0) }) else { return nil }
        return cleaned
    }

    /// Reads a code out of a join link such as https://time2play.live/ABCD.
    public static func fromLink(_ url: URL) -> String? {
        guard let host = url.host, host == "time2play.live" || host == "www.time2play.live" else { return nil }
        return normalize(url.lastPathComponent)
    }
}

/// A message from the phone to the server. Encoded with a `t` field, as the website's phones do today.
public enum ClientMessage: Equatable {
    case hello(version: Int, app: String)
    case join(name: String, face: String)
    case play(card: String)
}

extension ClientMessage: Encodable {
    private enum Keys: String, CodingKey { case t, v, app, name, face, card }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case let .hello(version, app):
            try c.encode("hello", forKey: .t); try c.encode(version, forKey: .v); try c.encode(app, forKey: .app)
        case let .join(name, face):
            try c.encode("join", forKey: .t); try c.encode(name, forKey: .name); try c.encode(face, forKey: .face)
        case let .play(card):
            try c.encode("play", forKey: .t); try c.encode(card, forKey: .card)
        }
    }
}

/// A message from the server. Unknown types decode as `.unknown` instead of failing, so a new server never breaks an
/// old app.
public enum ServerMessage: Equatable {
    case welcome(minVersion: Int)
    case pleaseUpdate
    case unknown(String)
}

extension ServerMessage: Decodable {
    private enum Keys: String, CodingKey { case t, min }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let t = try c.decode(String.self, forKey: .t)
        switch t {
        case "welcome":
            let min = try c.decodeIfPresent(Int.self, forKey: .min) ?? 1
            self = min > protocolVersion ? .pleaseUpdate : .welcome(minVersion: min)
        default:
            self = .unknown(t)
        }
    }
}
