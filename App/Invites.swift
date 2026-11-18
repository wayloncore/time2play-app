import SwiftUI
import T2PCore

/// Inviting friends to a room you host (Tyler, Nov 18: "if i click host a game i can also click invite friends and i
/// see a screen i can toggle whether i want to invite a friend or a group"). The lobby (iPhone) and the iPad host have
/// an Invite friends button; it opens the painted invite screen: Friends | Groups, pick, then Send. It calls the
/// server's challenges/send with this room's code (a challenge is an invite to a ready-made room, #396). Who was
/// invited shows in the lobby ("Invited: Sam, Jo"), and you can invite more.

/// Who this phone invited to which room (kept in memory: invites last two hours at most, rooms less).
@MainActor
final class InviteBook: ObservableObject {
    @Published private(set) var names: [String: [String]] = [:]
    @Published private(set) var ids: [String: Set<String>] = [:]

    func add(room: String, names new: [String], ids newIds: [String]) {
        var n = names[room] ?? []
        for x in new where !n.contains(x) { n.append(x) }
        names[room] = n
        ids[room, default: []].formUnion(newIds)
    }

    func invited(_ id: String, room: String) -> Bool { ids[room]?.contains(id) ?? false }

    /// "Invited: Sam, Jo", "Invited: Sam, Jo, Priya and 2 more", or nil before anyone is.
    func line(_ room: String) -> String? {
        guard let n = names[room], !n.isEmpty else { return nil }
        let shown = n.count <= 3 ? n.joined(separator: ", ") : n.prefix(3).joined(separator: ", ") + " and \(n.count - 3) more"
        return "Invited: \(shown)"
    }
}

/// The test build's stand-in friends (-t2p-social-demo; -t2p-social-demo-empty for none), for screenshots where a real
/// friend list isn't available. Release builds have none of it.
enum SocialDemo {
    #if DEBUG
    private static let args = ProcessInfo.processInfo.arguments
    static let empty = args.contains("-t2p-social-demo-empty")
    static let on = empty || args.contains("-t2p-social-demo")
    /// The server refusing every invite (the error shows painted).
    static let failInvites = args.contains("-t2p-invite-fail")
    /// An invite banner a moment after launch.
    static let banner = args.contains("-t2p-demo-banner")
    #else
    static let empty = false, on = false, failInvites = false, banner = false
    #endif

    static let me = PlayerCard(id: "a_demo_me", name: "Sim", face: 9)
    static let sam = PlayerCard(id: "a_demo_sam", name: "Sam", face: 3)
    static let jo = PlayerCard(id: "a_demo_jo", name: "Jo", face: 12)
    static let priya = PlayerCard(id: "a_demo_priya", name: "Priya", face: 20)
    static let marcus = PlayerCard(id: "a_demo_marcus", name: "Marcus", face: 31)
    static let lena = PlayerCard(id: "a_demo_lena", name: "Lena", face: 7)

    @MainActor static func load(into app: AppModel) {
        app.account = SavedAccount(account: Account(id: me.id, name: me.name, face: me.face), kind: "apple")
        if app.profile.name.isEmpty { app.profile = Profile(name: me.name, face: me.face) }
        if empty { return }
        var f = Friends()
        f.friends = [sam, jo, priya, marcus, lena]
        f.incoming = [PlayerCard(id: "a_demo_theo", name: "Theo", face: 15)]
        f.recent = [PlayerCard(id: "a_demo_ava", name: "Ava", face: 25)]
        f.outgoing = [PlayerCard(id: "a_demo_kai", name: "Kai", face: 40)]
        app.friends = f
        app.groups = [PlayerGroup(id: "g_demo_thursday", name: "Thursday crew", mine: true, members: [me, sam, jo, priya]),
                      PlayerGroup(id: "g_demo_lunch", name: "Lunch league", mine: false, members: [marcus, lena, me])]
        app.challenges = [Challenge(id: "c_demo_1", from: jo, game: .hotDice, room: "DEMO", created: Date().addingTimeInterval(-180).timeIntervalSince1970 * 1000)]
    }
}

