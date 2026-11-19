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
        if SocialDemo.on { SocialDemo.load(into: self); return }   // the test build's stand-in friends
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
        friends = Friends(); groups = []; challenges = []; challengesLoaded = false
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
        guard signedIn, !SocialDemo.on else { return }
        async let f = try? api.friends()
        async let g = try? api.groups()
        async let c = try? api.challenges()
        if let f = await f { friends = f }
        if let g = await g { groups = g }
        if let c = await c {
            // an invite that came in while the app is open: the painted banner (once per room; not the first load)
            let new = c.filter { n in !challenges.contains { $0.id == n.id } }
            let first = !challengesLoaded
            challenges = c; challengesLoaded = true
            if !first, let n = new.first, room?.code != n.room { bannerFor(n) }
        }
    }

    func bannerFor(_ c: Challenge) {
        AppDialogs.shared.showBanner(InviteNote(text: "\(c.from.name) invited you to \(c.game?.title ?? "a game")", game: c.game, room: c.room, face: c.from.face))
    }

    func social(_ work: @escaping () async throws -> Void) async {
        if SocialDemo.on { return }   // the stand-in friends stay as they are
        do { try await work(); await refreshSocial() }
        catch { accountProblem = (error as? API.Failure)?.message ?? "That didn’t work. Check your signal and try again." }
    }

    /// Starts a room, opens it (you own it), and invites friends or a group to it. The lobby then says who's invited.
    func challenge(_ game: Game, to friends: [PlayerCard], group: PlayerGroup? = nil) async {
        await start(game)
        guard let r = room else { return }
        // wait for your own seat first: the first person in a room owns it
        for _ in 0..<40 where !r.hasSeat { try? await Task.sleep(nanoseconds: 250_000_000) }
        await invite(game: game, room: r.code, friends: friends, group: group)
    }

    func joinChallenge(_ c: Challenge) async {
        try? await api.dismissChallenge(c.id)
        challenges.removeAll { $0.id == c.id }
        await join(code: c.room)
    }

    /// A friend or group link (time2play.live/f/CODE), opened from outside the app: a painted question first. Since
    /// #575 the server's peek says whose link it is before it's used, so the question names them ("Add Sam as a
    /// friend?", "Join Thursday crew?"). An older server without the peek gets the question as before, which can't
    /// name them; the answer does.
    func openFriendLink(_ code: String) async {
        guard signedIn else {
            tab = .friends
            AppDialogs.shared.say("Sign in to use friend links",
                                  "A friend link adds a friend or puts you in a group, so it needs an account. Sign in here on Friends, then open the link again.",
                                  identifier: "dialog-link-sign-in")
            return
        }
        let peek: LinkPeek?
        if SocialDemo.on {
            peek = code.hasPrefix("GRP") ? LinkPeek(kind: .group(id: "g_demo_board", name: "Board game night", size: 5))
                : SocialDemo.oldServer ? nil : LinkPeek(kind: .friend(SocialDemo.sam))
        } else {
            peek = try? await api.peekLink(code)
        }
        guard let p = peek else { askToOpen(code); return }
        switch p.kind {
        case let .friend(f) where p.already:
            tab = .friends
            AppDialogs.shared.say("You and \(f.name) are already friends", "Invite them from your room’s lobby, or from here.", ok: "OK", identifier: "dialog-link-already")
        case let .group(_, name, _) where p.already:
            tab = .friends
            AppDialogs.shared.say("You’re already in \(name)", "Invite the whole group from your room’s lobby, or from here.", ok: "OK", identifier: "dialog-link-already")
        case let .group(_, name, _) where p.full:
            AppDialogs.shared.say("\(name) is full", "Ask them to make room, or to start another group.", identifier: "dialog-link-failed")
        case let .friend(f):
            AppDialogs.shared.show(GameDialog(
                title: p.question,
                message: "You’ll be friends with \(f.name), so you can invite each other to games.",
                choices: [GameChoice(label: "Add \(f.name)", kind: .gold, identifier: "link-open") { [weak self] in
                    Task { await self?.acceptFriendLink(code, demoName: f.name) }
                }],
                cancel: "Not now", identifier: "dialog-friend-link"))
        case let .group(_, name, size):
            AppDialogs.shared.show(GameDialog(
                title: p.question,
                message: size == 1 ? "1 person is in it. You’ll get the group’s invites to games." : "\(size) people are in it. You’ll get the group’s invites to games.",
                choices: [GameChoice(label: "Join the group", kind: .gold, identifier: "link-open") { [weak self] in
                    Task { await self?.acceptFriendLink(code, demoName: name, demoGroup: true) }
                }],
                cancel: "Not now", identifier: "dialog-friend-link"))
        }
    }

    /// The question before #575 (an older server): it can't say whose link it is.
    private func askToOpen(_ code: String) {
        AppDialogs.shared.show(GameDialog(
            title: "Open this friend link?",
            message: "A friend link makes you friends with whoever sent it. A group link puts you in their group.",
            choices: [GameChoice(label: "Open it", kind: .gold, identifier: "link-open") { [weak self] in
                Task { await self?.acceptFriendLink(code) }
            }],
            cancel: "Not now", identifier: "dialog-friend-link"))
    }

    private func acceptFriendLink(_ code: String, demoName: String = "Sam", demoGroup: Bool = false) async {
        if SocialDemo.on {
            if demoGroup { AppDialogs.shared.say("You joined \(demoName)", "Invite the whole group from your room’s lobby, or from here.", ok: "Nice", identifier: "dialog-link-done") }
            else { AppDialogs.shared.say("You and \(demoName) are friends", "Invite them from your room’s lobby, or from here.", ok: "Nice", identifier: "dialog-link-done") }
            tab = .friends
            return
        }
        do {
            let r = try await api.openLink(code)
            await refreshSocial(); tab = .friends
            if r.kind == "friend" {
                AppDialogs.shared.say("You and \(r.name) are friends", "Invite them from your room’s lobby, or from here.", ok: "Nice", identifier: "dialog-link-done")
            } else {
                AppDialogs.shared.say("You joined \(r.name)", "Invite the whole group from your room’s lobby, or from here.", ok: "Nice", identifier: "dialog-link-done")
            }
        } catch {
            AppDialogs.shared.say("That link didn’t work", (error as? API.Failure)?.message ?? "Check your signal and try again.", identifier: "dialog-link-failed")
        }
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
