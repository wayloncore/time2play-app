import Foundation

/// A player account (#394): as little as possible. Saved data: add fields, never rename or remove.
public struct Account: Codable, Equatable, Sendable, Identifiable {
    public var id: String; public var name: String; public var face: Int; public var created: Double?
    public init(id: String, name: String, face: Int, created: Double? = nil) { self.id = id; self.name = name; self.face = face; self.created = created }
    init?(_ j: JSON) {
        guard let id = j["id"].string, let name = j["name"].string else { return nil }
        self.init(id: id, name: name, face: j["face"].int ?? 0, created: j["created"].double)
    }
}

/// Someone in a friends list, a request or a group: an account's public card.
public struct PlayerCard: Equatable, Sendable, Identifiable, Hashable {
    public var id: String; public var name: String; public var face: Int
    init?(_ j: JSON) { guard let id = j["id"].string else { return nil }; self.id = id; name = j["name"].string ?? ""; face = j["face"].int ?? 0 }
    public init(id: String, name: String, face: Int) { self.id = id; self.name = name; self.face = face }
}

public struct Friends: Equatable, Sendable {
    public var friends: [PlayerCard] = []; public var incoming: [PlayerCard] = []
    public var outgoing: [PlayerCard] = []; public var recent: [PlayerCard] = []
    public init() {}
    init(_ j: JSON) {
        friends = j["friends"].array.compactMap(PlayerCard.init); incoming = j["incoming"].array.compactMap(PlayerCard.init)
        outgoing = j["outgoing"].array.compactMap(PlayerCard.init); recent = j["recent"].array.compactMap(PlayerCard.init)
    }
}

public struct PlayerGroup: Equatable, Sendable, Identifiable {
    public var id: String; public var name: String; public var mine: Bool; public var members: [PlayerCard]
    init?(_ j: JSON) {
        guard let id = j["id"].string else { return nil }
        self.id = id; name = j["name"].string ?? ""; mine = j["mine"].bool ?? false; members = j["members"].array.compactMap(PlayerCard.init)
    }
}

/// A challenge: a ready-made room and an invite to it (#396). Lasts 2 hours.
public struct Challenge: Equatable, Sendable, Identifiable {
    public var id: String; public var from: PlayerCard; public var game: Game?; public var room: String; public var created: Double
    init?(_ j: JSON) {
        guard let id = j["id"].string, let from = PlayerCard(j["from"]), let room = j["room"].string else { return nil }
        self.id = id; self.from = from; game = j["game"].string.flatMap(Game.init(rawValue:)); self.room = room; created = j["created"].double ?? 0
    }
}

/// Who's asking: a session from Sign in with Apple (or App Review's sign-in), kept in the Keychain by the app.
public struct SignedIn: Equatable, Sendable { public var account: Account; public var token: String; public var expires: Double? }

/// The accounts paths (/live/players/, tyleralocke.com only). Every call but sign-in carries the session in a header.
extension API {
    private func players(_ path: String, _ body: JSON? = nil, method: String? = nil) async throws -> JSON {
        try await call(endpoints.api("live/players/\(path)"), method: method ?? (body == nil ? "GET" : "POST"), body: body, auth: true)
    }

    private func signedIn(_ j: JSON) throws -> SignedIn {
        guard let a = Account(j["account"]), let t = j["token"].string else { throw Failure(status: 0, message: "Couldn’t sign in. Try again.", code: nil) }
        return SignedIn(account: a, token: t, expires: j["expires"].double)
    }

    /// Sign in with Apple: Apple's identity token, checked by the server. A new account takes this name and face, and
    /// only if the person said they're 13 or older (nothing else about their age is sent or kept).
    public func signInWithApple(identityToken: String, name: String, face: Int, over13: Bool, app: String) async throws -> SignedIn {
        try signedIn(try await players("apple", ["identityToken": .string(identityToken), "name": .string(name), "face": .number(Double(face)),
                                                 "over13": .bool(over13), "app": .string(app)]))
    }

    /// App Review's sign-in (#403): the key from the review notes. Slot 2 is a second review account (for tests).
    public func signInForReview(key: String, slot: Int = 1, app: String) async throws -> SignedIn {
        try signedIn(try await players("review", ["key": .string(key), "slot": .number(Double(slot)), "app": .string(app)]))
    }

    public func me() async throws -> Account {
        guard let a = Account(try await players("me")["account"]) else { throw Failure(status: 0, message: "Sign in again.", code: "session") }
        return a
    }
    public func update(name: String?, face: Int?) async throws -> Account {
        var b: [String: JSON] = [:]
        if let n = name { b["name"] = .string(n) }
        if let f = face { b["face"] = .number(Double(f)) }
        guard let a = Account(try await players("me", .object(b))["account"]) else { throw Failure(status: 0, message: "Couldn’t save that.", code: nil) }
        return a
    }
    public func signOut() async throws { _ = try await players("signout", [:]) }
    /// Deletes the account and everything of it. A fresh Apple authorization code lets the server revoke Sign in with Apple.
    public func deleteAccount(authorizationCode: String?) async throws {
        _ = try await players("delete", authorizationCode.map { ["authorizationCode": .string($0)] } ?? [:])
    }