extension AppModel {
    /// Sends invites to this room: friends, or a group. True when they went; a refusal shows painted, with the
    /// server's own words (before wayloncore/tyleralocke#566 it refuses Roll Call and Close Enough rooms).
    @discardableResult
    func invite(game: Game, room: String, friends: [PlayerCard] = [], group: PlayerGroup? = nil) async -> Bool {
        let names = group.map { [$0.name] } ?? friends.map(\.name)
        let ids = friends.map(\.id) + (group.map { [$0.id] } ?? [])
        if SocialDemo.on {
            if SocialDemo.failInvites { inviteFailed("Start a room first."); return false }
            invites.add(room: room, names: names, ids: ids)
            return true
        }
        do {
            try await api.sendChallenge(game: game, room: room, to: friends.map(\.id), group: group?.id)
            invites.add(room: room, names: names, ids: ids)
            return true
        } catch {
            inviteFailed((error as? API.Failure)?.message ?? "Check your signal and try again.")
            return false
        }
    }

    private func inviteFailed(_ why: String) {
        AppDialogs.shared.say("The invite didn’t go", why, identifier: "dialog-invite-failed")
    }

    /// An invite's room, from its banner or its alert: straight in, and the invite leaves Friends.
    func openInvite(code: String) async {
        let c = challenges.first { $0.room == code }
        await openRoom(code: code)
        if let c {
            challenges.removeAll { $0.id == c.id }
            if !SocialDemo.on { try? await api.dismissChallenge(c.id) }
        }
    }

    /// Your friend link (7 days), ready to share; a failure shows painted.
    func friendLinkURL() async -> URL? {
        if SocialDemo.on { return FriendLink.url("DEMO2345") }
        do { return FriendLink.url(try await api.friendLink()) }
        catch {
            AppDialogs.shared.say("Couldn’t make a link", (error as? API.Failure)?.message ?? "Check your signal and try again.")
            return nil
        }
    }
}

extension PlayerGroup {
    /// "4 people: Sam, Jo and 1 more" (you're left out of the names).
    func line(me: String?) -> String {
        let names = members.filter { $0.id != me }.map(\.name)
        let shown = names.count <= 2 ? names.joined(separator: " and ") : names.prefix(2).joined(separator: ", ") + " and \(names.count - 2) more"
        let count = members.count == 1 ? "Just you" : "\(members.count) people"
        return names.isEmpty ? count : "\(count): \(shown)"
    }
}

