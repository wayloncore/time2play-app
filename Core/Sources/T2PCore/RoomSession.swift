import Foundation

/// The socket under a room, as the session needs it. The app's is URLSessionWebSocketTask; tests use a fake.
public protocol RoomTransport: AnyObject {
    /// Opens the socket. Events come back through `onEvent`, on the session's own queue.
    func open(_ url: URL, onEvent: @escaping (TransportEvent) -> Void)
    func send(_ text: String)
    func close()
}

public enum TransportEvent: Equatable {
    case opened
    case text(String)
    /// The socket closed. `code` is the WebSocket close code when there is one (4001 removed, 4002 moved, 4005 ended).
    case closed(code: Int?)
}

/// Seats this phone holds, by room code, so a dropped phone comes back to the same seat. Saved data: add fields only.
public protocol SeatStore: AnyObject {
    func seat(for code: String) -> SavedSeat?
    func save(_ seat: SavedSeat)
    func forget(code: String)
}

public struct SavedSeat: Codable, Equatable, Sendable {
    public var code: String
    public var game: String
    public var id: String
    public var token: String
    public var name: String
    public var savedAt: Date
    public init(code: String, game: Game, seat: Seat, savedAt: Date = Date()) {
        self.code = code; self.game = game.rawValue; self.id = seat.id; self.token = seat.token; self.name = seat.name; self.savedAt = savedAt
    }
    public var seat: Seat { Seat(id: id, token: token, name: name) }
}

public final class MemorySeatStore: SeatStore {
    private var seats: [String: SavedSeat] = [:]
    public init() {}
    public func seat(for code: String) -> SavedSeat? { seats[code] }
    public func save(_ seat: SavedSeat) { seats[seat.code] = seat }
    public func forget(code: String) { seats[code] = nil }
}

/// One phone in one room: hello, then join or resume, then views until the room ends. It reconnects by itself after a
/// drop (a lock, lost signal, switching apps) and comes back to the same seat. No UI and no timers of its own: the app
/// schedules `reconnect()` after `reconnectDelay`, so this runs and is tested the same on Linux.
public final class RoomSession {
    public enum Status: Equatable {
        case connecting
        /// The server no longer serves this app's protocol: "Please update".
        case needsUpdate
        /// Connected; waiting for a name and a face before joining.
        case choosing(problem: String?)
        case joining
        case inRoom
        /// Dropped; trying again. The seat is held by the room for 3 minutes, a bot playing for you.
        case reconnecting(attempt: Int)
        case ended(EndReason)
    }

    public enum EndReason: Equatable {
        case closedByOwner, removed, expired, left, moved, gone
        case refused(String)

        public var title: String {
            switch self {
            case .closedByOwner: return "The room has closed"
            case .removed: return "You were taken out of this room"
            case .expired: return "Your seat was given up"
            case .left: return "You left this game"
            case .moved: return "This seat is open somewhere else"
            case .gone: return "That room isn't there any more"
            case let .refused(why): return why
            }
        }
        public var detail: String {
            switch self {
            case .closedByOwner: return "The room’s owner ended it. Start a new room or join another."
            case .removed: return "The room’s owner removed you. You can join another room."
            case .expired: return "You were away for more than 3 minutes, so a bot finished for you."
            case .left: return "You can join another room any time."
            case .moved: return "You opened this seat on another screen, so it moved there."
            case .gone: return "Rooms close after 20 minutes with nobody in them."
            case .refused: return "Check the code, or start a room of your own."
            }
        }
    }

    public let game: Game
    public let code: String
    public let endpoints: Endpoints
    public let appVersion: String
    public var sessionToken: String?
    /// The protocol this phone says it speaks. Always `protocolVersion`, except in the UI test that makes the real
    /// server answer "Please update" (it does for anything below its oldest, 1).
    public var helloVersion = protocolVersion

    public private(set) var status: Status = .connecting
    public private(set) var seat: Seat?
    /// The last view the room sent this phone (`t: "you"`), as JSON; the game's own view type reads it.
    public private(set) var view: JSON?
    /// The account the room sees this phone as (nil: a guest).
    public private(set) var account: String?
    public private(set) var game_: String?
    /// #539: watching the room, with no seat (no hand, no turns).
    public private(set) var watching = false