    public func friends() async throws -> Friends { Friends(try await players("friends")) }
    @discardableResult public func requestFriend(_ id: String) async throws -> Bool { try await players("friends/request", ["account": .string(id)])["friends"].bool ?? false }
    public func acceptFriend(_ id: String) async throws { _ = try await players("friends/accept", ["account": .string(id)]) }
    public func declineFriend(_ id: String) async throws { _ = try await players("friends/decline", ["account": .string(id)]) }
    public func removeFriend(_ id: String) async throws { _ = try await players("friends/remove", ["account": .string(id)]) }
    /// Your friend link's code (7 days): time2play.live/f/CODE.
    public func friendLink() async throws -> String { try await players("friends/link", [:])["code"].string ?? "" }
    /// Opens a friend or group link: "friend" or "group", and the name.
    public func openLink(_ code: String) async throws -> (kind: String, name: String) {
        let j = try await players("links/open", ["code": .string(code)])
        if let f = PlayerCard(j["friend"]) { return ("friend", f.name) }
        return ("group", j["group"]["name"].string ?? "")
    }

    public func groups() async throws -> [PlayerGroup] { try await players("groups")["groups"].array.compactMap(PlayerGroup.init) }
    public func createGroup(name: String, members: [String]) async throws {
        _ = try await players("groups/create", ["name": .string(name), "members": .array(members.map { .string($0) })])
    }
    public func groupLink(_ group: String) async throws -> String { try await players("groups/link", ["group": .string(group)])["code"].string ?? "" }
    public func leaveGroup(_ group: String) async throws { _ = try await players("groups/leave", ["group": .string(group)]) }

    public func challenges() async throws -> [Challenge] { try await players("challenges")["challenges"].array.compactMap(Challenge.init) }
    /// Invites friends (or a group) to a room you've started. Only Overdraft and Hot Dice rooms for now (the server's list).
    public func sendChallenge(game: Game, room: String, to: [String] = [], group: String? = nil) async throws {
        var b: [String: JSON] = ["game": .string(game.rawValue), "room": .string(room), "to": .array(to.map { .string($0) })]
        if let g = group { b["group"] = .string(g) }
        _ = try await players("challenges/send", .object(b))
    }
    public func dismissChallenge(_ id: String) async throws { _ = try await players("challenges/dismiss", ["challenge": .string(id)]) }

    /// Report a name (from any player list; guests can too). why: "name" or "behavior". No free text.
    public func report(name: String, why: String, account: String? = nil, room: String? = nil) async throws {
        var b: [String: JSON] = ["name": .string(name), "why": .string(why)]
        if let a = account { b["account"] = .string(a) }
        if let r = room { b["room"] = .string(r) }
        _ = try await players("report", .object(b))
    }
    public func block(_ id: String) async throws { _ = try await players("block", ["account": .string(id)]) }
    public func unblock(_ id: String) async throws { _ = try await players("unblock", ["account": .string(id)]) }

    /// This device's push token, for invite alerts (#404). sandbox: a test build. turn: "Alerts for my turn" is on
    /// (wayloncore/tyleralocke#534; added, so a server from before it just ignores the field).
    public func registerPush(device: String, sandbox: Bool, turn: Bool? = nil) async throws {
        var body: [String: JSON] = ["device": .string(device), "sandbox": .bool(sandbox)]
        if let t = turn { body["turn"] = .bool(t) }
        _ = try await players("push", .object(body))
    }
}

/// The games a challenge can be for (the server's list, social.js GAMES).
public extension Game { var challengeable: Bool { self == .overdraft || self == .hotDice } }

/// A friend or group link: time2play.live/f/CODE (8 letters and numbers).
public enum FriendLink {
    public static func code(_ url: URL) -> String? {
        let parts = url.pathComponents.filter { $0 != "/" }
        let isOurs = (url.host ?? "").hasSuffix("time2play.live") || url.scheme == "time2play"
        guard isOurs, let i = parts.firstIndex(of: "f"), i + 1 < parts.count else {
            if url.scheme == "time2play", url.host == "f", let c = parts.first, c.count == 8 { return c.uppercased() }
            return nil
        }
        let c = parts[i + 1].uppercased()
        return c.count == 8 && c.allSatisfy({ $0.isLetter || $0.isNumber }) ? c : nil
    }
    public static func url(_ code: String) -> URL { URL(string: "https://time2play.live/f/\(code)")! }
}
