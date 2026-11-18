import Foundation
import Security
import T2PCore

/// What the app and its home screen widget share: the last room you were in (for the widget's one-tap rejoin).
/// It travels in a Keychain group both carry (keychain-access-groups in both entitlements files: an App Store
/// profile allows any group under the team, so this needs no App Group set up in the developer portal).
/// A build that isn't signed (the simulator's UI tests) can't use the group; it keeps a copy in its own defaults.
enum SharedRoom {
    static let group = "6WK983RXJT.live.time2play.shared"
    private static let service = "live.time2play.lastRoom"
    private static let fallbackKey = "t2p.sharedLastRoom"

    static func save(_ r: RecentRoom) {
        guard let d = try? JSONEncoder().encode(r) else { return }
        var q = base(group: true)
        SecItemDelete(q as CFDictionary)
        q[kSecValueData as String] = d
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        if SecItemAdd(q as CFDictionary, nil) != errSecSuccess { UserDefaults.standard.set(d, forKey: fallbackKey) }
    }

    static func load() -> RecentRoom? {
        var q = base(group: true)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        let d: Data? = SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess ? out as? Data : UserDefaults.standard.data(forKey: fallbackKey)
        return d.flatMap { try? JSONDecoder().decode(RecentRoom.self, from: $0) }
    }

    static func clear() {
        SecItemDelete(base(group: true) as CFDictionary)
        UserDefaults.standard.removeObject(forKey: fallbackKey)
    }

    private static func base(group: Bool) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        if group { q[kSecAttrAccessGroup as String] = SharedRoom.group }
        return q
    }
}

/// The links the widget opens (the app's own scheme, handled in Time2PlayApp's onOpenURL).
enum AppLinks {
    /// time2play://join/K7QP: join (or rejoin) a room.
    static func join(_ code: String) -> URL { URL(string: "time2play://join/\(code)")! }
    /// time2play://game/<library key>: show a Library card (the game of the day).
    static func game(_ key: String) -> URL { URL(string: "time2play://game/\(key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key)")! }
    static func gameKey(_ url: URL) -> String? {
        guard url.scheme == "time2play", url.host == "game" else { return nil }
        let k = url.lastPathComponent
        return k.isEmpty || k == "/" ? nil : k
    }
}
