import SwiftUI
import Security
import AuthenticationServices
import UserNotifications
import T2PCore

/// The session token lives in the iPhone's Keychain, never in plain settings.
enum Keychain {
    private static let service = "live.time2play.session"
    static func save(_ token: String) {
        delete()
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock, kSecValueData as String: Data(token.utf8)]
        SecItemAdd(q as CFDictionary, nil)
    }
    static func load() -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func delete() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
    }
}

/// The signed-in account, saved so the app knows it at launch. Saved data: add fields, never rename or remove.
struct SavedAccount: Codable, Equatable {
    var account: Account
    var kind: String   // "apple" or "review"
}

/// Sign in with Apple, asked for in code (to get a fresh authorization code when deleting an account).
@MainActor
final class AppleAuth: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var done: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?
    func request() async throws -> ASAuthorizationAppleIDCredential {
        let r = ASAuthorizationAppleIDProvider().createRequest()
        r.requestedScopes = []   // no name, no email: the app asks for a display name itself
        let c = ASAuthorizationController(authorizationRequests: [r])
        c.delegate = self; c.presentationContextProvider = self
        return try await withCheckedThrowingContinuation { k in done = k; c.performRequests() }
    }
    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization a: ASAuthorization) {
        Task { @MainActor in
            if let c = a.credential as? ASAuthorizationAppleIDCredential { done?.resume(returning: c) }
            else { done?.resume(throwing: API.Failure(status: 0, message: "Couldn’t sign in with Apple.", code: nil)) }
            done = nil
        }
    }
    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        Task { @MainActor in done?.resume(throwing: error); done = nil }
    }
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        }
    }
}

extension AppModel {
    var signedIn: Bool { account != nil }

    func restoreAccount() {
        guard let saved: SavedAccount = UserDefaults.standard.data(forKey: "t2p.account").flatMap({ try? JSONDecoder().decode(SavedAccount.self, from: $0) }),
              let token = Keychain.load() else { return }
        account = saved; api.session = token
        Task { await refreshAccount() }
    }

    func refreshAccount() async {
        guard account != nil else { return }
        do {
            let a = try await api.me()
            account?.account = a; saveAccount()
            await refreshSocial()
        } catch let f as API.Failure where f.code == "session" {
            forgetAccount()
        } catch {}
    }

    private func saveAccount() { UserDefaults.standard.set(try? JSONEncoder().encode(account), forKey: "t2p.account") }
    private func forgetAccount() {
        account = nil; api.session = nil; Keychain.delete()
        UserDefaults.standard.removeObject(forKey: "t2p.account")
        friends = Friends(); groups = []; challenges = []
    }

    private func signedIn(_ s: SignedIn, kind: String) async {
        Keychain.save(s.token); api.session = s.token
        account = SavedAccount(account: s.account, kind: kind); saveAccount()
        // the guest's name and face carry into the account (a new account takes them; an old one keeps its own)
        profile = Profile(name: s.account.name, face: s.account.face)
        await refreshSocial()
        await askForAlerts()
    }

    /// Sign in with Apple, after the age question said 13 or older.
    func signInWithApple(_ c: ASAuthorizationAppleIDCredential) async {
        guard let t = c.identityToken.flatMap({ String(data: $0, encoding: .utf8) }) else { accountProblem = "Couldn’t sign in with Apple."; return }
        let name = profile.name.count >= 2 ? profile.name : "Player"
        do {
            await signedIn(try await api.signInWithApple(identityToken: t, name: name, face: profile.face ?? 9, over13: true, app: "ios \(AppModel.appVersion)"), kind: "apple")
        } catch { accountProblem = (error as? API.Failure)?.message ?? "Couldn’t sign in. Check your signal and try again." }
    }

    /// App Review's sign-in (the key is in the review notes).
    func signInForReview(key: String, slot: Int = 1) async {
        do { await signedIn(try await api.signInForReview(key: key, slot: slot, app: "ios \(AppModel.appVersion)"), kind: "review") }
        catch { accountProblem = (error as? API.Failure)?.message ?? "Couldn’t sign in. Check your signal and try again." }
    }

    func signOut() async {
        try? await api.signOut()
        forgetAccount()
    }

    /// Deletes the account and everything of it. An Apple account asks Apple once more, so the server can revoke it.
    func deleteAccount() async -> Bool {
        var code: String?
        if account?.kind == "apple" {
            code = (try? await AppleAuth().request())?.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
        }
        do {
            try await api.deleteAccount(authorizationCode: code)
            forgetAccount()
            return true
        } catch {
            accountProblem = (error as? API.Failure)?.message ?? "Couldn’t delete the account. Check your signal and try again."
            return false
        }
    }

    func rename(_ name: String?, face: Int?) async {
        do { let a = try await api.update(name: name, face: face); account?.account = a; saveAccount(); profile = Profile(name: a.name, face: a.face) }
        catch { accountProblem = (error as? API.Failure)?.message ?? "Couldn’t save that." }
    }

    // MARK: friends, groups, challenges

    func refreshSocial() async {
        guard signedIn else { return }
        async let f = try? api.friends()
        async let g = try? api.groups()
        async let c = try? api.challenges()
        if let f = await f { friends = f }
        if let g = await g { groups = g }
        if let c = await c { challenges = c }
    }

    func social(_ work: @escaping () async throws -> Void) async {
        do { try await work(); await refreshSocial() }
        catch { accountProblem = (error as? API.Failure)?.message ?? "That didn’t work. Check your signal and try again." }
    }

    /// Starts a room, opens it (you own it), and invites friends or a group to it.
    func challenge(_ game: Game, to: [String], group: String? = nil) async {
        await start(game)
        guard let r = room else { return }
        // wait for your own seat first: the first person in a room owns it
        for _ in 0..<40 where !r.hasSeat { try? await Task.sleep(nanoseconds: 250_000_000) }
        do { try await api.sendChallenge(game: game, room: r.code, to: to, group: group) }
        catch { r.toast = (error as? API.Failure)?.message ?? "The invite didn’t go." }
    }

    func joinChallenge(_ c: Challenge) async {
        try? await api.dismissChallenge(c.id)
        challenges.removeAll { $0.id == c.id }
        await join(code: c.room)
    }

    /// A friend or group link (time2play.live/f/CODE).
    func openFriendLink(_ code: String) async {
        guard signedIn else { tab = .friends; accountProblem = "Sign in to add friends from a link."; return }
        do {
            let r = try await api.openLink(code)
            notice = r.kind == "friend" ? "You and \(r.name) are friends now." : "You joined \(r.name)."
            await refreshSocial(); tab = .friends
        } catch { accountProblem = (error as? API.Failure)?.message ?? "That link didn’t work." }
    }

    // MARK: invite alerts (#404)

    /// Alerts are for signed-in players (invites come from friends). Asked once, after signing in.
    func askForAlerts() async {
        let ok = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if ok { UIApplication.shared.registerForRemoteNotifications() }
    }

    func registerDevice(_ token: Data) {
        guard signedIn else { return }
        let hex = token.map { String(format: "%02x", $0) }.joined()
        #if DEBUG
        let sandbox = true
        #else
        let sandbox = false
        #endif
        Task { try? await api.registerPush(device: hex, sandbox: sandbox, turn: TurnAlerts.on) }
    }

    /// You → "Alerts for my turn": on asks for alerts if they haven't been allowed yet; either way the device
    /// registers again, carrying the new choice to the server (#534).
    func turnAlertsChanged(_ on: Bool) async {
        guard signedIn else { return }
        if on { await askForAlerts() } else { UIApplication.shared.registerForRemoteNotifications() }
    }
}
