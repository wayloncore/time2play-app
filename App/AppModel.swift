import SwiftUI
import T2PCore

/// The player's own name and face as a guest, kept on this phone. Saved data: add fields, never rename or remove.
struct Profile: Codable, Equatable {
    var name: String = ""
    var face: Int? = nil
}

/// Seats this phone holds, by room code (so a dropped phone comes back to the same seat), in UserDefaults.
final class DefaultsSeatStore: SeatStore {
    private let key = "t2p.seats"
    private var all: [String: SavedSeat] {
        get { (UserDefaults.standard.data(forKey: key)).flatMap { try? JSONDecoder().decode([String: SavedSeat].self, from: $0) } ?? [:] }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key) }
    }
    func seat(for code: String) -> SavedSeat? { all[code] }
    func save(_ seat: SavedSeat) {
        var a = all.filter { Date().timeIntervalSince($0.value.savedAt) < 86_400 }   // a day at most: rooms go long before
        a[seat.code] = seat; all = a
    }
    func forget(code: String) { var a = all; a[code] = nil; all = a }
}

@MainActor
final class AppModel: ObservableObject {
    static let appVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"

    let endpoints: Endpoints
    let api: API
    let seats = DefaultsSeatStore()

    @Published var profile: Profile { didSet { save(profile, "t2p.profile") } }
    @Published var room: RoomModel?
    @Published var library: Library
    @Published var libraryProblem: String?
    @Published var tab: Tab = .play
    @Published var busy = false
    @Published var problem: String?
    /// The signed-in account (#403), or nil: a guest. Nobody needs one to play.
    @Published var account: SavedAccount?
    @Published var accountProblem: String?
    @Published var notice: String?
    @Published var friends = Friends()
    @Published var groups: [PlayerGroup] = []
    @Published var challenges: [Challenge] = []

    enum Tab: Hashable { case play, friends, library, you }

    init() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-uitest-reset") {
            for k in ["t2p.profile", "t2p.seats", "t2p.library", "t2p.account", Table3DSwitch.classicKey] { UserDefaults.standard.removeObject(forKey: k) }
            Keychain.delete()
        }
        // A test (or a check against staging) can point the app elsewhere: -t2p-base https://…
        if let i = args.firstIndex(of: "-t2p-base"), i + 1 < args.count, let u = URL(string: args[i + 1]) {
            endpoints = Endpoints(base: u, joinSite: Endpoints.live.joinSite)
        } else { endpoints = .live }
        api = API(endpoints: endpoints)
        api.appVersion = "ios \(AppModel.appVersion)"
        profile = AppModel.load("t2p.profile") ?? Profile()
        library = UserDefaults.standard.data(forKey: "t2p.library").flatMap { JSON.parse($0) }.flatMap { Library($0) } ?? Library()
        // a test can start with a name (-t2p-name Sim), so the largest-text tour doesn't type
        if let i = args.firstIndex(of: "-t2p-name"), i + 1 < args.count, profile.name.isEmpty { profile = Profile(name: args[i + 1], face: 9) }
        restoreAccount()
    }

    private static func load<T: Decodable>(_ key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
    private func save<T: Encodable>(_ v: T, _ key: String) { UserDefaults.standard.set(try? JSONEncoder().encode(v), forKey: key) }

    // MARK: rooms

    /// Joins a room by its code: finds which game it is, then opens it.
    func join(code: String) async {
        guard let c = RoomCode.normalize(code) else { problem = "Room codes are 4 letters and numbers."; return }
        busy = true; defer { busy = false }
        do {
            guard let found = try await api.find(code: c) else {
                problem = "There’s no room \(c) right now. Check the code, or start a room of your own."
                return
            }
            guard let g = found.game else {
                problem = "Room \(c) is a game the app doesn’t have yet. It opens on the website."
                webFallback = endpoints.invite(code: c)
                return
            }
            open(g, code: c, taken: found.taken)
        } catch {
            problem = (error as? API.Failure)?.message ?? "No connection. Check your signal and try again."
        }
    }
    @Published var webFallback: URL?

    /// Starts a hostless room of a game; the first to join owns it, which is you.
    func start(_ g: Game) async {
        busy = true; defer { busy = false }
        do {
            let c = try await api.startRoom(g)
            open(g, code: c, taken: [], starting: true)
        } catch {
            problem = (error as? API.Failure)?.message ?? "Couldn’t start a room. Check your signal and try again."
        }
    }

    func open(_ g: Game, code: String, taken: [Int], starting: Bool = false) {
        room?.close()
        let r = RoomModel(game: g, code: code, app: self, taken: taken, starting: starting, session: api.session)
        room = r
        r.start()
        TVModel.shared.watch(g, code: code, endpoints: endpoints)
    }

    func closeRoom() { room?.close(); room = nil; TVModel.shared.watch(nil, code: nil, endpoints: endpoints) }

    /// The server's own rules, loaded once, for playing bots with no signal (#402).
    /// Hot Dice also asks them which dice in a roll can score (#488), online too.
    lazy var offlineRules: OfflineRules? = OfflineRules.load()
    /// A test can fix an offline room's dice: -t2p-seed 3 (#488's Farkle test).
    let offlineSeed: UInt32? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-t2p-seed"), i + 1 < args.count else { return nil }
        return UInt32(args[i + 1])
    }()

    /// An offline practice room with bots: the same screens, the same rules, no server. Nothing here counts.
    func startOffline(_ g: Game) {
        guard let rules = offlineRules else { problem = "Offline play isn’t available right now."; return }
        room?.close()
        let r = RoomModel(game: g, code: "SOLO", app: self, taken: [], starting: true, offline: rules)
        room = r
        r.start()
    }

    // MARK: the Library

    func loadLibrary() async {
        do {
            let (lib, data) = try await api.library()
            library = lib; libraryProblem = nil
            UserDefaults.standard.set(data, forKey: "t2p.library")
        } catch {
            libraryProblem = library.items.isEmpty ? "The Library didn’t load. Check your signal and pull to try again." : nil
        }
    }
}
