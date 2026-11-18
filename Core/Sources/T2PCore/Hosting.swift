import Foundation

/// Hosting a room from an iPad (#537): a hosted room, the kind the website's game pages start. The iPad is the room's
/// big screen: it holds the host token (never shown, never saved), gets the floor (everyone's public view) on the
/// room's screen socket, and sends the host's messages with the token. Players join on their phones as they always
/// have. Nothing here is new to the server: these are the website's host pages' own paths and messages.
public struct HostedRoom: Equatable, Sendable {
    public var game: Game
    public var code: String
    public var hostToken: String
    public init(game: Game, code: String, hostToken: String) { self.game = game; self.code = code; self.hostToken = hostToken }
}

extension Endpoints {
    /// A hosted room: /live/<game>/new with no ?hostless, which answers with the code and the host token.
    public func newHostedRoom(_ g: Game) -> URL { base.appendingPathComponent("live/\(g.path)/new") }
    /// The host's own screen socket: ?as=screen&host=TOKEN (the website's host pages open the same).
    public func hostScreen(_ r: HostedRoom) -> URL {
        var c = URLComponents(url: socket(r.game, code: r.code), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "as", value: "screen"), URLQueryItem(name: "host", value: r.hostToken)]
        return c.url!
    }
}

extension API {
    /// Starts a hosted room for this device to run.
    public func startHostedRoom(_ g: Game) async throws -> HostedRoom {
        let j = try await call(endpoints.newHostedRoom(g))
        guard let code = j["code"].string.flatMap(RoomCode.normalize), let token = j["hostToken"].string, !token.isEmpty else {
            throw Failure(status: 0, message: "Couldn’t start a room to host. Try again.", code: nil)
        }
        return HostedRoom(game: g, code: code, hostToken: token)
    }
}

extension Out {
    /// A host message: the same as the owner's, with the host token the room checks.
    public static func host(_ m: JSON, token: String) -> JSON {
        guard case var .object(o) = m else { return m }
        o["hostToken"] = .string(token)
        return .object(o)
    }
    /// Hot Dice on a big screen: its dice have landed on roll seq, so the phones may see them.
    public static func landed(seq: Int) -> JSON { ["t": "landed", "seq": .number(Double(seq))] }
}

/// The floor as the host screen reads it: who's in the room, whichever game.
public struct FloorPlayer: Equatable, Sendable, Identifiable {
    public var id: String; public var name: String; public var face: Int; public var bot: String?; public var connected: Bool
    /// Cards in hand (Overdraft), or the score (the dice games and Close Enough).
    public var cards: Int?; public var score: Int?
    public var turn: Bool
}

public enum Floor {
    /// Everyone the floor lists, in seat order once a game is on.
    public static func players(_ f: JSON, game: Game) -> [FloorPlayer] {
        let turnId: String? = game == .overdraft ? f["tables"][0]["turn"].string : f["turn"]["id"].string
        let list: [JSON]
        if game == .overdraft {
            let seats = f["tables"].array.flatMap { $0["seats"].array }
            list = seats.isEmpty ? f["roster"].array : seats
        } else {
            list = f["players"].array.filter { $0["left"].bool != true }
        }
        return list.map {
            FloorPlayer(id: $0["id"].string ?? "", name: RoomPlayer.stripBot($0["name"].string ?? ""), face: $0["face"].int ?? 0,
                        bot: $0["bot"].string ?? ($0["name"].string?.hasSuffix(" (bot)") == true ? "bot" : nil),
                        connected: $0["connected"].bool ?? true, cards: $0["cards"].int,
                        score: game == .overdraft ? nil : ($0["score"].int ?? $0["total"].int ?? 0),
                        turn: turnId != nil && $0["id"].string == turnId)
        }
    }

    /// Hot Dice: the roll the floor is waiting on the big screen to show (its seq), if any.
    public static func rolling(_ f: JSON) -> Int? {
        f["turn"]["state"].string == "rolling" ? f["turn"]["seq"].int : nil
    }

    /// How many are watching (#534's spectators; 0 until the server sends it).
    public static func watching(_ f: JSON) -> Int { f["watching"].int ?? f["spectators"].int ?? 0 }
}