/// The lobby's (and the iPad host's) Invite friends button, with who's been invited under it.
struct InviteFriendsBar: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var book: InviteBook
    let game: Game
    let code: String
    @State private var open = false

    var body: some View {
        let line = book.line(code)
        Button { open = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "person.2.fill").font(.title3).foregroundStyle(T2P.ink)
                    .frame(width: 46, height: 46).background(T2P.gold, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(line == nil ? "Invite friends" : "Invite more friends").font(.headline).foregroundStyle(T2P.text)
                    Text(line ?? "Pick friends or a group. They get an alert and join in one tap.")
                        .font(.subheadline).foregroundStyle(line == nil ? T2P.muted : T2P.goldText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.headline).foregroundStyle(T2P.faint)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(T2P.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(T2P.gold.opacity(0.7), lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("invite-friends")
        .sheet(isPresented: $open) { InviteSheet(book: book, game: game, code: code).environmentObject(app) }
    }
}

/// The painted invite screen: Friends | Groups, then Send.
struct InviteSheet: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var book: InviteBook
    let game: Game
    let code: String
    @Environment(\.dismiss) private var dismiss
    enum Mode: Hashable { case friends, groups }
    @State private var mode: Mode = .friends
    @State private var picked: Set<String> = []
    @State private var group: String?
    @State private var sending = false
    @State private var share: ShareItem?
    @State private var makingGroup = false

    var body: some View {
        VStack(spacing: 14) {
            header
            if app.signedIn {
                PaintedTabs<Mode>(options: [PaintedTabs<Mode>.Option(value: .friends, label: "Friends", identifier: "invite-tab-friends"),
                                            PaintedTabs<Mode>.Option(value: .groups, label: "Groups", identifier: "invite-tab-groups")],
                                  selection: $mode)
                    .padding(.horizontal, 20)
                ScrollView {
                    VStack(spacing: 10) {
                        if mode == .friends { friendsList } else { groupsList }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 4)
                }
                sendBar
            } else {
                ScrollView { signedOut.padding(.horizontal, 20) }
            }
        }
        .padding(.top, 20)
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PaintedBackdrop().ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground { PaintedBackdrop() }
        .task { await app.refreshSocial() }
        .sheet(item: $share) { s in ShareSheet(items: [s.url]) }
        .sheet(isPresented: $makingGroup) { NewGroup().environmentObject(app) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("invite-screen")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            GameArt(game: game)
                .frame(width: 60, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Painted.gold.opacity(0.6), lineWidth: 1))
            VStack(alignment: .leading, spacing: 3) {
                Text("INVITE TO \(game.title.uppercased())").font(Painted.display(19)).tracking(1.3).foregroundStyle(Painted.titleGold)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                Text("Room \(code)").font(.subheadline).foregroundStyle(Painted.paperDim)
            }
            Spacer(minLength: 4)
            PaintedIconButton(icon: "xmark", label: "Close", identifier: "invite-close") { dismiss() }
        }
        .padding(.horizontal, 20)
    }

    // MARK: signed out

    private var signedOut: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Invites need you to sign in.").font(Painted.display(20)).foregroundStyle(Painted.paper)
                .accessibilityIdentifier("invite-needs-sign-in")
            SignInPanel(painted: true)
            PaintedDivider().frame(maxWidth: .infinity)
            Text("Or send this room’s link: anyone with it can join, no account needed.").font(.subheadline).foregroundStyle(Painted.paperDim)
            roomLink
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Painted.gold.opacity(0.3), lineWidth: 1))
    }

    private var roomLink: some View {
        ShareLink(item: app.endpoints.invite(code: code), subject: Text("Play \(game.title)"), message: Text("Join my \(game.title) room: code \(code)")) {
            Label("Share this room’s link", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(PaintedButtonStyle(kind: .quiet))
        .accessibilityIdentifier("invite-room-link")
    }

    // MARK: friends

    @ViewBuilder private var friendsList: some View {
        if app.friends.friends.isEmpty {
            emptyCard(title: "No friends yet",
                      text: "Send your friend link. Anyone who opens it becomes your friend right away, and the link works for 7 days. Then invite them from here.") {
                Button { Task { if let u = await app.friendLinkURL() { share = ShareItem(url: u) } } } label: {
                    Label("Send your friend link", systemImage: "link")
                }
                .buttonStyle(PaintedButtonStyle(kind: .gold))
                .accessibilityIdentifier("invite-friend-link")
                roomLink
            }
        } else {
            ForEach(app.friends.friends) { p in friendRow(p) }
        }
    }

    private func friendRow(_ p: PlayerCard) -> some View {
        let on = picked.contains(p.id)
        let already = book.invited(p.id, room: code)
        return Button {
            if on { picked.remove(p.id) } else { picked.insert(p.id) }
            Haptics.select()
        } label: {
            HStack(spacing: 12) {
                FaceView(face: p.face, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name).font(Painted.display(18)).foregroundStyle(Painted.paper)
                    if already { Text("Invited").font(.caption.weight(.semibold)).foregroundStyle(Painted.gold) }
                }
                Spacer()
                PaintedCheck(on: on)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(on ? Painted.gold.opacity(0.14) : Color.white.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(on ? Painted.gold : Painted.gold.opacity(0.25), lineWidth: on ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(already ? "\(p.name), invited" : p.name)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("invite-friend-\(p.id)")
    }

    // MARK: groups

    @ViewBuilder private var groupsList: some View {
        if app.groups.isEmpty {
            emptyCard(title: "No groups yet", text: "A group is a few friends you invite in one go, like a Thursday crew.") {
                if app.friends.friends.isEmpty {
                    Text("Add a friend first, then make a group.").font(.subheadline.weight(.semibold)).foregroundStyle(Painted.goldLight)
                } else {
                    Button { makingGroup = true } label: { Label("Make a group", systemImage: "person.3.fill") }
                        .buttonStyle(PaintedButtonStyle(kind: .gold))
                        .accessibilityIdentifier("invite-make-group")
                }
            }
        } else {
            ForEach(app.groups) { g in groupRow(g) }
            if !app.friends.friends.isEmpty {
                Button { makingGroup = true } label: { Label("Make a group", systemImage: "plus") }
                    .buttonStyle(PaintedButtonStyle(kind: .quiet))
                    .accessibilityIdentifier("invite-make-group")
            }
        }
    }

    private func groupRow(_ g: PlayerGroup) -> some View {
        let on = group == g.id
        return Button {
            group = on ? nil : g.id
            Haptics.select()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(g.name).font(Painted.display(18)).foregroundStyle(Painted.paper).lineLimit(1)
                        if g.mine { PaintedTag(text: "Yours") }
                        if book.invited(g.id, room: code) { PaintedTag(text: "Invited") }
                    }
                    HStack(spacing: -8) {
                        ForEach(g.members.prefix(7)) { m in
                            FaceView(face: m.face, size: 28).overlay(Circle().stroke(Painted.faceBottom, lineWidth: 1.5))
                        }
                    }
                    Text(g.line(me: app.account?.account.id)).font(.caption).foregroundStyle(Painted.paperDim).lineLimit(1)
                }
                Spacer()
                PaintedCheck(on: on)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(on ? Painted.gold.opacity(0.14) : Color.white.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(on ? Painted.gold : Painted.gold.opacity(0.25), lineWidth: on ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(g.name), \(g.line(me: app.account?.account.id))")
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("invite-group-\(g.id)")
    }

    private func emptyCard<Actions: View>(title: String, text: String, @ViewBuilder actions: () -> Actions) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(Painted.display(20)).foregroundStyle(Painted.paper)
            Text(text).font(.subheadline).foregroundStyle(Painted.paperDim).fixedSize(horizontal: false, vertical: true)
            actions()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Painted.gold.opacity(0.3), lineWidth: 1))
    }

    // MARK: send

    private var pickedFriends: [PlayerCard] { app.friends.friends.filter { picked.contains($0.id) } }
    private var pickedGroup: PlayerGroup? { app.groups.first { $0.id == group } }
    private var canSend: Bool { mode == .friends ? !pickedFriends.isEmpty : pickedGroup != nil }
    private var sendLabel: String {
        switch mode {
        case .friends:
            let f = pickedFriends
            if f.isEmpty { return "Pick friends to invite" }
            return f.count == 1 ? "Invite \(f[0].name)" : "Invite \(f.count) friends"
        case .groups:
            return pickedGroup.map { "Invite \($0.name)" } ?? "Pick a group"
        }
    }

    @ViewBuilder private var sendBar: some View {
        let empty = mode == .friends ? app.friends.friends.isEmpty : app.groups.isEmpty
        if !empty {
            VStack(spacing: 6) {
                Button { Task { await send() } } label: {
                    HStack(spacing: 8) {
                        if sending { ProgressView().tint(Color(hex: 0x2A1A05)) }
                        Text(sendLabel)
                    }
                }
                .buttonStyle(PaintedButtonStyle(kind: .gold))
                .disabled(!canSend || sending)
                .accessibilityIdentifier("invite-send")
                Text("They get an alert, and Join takes them straight to room \(code).")
                    .font(.caption).foregroundStyle(Painted.paperDim).multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20).padding(.bottom, 12)
        }
    }

    private func send() async {
        sending = true
        defer { sending = false }
        let ok: Bool
        switch mode {
        case .friends: ok = await app.invite(game: game, room: code, friends: pickedFriends)
        case .groups:
            guard let g = pickedGroup else { return }
            ok = await app.invite(game: game, room: code, group: g)
        }
        if ok { Haptics.yourTurn(); dismiss() }
    }
}