    /// Called after anything changes (status, seat, view).
    public var onChange: (() -> Void)?
    /// One-off things to show: a reaction, an error toast, "You're back…".
    public var onNotice: ((Notice) -> Void)?

    public enum Notice: Equatable {
        case reaction(playerId: String, Reaction)
        case problem(String)
        case back(String)
    }

    private let transport: RoomTransport
    private let store: SeatStore
    private var wantJoin: (name: String, face: Int?)?
    private var wantWatch: String??
    private var open = false
    private var attempt = 0
    private var resuming = false
    private var handBefore: Set<String>?

    public init(game: Game, code: String, endpoints: Endpoints = .live, appVersion: String, sessionToken: String? = nil,
                transport: RoomTransport, store: SeatStore) {
        self.game = game; self.code = code; self.endpoints = endpoints; self.appVersion = appVersion
        self.sessionToken = sessionToken; self.transport = transport; self.store = store
        seat = store.seat(for: code).flatMap { $0.game == game.rawValue ? $0.seat : nil }
    }

    // MARK: what the app calls

    /// Opens the socket. With a seat saved for this code it resumes; else it joins once `join(name:face:)` is called.
    public func start() { connect() }

    /// Joins as a guest (or the signed-in account) with this name and face.
    public func join(name: String, face: Int?) {
        wantJoin = (name, face)
        if open, seat == nil { status = .joining; send(Out.join(name: name, face: face)); changed() }
    }

    /// Watches the room without playing (#539): no seat, no hand, no turns. Comes back as a watcher after a drop.
    public func watch(name: String?) {
        wantWatch = .some(name); watching = true
        if open, seat == nil { status = .joining; send(Out.watch(name: name)); changed() }
    }

    /// The app went to the background: close the socket. The room holds the seat; `resume()` comes back to it.
    public func pause() {
        guard open || status == .connecting else { return }
        snapshotHand()
        open = false
        transport.close()
        if case .ended = status { return }
        status = .reconnecting(attempt: 0)
        changed()
    }

    /// Back in the foreground, or after `reconnectDelay`: open again and resume the seat.
    public func reconnect() {
        if case .ended = status { return }
        if case .needsUpdate = status { return }
        if open { return }
        connect()
    }

    /// How long to wait before the next try after a drop: 0.5 s, then doubling to 15 s at most.
    public var reconnectDelay: TimeInterval { min(15, 0.5 * pow(2, Double(max(0, attempt - 1)))) }

    /// Leave for good (not a drop). Mid-hand a bot takes the seat; in the lobby the seat goes.
    public func leave() {
        if let s = seat, open { send(Out.leave(id: s.id, token: s.token)) }
        store.forget(code: code)
        seat = nil
        open = false
        transport.close()
        status = .ended(.left)
        changed()
    }

    /// Sends anything the room takes (a move, an owner's message, a reaction).
    public func send(_ message: JSON) {
        guard open else { return }
        transport.send(message.text)
    }

    /// A move, with this seat's id and token.
    public func move(_ t: String, _ fields: [String: JSON] = [:]) {
        guard let s = seat else { return }
        send(Out.move(t, fields, seat: s))
    }

    // MARK: the socket

    private func connect() {
        status = attempt == 0 ? .connecting : .reconnecting(attempt: attempt)
        changed()
        transport.open(endpoints.socket(game, code: code)) { [weak self] e in self?.handle(e) }
    }

    func handle(_ e: TransportEvent) {
        switch e {
        case .opened:
            open = true
            send(Out.hello(app: "ios \(appVersion)", session: sessionToken, v: helloVersion))
        case let .text(t):
            if let m = ServerMessage.decode(t) { receive(m) }
        case let .closed(code):
            let wasOpen = open
            open = false
            switch code {
            case 4001: finish(.removed)
            case 4002: finish(.moved)
            case 4005: finish(.closedByOwner)
            default:
                if case .ended = status { return }
                if case .needsUpdate = status { return }
                if wasOpen || attempt > 0 || seat != nil { snapshotHand() }
                attempt += 1
                status = .reconnecting(attempt: attempt)
                changed()
            }
        }
    }

