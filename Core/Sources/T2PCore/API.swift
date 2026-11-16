import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The server's plain HTTP answers (starting rooms, finding a code's game, the Library, accounts). One method does
/// the network, so tests swap it for canned answers.
public final class API: @unchecked Sendable {
    public typealias Fetch = @Sendable (URLRequest) async throws -> (Int, Data)
    public let endpoints: Endpoints
    private let fetch: Fetch
    /// The signed-in session, sent as `Authorization: Bearer …` to the accounts paths only.
    public var session: String?
    /// "ios 1.0": the app version an account was last seen with.
    public var appVersion: String?

    public init(endpoints: Endpoints = .live, fetch: Fetch? = nil) {
        self.endpoints = endpoints
        self.fetch = fetch ?? { req in
            let (d, r) = try await URLSession.shared.data(for: req)
            return ((r as? HTTPURLResponse)?.statusCode ?? 0, d)
        }
    }

    public struct Failure: Error, Equatable, CustomStringConvertible {
        public var status: Int; public var message: String; public var code: String?
        public var description: String { message }
        public init(status: Int, message: String, code: String?) { self.status = status; self.message = message; self.code = code }
    }

    /// GET or POST a path; JSON back. A non-2xx answer throws with the server's own words when it gave some.
    public func call(_ url: URL, method: String = "GET", body: JSON? = nil, auth: Bool = false) async throws -> JSON {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "accept")
        if let b = body { req.httpBody = Data(b.text.utf8); req.setValue("application/json", forHTTPHeaderField: "content-type") }
        if auth, let s = session { req.setValue("Bearer \(s)", forHTTPHeaderField: "authorization") }
        if let a = appVersion { req.setValue(a, forHTTPHeaderField: "x-t2p-app") }
        let (status, data) = try await fetch(req)
        let j = JSON.parse(data) ?? .null
        guard (200..<300).contains(status) else {
            throw Failure(status: status, message: j["error"].string ?? API.plain(status), code: j["code"].string)
        }
        return j
    }

    static func plain(_ status: Int) -> String {
        switch status {
        case 0: return "No connection. Check your signal and try again."
        case 404: return "That isn’t there."
        case 429: return "This network has opened a lot of rooms this hour. Try again later."
        default: return "Something went wrong (\(status)). Try again."
        }
    }

    // MARK: rooms

    /// Starts a room with no host screen: you'll own it once you join.
    public func startRoom(_ g: Game) async throws -> String {
        let j = try await call(endpoints.newRoom(g))
        guard let code = j["code"].string, let c = RoomCode.normalize(code) else {
            throw Failure(status: 0, message: "Couldn’t start a room. Try again.", code: nil)
        }
        return c
    }

    public struct Found: Equatable, Sendable {
        public var game: Game?        // nil: a room of a game the app doesn't have (it opens on the website)
        public var code: String
        public var phase: String
        public var players: Int
        public var taken: [Int]
    }

    /// Which game a code is, asking each game's room (the same rooms answer for all four; only the right one is in use).
    public func find(code: String) async throws -> Found? {
        let found = try await withThrowingTaskGroup(of: Found?.self) { group -> [Found] in
            for g in Game.allCases {
                group.addTask {
                    let j = try await self.call(self.endpoints.exists(g, code: code))
                    guard j["inUse"].bool == true, j["ended"].bool != true else { return nil }
                    return Found(game: g, code: code, phase: j["phase"].string ?? "lobby", players: j["players"].int ?? 0,
                                 taken: j["taken"].array.compactMap(\.int))
                }
            }
            group.addTask {
                // the website's other live games (a trivia board, Jeopardy Live…): not in the app, so they open on the web
                guard let j = try? await self.call(self.endpoints.api("live/room/\(code)/exists")),
                      j["exists"].bool == true || j["inUse"].bool == true else { return nil }
                return Found(game: nil, code: code, phase: "", players: 0, taken: [])
            }
            var out: [Found] = []
            for try await f in group { if let f { out.append(f) } }
            return out
        }
        return found.first { $0.game != nil } ?? found.first
    }

    /// The faces taken in a room right now, for the picker.
    public func taken(_ g: Game, code: String) async -> [Int] {
        (try? await call(endpoints.exists(g, code: code)))?["taken"].array.compactMap(\.int) ?? []
    }
}