    func receive(_ m: ServerMessage) {
        switch m {
        case let .hello(_, _, g, update, acct):
            account = acct; game_ = g
            if update { status = .needsUpdate; open = false; transport.close(); changed(); return }
            if let s = seat {
                resuming = true
                send(Out.resume(id: s.id, token: s.token))
            } else if let w = wantWatch {
                status = .joining
                send(Out.watch(name: w))
            } else if let w = wantJoin {
                status = .joining
                send(Out.join(name: w.name, face: w.face))
            } else {
                status = .choosing(problem: nil)
            }
            changed()
        case .pong: break
        case let .joined(s):
            seat = s
            store.save(SavedSeat(code: code, game: game, seat: s))
            attempt = 0
            status = .inRoom
            changed()
        case .resumed:
            attempt = 0
            status = .inRoom
            changed()
        case let .view(v):
            view = v
            if v["spectator"].bool == true { watching = true }
            if status != .inRoom, seat != nil || watching { status = .inRoom; attempt = 0 }
            if resuming { resuming = false; noteBack(v) }
            changed()
        case let .floor(f):
            // a watcher may be sent the room's public view (the floor) rather than a phone's
            if watching { view = f; if status != .inRoom { status = .inRoom; attempt = 0 }; changed() }
        case let .react(id, r):
            if let r = Reaction(rawValue: r) { onNotice?(.reaction(playerId: id, r)) }
        case let .error(message, code):
            handleError(message, code)
        case .moved: finish(.moved)
        case let .removed(why): finish(why == "expired" ? .expired : .removed)
        case .ended: finish(.closedByOwner)
        case .unknown: break
        }
    }

    private func handleError(_ message: String, _ code: String?) {
        if resuming {
            resuming = false
            switch code {
            case "ended": finish(.closedByOwner); return
            case "removed": finish(.removed); return
            case "expired": finish(.expired); return
            case "left": finish(.left); return
            default:
                // "gone" (no such player) or not this seat: the seat is no good; join afresh as the website does
                store.forget(code: code_)
                seat = nil
                if let w = wantJoin { status = .joining; send(Out.join(name: w.name, face: w.face)) }
                else { status = .choosing(problem: nil) }
                changed(); return
            }
        }
        if status == .joining {
            switch code {
            case "face_taken", "face_missing": status = .choosing(problem: message); wantJoin = nil
            case "name_word": status = .choosing(problem: "Please pick another name."); wantJoin = nil
            case "table_full", "playing", "done": finish(.refused(message))
            default:
                if message.hasPrefix("Names need") { status = .choosing(problem: message); wantJoin = nil }
                else { finish(.refused(message)) }
            }
            changed(); return
        }
        onNotice?(.problem(message))
    }

    private var code_: String { code }

    private func finish(_ why: EndReason) {
        if why != .moved { store.forget(code: code); seat = nil }
        open = false
        transport.close()
        status = .ended(why)
        changed()
    }

    private func snapshotHand() {
        if handBefore == nil, let v = view { handBefore = Set(v["hand"].array.compactMap { $0["id"].string }) }
    }

    /// "You're back. The bot played 2 cards for you." (Overdraft compares the hand from before the drop.)
    private func noteBack(_ v: JSON) {
        defer { handBefore = nil }
        guard let before = handBefore else { onNotice?(.back("You’re back.")); return }
        let now = Set(v["hand"].array.compactMap { $0["id"].string })
        let played = before.subtracting(now).count, drew = now.subtracting(before).count
        onNotice?(.back(RoomSession.backLine(played: played, drew: drew)))
    }

    public static func backLine(played: Int, drew: Int) -> String {
        var s = "You’re back."
        if played > 0 { s += " The bot played \(played) card\(played == 1 ? "" : "s") for you." }
        else if drew > 0 { s += " The room drew \(drew) card\(drew == 1 ? "" : "s") for you." }
        return s
    }

    private func changed() { onChange?() }
}
