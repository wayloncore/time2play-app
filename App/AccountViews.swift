import SwiftUI
import AuthenticationServices
import T2PCore

/// The age question before an account (#385: accounts are for 13 and up). Neutral: no year is picked for you and
/// nothing hints at the answer. Only "13 or older: yes or no" is kept, and only on the server's side as yes.
struct AgeGate: View {
    var onAnswer: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var year: Int?
    @State private var birthdayPassed: Bool?
    private let now = Calendar.current.component(.year, from: Date())

    private var needsMonth: Bool { year.map { now - $0 == 13 } ?? false }
    private var answer: Bool? {
        guard let y = year else { return nil }
        let age = now - y
        if age > 13 { return true }
        if age < 13 { return false }
        return birthdayPassed
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("What year were you born?").font(.headline).foregroundStyle(T2P.text)
                    Picker("Year", selection: $year) {
                        Text("Choose a year").tag(Int?.none)
                        ForEach((now - 100...now - 3).reversed(), id: \.self) { Text(String($0)).tag(Int?.some($0)) }
                    }
                    .pickerStyle(.wheel)
                    .accessibilityIdentifier("birth-year")
                    if needsMonth {
                        Picker("Has your birthday been this year?", selection: $birthdayPassed) {
                            Text("Choose").tag(Bool?.none)
                            Text("Yes").tag(Bool?.some(true))
                            Text("Not yet").tag(Bool?.some(false))
                        }
                    }
                } footer: { Text("We keep only whether you’re 13 or older, never the year.").foregroundStyle(T2P.muted) }
                .listRowBackground(T2P.panel)
                Section {
                    Button("Continue") { if let a = answer { onAnswer(a); dismiss() } }
                        .disabled(answer == nil)
                        .accessibilityIdentifier("age-continue")
                }
                .listRowBackground(T2P.panel)
            }
            .scrollContentBackground(.hidden)
            .background(T2P.navy.ignoresSafeArea())
            .navigationTitle("Before you sign in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

/// Signing in: optional, to keep your name and face, friends, groups and challenges. Guests play everything.
struct SignInPanel: View {
    @EnvironmentObject var app: AppModel
    /// On a painted screen (Friends, the invite screen): paper-and-gold words and a painted Sign in.
    var painted = false
    /// "Save your progress" over it (the invite screen has its own line).
    var heading = true
    @State private var asking = false
    @State private var over13: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if heading {
                Text("Save your progress").font(painted ? Painted.display(19) : .headline).foregroundStyle(painted ? Painted.paper : T2P.text)
            }
            Text("Sign in to add friends, make groups and get invites. You can keep playing as a guest without it.")
                .font(.subheadline).foregroundStyle(painted ? Painted.paperDim : T2P.muted)
                .fixedSize(horizontal: false, vertical: true)
            switch over13 {
            case .some(true):
                SignInWithAppleButton(.signIn) { r in r.requestedScopes = [] } onCompletion: { result in
                    switch result {
                    case let .success(a):
                        if let c = a.credential as? ASAuthorizationAppleIDCredential { Task { await app.signInWithApple(c) } }
                    case let .failure(e):
                        if (e as? ASAuthorizationError)?.code != .canceled {
                            app.accountProblem = "Sign in with Apple didn’t work here. Try again, or keep playing as a guest."
                        }
                    }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 50)
                .accessibilityIdentifier("apple-sign-in")
            case .some(false):
                Label("Accounts are for 13 and up. You can keep playing every game as a guest.", systemImage: "person.fill.checkmark")
                    .foregroundStyle(painted ? Painted.paper : T2P.text).accessibilityIdentifier("under-13")
            case .none:
                if painted {
                    Button("Sign in") { asking = true }.buttonStyle(PaintedButtonStyle(kind: .gold)).accessibilityIdentifier("sign-in")
                } else {
                    Button("Sign in") { asking = true }.buttonStyle(GoldButtonStyle()).accessibilityIdentifier("sign-in")
                }
            }
        }
        .sheet(isPresented: $asking) { AgeGate { over13 = $0 } }
    }
}

/// App Review's sign-in: hidden until the version line is tapped five times (the review notes say how).
struct ReviewSignIn: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Review key", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("review-key")
                    Button("Sign in for review") { Task { await app.signInForReview(key: key.trimmingCharacters(in: .whitespaces)); dismiss() } }
                        .disabled(key.isEmpty).accessibilityIdentifier("review-sign-in")
                } footer: { Text("For App Review. The key is in the review notes.").foregroundStyle(T2P.muted) }
            }
            .navigationTitle("Review sign-in")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

/// You: your name and face, and your account if you have one (sign out, delete account).
struct YouView: View {
    @EnvironmentObject var app: AppModel
    @State private var picking = false
    @State private var taps = 0
    @State private var review = false
    @State private var reporting = false
    @State private var name = ""
    @AppStorage(HandSize.key) private var handSize = HandSize.medium.rawValue

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        if let f = app.profile.face { FaceView(face: f, size: 64) }
                        else { Image(systemName: "person.crop.circle").font(.system(size: 56)).foregroundStyle(T2P.muted) }
                        VStack(alignment: .leading) {
                            HStack(spacing: 8) {
                                Text(app.profile.name.isEmpty ? "Guest" : app.profile.name).font(.title2.bold()).foregroundStyle(T2P.text)
                                    .accessibilityIdentifier("you-name")
                                SupporterStar()   // #598: once you've tipped, kept on this phone
                            }
                            Text(app.signedIn ? (app.account?.kind == "review" ? "Signed in for review" : "Signed in with Apple") : "Playing as a guest")
                                .foregroundStyle(T2P.muted)
                        }
                    }
                    .padding(.vertical, 6)
                    TextField("Your name", text: $name)
                        .textInputAutocapitalization(.words).autocorrectionDisabled()
                        .onSubmit { save() }
                        .accessibilityIdentifier("you-name-field")
                    Button("Change your face") { picking = true }
                } footer: {
                    Text(app.signedIn ? "Friends see this name and face." : "Your name and face stay on this phone. Rooms see them while you play.")
                        .foregroundStyle(T2P.muted)
                }
                .listRowBackground(T2P.panel)

                if app.signedIn {
                    Section {
                        Button("Sign out") { askSignOut() }.accessibilityIdentifier("sign-out")
                        Button("Delete account", role: .destructive) { askDelete() }.accessibilityIdentifier("delete-account")
                    } footer: { Text("Deleting removes your account, friends, groups and invites from Time2Play for good. You can still play as a guest.").foregroundStyle(T2P.muted) }
                    .listRowBackground(T2P.panel)
                } else {
                    Section { SignInPanel() }.listRowBackground(T2P.panel)
                }

                StatsSections()   // #540
                GameCenterSection()   // #541

                // Nov 20 2026: the 3D table is the only one (no Classic table); Card size stays
                Section {
                    Picker("Card size", selection: $handSize) {
                        ForEach(HandSize.allCases) { Text($0.name).tag($0.rawValue) }
                    }
                    .accessibilityIdentifier("card-size")
                } footer: {
                    Text("How big your hand of cards is at the Overdraft table.")
                        .foregroundStyle(T2P.muted)
                }
                .listRowBackground(T2P.panel)

                FeelSection()
                AlertsSection()
                AppIconSection()
                IntroSection()   // #562

                BoardSettingsSection()   // #535

                TipJarSection()   // #598: only when the App Store has the tips
                SupporterSection()
                ReportSection(open: $reporting)   // #594

                Section {
                    Link("Help and support", destination: URL(string: "https://tyleralocke.com/help#app-support")!)
                    Link("Privacy", destination: URL(string: "https://tyleralocke.com/privacy")!)
                } footer: {
                    Text("Time2Play \(AppModel.appVersion) · protocol v\(protocolVersion)")
                        .foregroundStyle(T2P.muted)
                        .onTapGesture { taps += 1; if taps >= 5 { taps = 0; review = true } }
                        .accessibilityIdentifier("version")
                }
                .listRowBackground(T2P.panel)
            }
            .scrollContentBackground(.hidden)
            .background(T2P.navy.ignoresSafeArea())
            .navigationTitle("You")
            .onAppear { name = app.profile.name }
            .onChange(of: app.profile.name) { _, n in name = n }
            .sheet(isPresented: $picking) {
                FacePickerSheet(face: Binding(get: { app.profile.face }, set: { f in
                    app.profile.face = f
                    if app.signedIn { Task { await app.rename(nil, face: f) } }
                }))
            }
            .sheet(isPresented: $review) { ReviewSignIn() }
            .sheet(isPresented: $reporting) { ReportSheet().environmentObject(app) }
        }
    }

    // Sign out and Delete account, painted (Nov 18)
    private func askSignOut() {
        let a = app
        AppDialogs.shared.show(GameDialog(title: "Sign out?", message: "Your friends and groups stay with your account. On this phone you play as a guest until you sign in again.",
                                          choices: [GameChoice(label: "Sign out", kind: .gold, identifier: "confirm-sign-out") { Task { await a.signOut() } }],
                                          cancel: "Stay signed in", identifier: "dialog-sign-out"))
    }

    private func askDelete() {
        let a = app
        AppDialogs.shared.show(GameDialog(title: "Delete your account?", message: "Your account, friends, groups and invites go for good. This can’t be undone.",
                                          choices: [GameChoice(label: "Delete account", kind: .danger, identifier: "confirm-delete-account") { Task { _ = await a.deleteAccount() } }],
                                          cancel: "Keep it", identifier: "dialog-delete-account"))
    }

    private func save() {
        let n = String(name.trimmingCharacters(in: .whitespaces).prefix(12))
        app.profile.name = n
        if app.signedIn, n.count >= 2 { Task { await app.rename(n, face: nil) } }
    }
}


/// Friends (#403), painted (Nov 18): invites at the top with Join, friend requests, your friends (each with Invite),
/// the people you played with, groups (members, Invite, the group's link, Leave or Delete), and your friend link.
/// No search and no directory: every way in starts with someone you already know (#385). The server has no way to
/// edit a group yet (social.js: create, link, leave), so there's no Edit here.
struct FriendsView: View {
    @EnvironmentObject var app: AppModel
    @State private var inviting: PlayerCard?
    @State private var invitingGroup: PlayerGroup?
    @State private var newGroup = false
    /// Your own group, being changed (#575).
    @State private var editingGroup: PlayerGroup?
    @State private var share: ShareItem?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if !app.signedIn {
                        PaintedCard(title: "Play with friends") { SignInPanel(painted: true) }
                    } else {
                        if !app.challenges.isEmpty {
                            PaintedCard(title: "Invites") {
                                ForEach(app.challenges) { ChallengeRow(c: $0, painted: true) }
                            }
                        }
                        if !app.friends.incoming.isEmpty { requests }
                        friendsCard
                        if !app.friends.recent.isEmpty { playedWith }
                        if !app.friends.outgoing.isEmpty {
                            PaintedCard(title: "Waiting for them", footer: "They see your request on their Friends tab.") {
                                ForEach(app.friends.outgoing) { p in
                                    personLine(p) { Text("Asked").font(.subheadline.weight(.semibold)).foregroundStyle(Painted.paperDim) }
                                }
                            }
                        }
                        groupsCard
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 32)
                .frame(maxWidth: 700).frame(maxWidth: .infinity)
            }
            .background(PaintedBackdrop().ignoresSafeArea())
            // a painted band under the status bar, so the list doesn't scroll under the clock
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: 0)
                    .background(LinearGradient(colors: [Painted.faceTop, Painted.faceTop.opacity(0.85)], startPoint: .top, endPoint: .bottom).ignoresSafeArea(edges: .top))
            }
            .environment(\.colorScheme, .dark)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await app.refreshSocial() }
            .task { await app.refreshSocial() }
            .sheet(item: $inviting) { p in
                GamePicker(title: "Invite \(p.name)") { g in Task { await app.challenge(g, to: [p]) } }.environmentObject(app)
            }
            .sheet(item: $invitingGroup) { g in
                GamePicker(title: "Invite \(g.name)") { game in Task { await app.challenge(game, to: [], group: g) } }.environmentObject(app)
            }
            .sheet(isPresented: $newGroup) { NewGroup().environmentObject(app) }
            .sheet(item: $editingGroup) { g in NewGroup(editing: g).environmentObject(app) }
            .sheet(item: $share) { s in ShareSheet(items: [s.url]) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Friends").font(Painted.display(34, .bold)).foregroundStyle(Painted.titleGold).accessibilityAddTraits(.isHeader)
            Text("People you add by link or after a game. Nobody can search for you.")
                .font(.subheadline).foregroundStyle(Painted.paperDim)
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: sections

    private var requests: some View {
        PaintedCard(title: "Friend requests") {
            ForEach(app.friends.incoming) { p in
                personLine(p) {
                    HStack(spacing: 8) {
                        Button("Accept") { Task { await app.social { try await app.api.acceptFriend(p.id) } } }
                            .buttonStyle(PaintedButtonStyle(kind: .gold, wide: false, compact: true))
                            .accessibilityIdentifier("accept-\(p.id)")
                        Button("Decline") { Task { await app.social { try await app.api.declineFriend(p.id) } } }
                            .buttonStyle(PaintedButtonStyle(kind: .quiet, wide: false, compact: true))
                            .accessibilityIdentifier("decline-\(p.id)")
                    }
                }
            }
        }
    }

    private var friendsCard: some View {
        PaintedCard(title: "Friends") {
            if app.friends.friends.isEmpty {
                Text("No friends yet. Send your link, or add people after a game.").font(.subheadline).foregroundStyle(Painted.paperDim)
            }
            ForEach(app.friends.friends) { p in
                personLine(p) {
                    HStack(spacing: 8) {
                        Button("Invite") { inviting = p }
                            .buttonStyle(PaintedButtonStyle(kind: .gold, wide: false, compact: true))
                            .accessibilityLabel("Invite \(p.name)")
                            .accessibilityIdentifier("friend-invite-\(p.id)")
                        PaintedIconButton(icon: "ellipsis", label: "More for \(p.name)", identifier: "friend-more-\(p.id)") { personMenu(p, friend: true) }
                    }
                }
            }
            PaintedDivider().frame(maxWidth: .infinity).padding(.vertical, 2)
            Button { Task { if let u = await app.friendLinkURL() { share = ShareItem(url: u) } } } label: {
                Label("Send your friend link", systemImage: "link")
            }
            .buttonStyle(PaintedButtonStyle(kind: .gold))
            .accessibilityIdentifier("friend-link")
            Text("Anyone who opens your link becomes your friend right away, no request needed. It works for 7 days; after that, send a new one.")
                .font(.footnote).foregroundStyle(Painted.paperDim).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var playedWith: some View {
        PaintedCard(title: "You played with", footer: "Signed-in players from your games in the last 30 days.") {
            ForEach(app.friends.recent) { p in
                personLine(p) {
                    HStack(spacing: 8) {
                        Button("Add friend") { Task { await app.social { try await app.api.requestFriend(p.id) } } }
                            .buttonStyle(PaintedButtonStyle(kind: .gold, wide: false, compact: true))
                            .accessibilityIdentifier("add-friend-\(p.id)")
                        PaintedIconButton(icon: "ellipsis", label: "More for \(p.name)", identifier: "recent-more-\(p.id)") { personMenu(p, friend: false) }
                    }
                }
            }
        }
    }

    private var groupsCard: some View {
        PaintedCard(title: "Groups", footer: app.groups.isEmpty ? "A group is a few friends you invite in one go, like a Thursday crew." : nil) {
            ForEach(app.groups) { g in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(g.name).font(Painted.display(19)).foregroundStyle(Painted.paper).lineLimit(1).minimumScaleFactor(0.8)
                        Spacer(minLength: 4)
                        Button("Invite") { invitingGroup = g }
                            .buttonStyle(PaintedButtonStyle(kind: .gold, wide: false, compact: true))
                            .accessibilityLabel("Invite \(g.name)")
                            .accessibilityIdentifier("group-invite-\(g.id)")
                        PaintedIconButton(icon: "ellipsis", label: "More for \(g.name)", identifier: "group-more-\(g.id)") { groupMenu(g) }
                    }
                    HStack(spacing: 8) {
                        HStack(spacing: -8) {
                            ForEach(g.members.prefix(8)) { m in
                                FaceView(face: m.face, size: 30).overlay(Circle().stroke(Painted.faceBottom, lineWidth: 1.5))
                            }
                        }
                        .accessibilityHidden(true)
                        Spacer(minLength: 4)
                        if g.mine {
                            // #575: your own group: rename it, put friends in, take people out (on the faces' line, so
                            // the name keeps its room)
                            Button("Edit") { editingGroup = g }
                                .buttonStyle(PaintedButtonStyle(kind: .quiet, wide: false, compact: true))
                                .accessibilityLabel("Edit \(g.name)")
                                .accessibilityIdentifier("group-edit-\(g.id)")
                        }
                    }
                    HStack(spacing: 6) {
                        if g.mine { PaintedTag(text: "Yours") }
                        Text(g.line(me: app.account?.account.id)).font(.caption).foregroundStyle(Painted.paperDim)
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.04)))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Painted.gold.opacity(0.25), lineWidth: 1))
            }
            Button { newGroup = true } label: { Label("Make a group", systemImage: "person.3.fill") }
                .buttonStyle(PaintedButtonStyle(kind: .quiet))
                .disabled(app.friends.friends.isEmpty)
                .accessibilityIdentifier("make-group")
            if app.friends.friends.isEmpty {
                Text("Add a friend first, then make a group.").font(.footnote).foregroundStyle(Painted.paperDim)
            }
        }
    }

    private func personLine<Actions: View>(_ p: PlayerCard, @ViewBuilder actions: () -> Actions) -> some View {
        HStack(spacing: 12) {
            FaceView(face: p.face, size: 42)
            Text(p.name).font(Painted.display(18)).foregroundStyle(Painted.paper).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 6)
            actions()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("person-\(p.id)")
    }

    // MARK: painted choices and confirms (Nov 18: no iOS menus, swipes or alerts here)

    private func personMenu(_ p: PlayerCard, friend: Bool) {
        let a = app
        var choices: [GameChoice] = []
        if friend { choices.append(GameChoice(label: "Invite to a game", kind: .gold, identifier: "person-invite") { inviting = p }) }
        else { choices.append(GameChoice(label: "Add friend", kind: .gold, identifier: "person-add") { Task { await a.social { try await a.api.requestFriend(p.id) } } }) }
        if friend { choices.append(GameChoice(label: "Remove friend", kind: .danger, identifier: "person-remove") { confirmRemove(p) }) }
        choices.append(GameChoice(label: "Block", kind: .danger, identifier: "person-block") { confirmBlock(p) })
        choices.append(GameChoice(label: "Report their name", identifier: "person-report") {
            Task {
                await a.social { try await a.api.report(name: p.name, why: "name", account: p.id) }
                AppDialogs.shared.say("Thanks", "Tyler will look at it.", identifier: "dialog-reported")
            }
        })
        AppDialogs.shared.show(GameDialog(title: p.name, choices: choices, cancel: "Back", identifier: "dialog-person"))
    }

    private func confirmRemove(_ p: PlayerCard) {
        let a = app
        AppDialogs.shared.show(GameDialog(title: "Remove \(p.name)?", message: "You stop being friends. You can add each other again later.",
                                          choices: [GameChoice(label: "Remove friend", kind: .danger, identifier: "confirm-remove-friend") {
                                              Task { await a.social { try await a.api.removeFriend(p.id) } }
                                          }],
                                          cancel: "Keep", identifier: "dialog-remove-friend"))
    }

    private func confirmBlock(_ p: PlayerCard) {
        let a = app
        AppDialogs.shared.show(GameDialog(title: "Block \(p.name)?", message: "Neither of you can send the other requests, invites or links, and you won’t see each other in your lists.",
                                          choices: [GameChoice(label: "Block", kind: .danger, identifier: "confirm-block") {
                                              Task { await a.social { try await a.api.block(p.id) } }
                                          }],
                                          cancel: "Cancel", identifier: "dialog-block"))
    }

    private func groupMenu(_ g: PlayerGroup) {
        let a = app
        let leave = g.mine ? "Delete the group" : "Leave the group"
        var choices: [GameChoice] = [GameChoice(label: "Invite to a game", kind: .gold, identifier: "group-invite") { invitingGroup = g }]
        if g.mine { choices.append(GameChoice(label: "Edit the group", icon: "pencil", identifier: "group-edit") { editingGroup = g }) }
        choices.append(GameChoice(label: "Share the group’s link", icon: "link", identifier: "group-link") { Task { await shareGroup(g) } })
        choices.append(GameChoice(label: leave, kind: .danger, identifier: "group-leave") { confirmLeave(g) })
        AppDialogs.shared.show(GameDialog(title: g.name, message: g.line(me: a.account?.account.id),
            choices: choices,
            cancel: "Back", identifier: "dialog-group"))
    }

    private func confirmLeave(_ g: PlayerGroup) {
        let a = app
        AppDialogs.shared.show(GameDialog(
            title: g.mine ? "Delete \(g.name)?" : "Leave \(g.name)?",
            message: g.mine ? "The group goes for everyone in it. Your friendships stay." : "You can come back with the group’s link.",
            choices: [GameChoice(label: g.mine ? "Delete the group" : "Leave the group", kind: .danger, identifier: "confirm-group-leave") {
                Task { await a.social { try await a.api.leaveGroup(g.id) } }
            }],
            cancel: "Keep it", identifier: "dialog-group-leave"))
    }

    private func shareGroup(_ g: PlayerGroup) async {
        if SocialDemo.on { share = ShareItem(url: FriendLink.url("GRP23456")); return }
        do { share = ShareItem(url: FriendLink.url(try await app.api.groupLink(g.id))) }
        catch { AppDialogs.shared.say("Couldn’t make a link", (error as? API.Failure)?.message ?? "Check your signal and try again.") }
    }
}

struct ShareItem: Identifiable { let url: URL; var id: String { url.absoluteString } }

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

/// An invite to a room: the game's picture with the friend's face on it, who sent it, the code, and Join.
struct ChallengeRow: View {
    @EnvironmentObject var app: AppModel
    let c: Challenge
    var painted = false
    var body: some View {
        let when = Date(timeIntervalSince1970: c.created / 1000).formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
        Button { Task { await app.joinChallenge(c) } } label: {
            GameRowLabel(game: c.game, title: c.game?.title ?? "A game", line: "\(c.from.name) invited you",
                         small: "Room \(c.room) · \(when)", action: "Join", face: c.from.face, painted: painted)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(c.from.name) invited you to \(c.game?.title ?? "a game"), room \(c.room). Join")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("join-invite")
    }
}

/// Which game to invite someone to: the four, each with its picture (painted, Nov 18).
struct GamePicker: View {
    let title: String
    var pick: (Game) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title.uppercased()).font(Painted.display(19)).tracking(1.3).foregroundStyle(Painted.titleGold)
                    .lineLimit(1).minimumScaleFactor(0.7).accessibilityAddTraits(.isHeader)
                Spacer()
                PaintedIconButton(icon: "xmark", label: "Cancel", identifier: "picker-cancel") { dismiss() }
            }
            Text("Pick a game. A room starts with you in it, and they get the invite.").font(.subheadline).foregroundStyle(Painted.paperDim)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(Game.allCases.filter(\.challengeable)) { g in
                        Button { dismiss(); pick(g) } label: {
                            GameRowLabel(game: g, title: g.title, line: g.blurb, small: g.players, action: "Invite", painted: true)
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.04)))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Painted.gold.opacity(0.3), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("pick-\(g.rawValue)")
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(PaintedBackdrop().ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground { PaintedBackdrop() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("game-picker")
    }
}

/// Make a group: a name and the friends in it (painted, Nov 18). Anyone else joins by the group's link.
/// #575: the same sheet edits your own group: its name, friends put in, members taken out (one who joined by the
/// link can be taken out, but only friends can be put in).
struct NewGroup: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.dismiss) private var dismiss
    /// The group being changed (nil makes a new one).
    var editing: PlayerGroup? = nil
    @StateObject private var name: DialogField
    @State private var picked: Set<String>

    init(editing: PlayerGroup? = nil) {
        self.editing = editing
        _name = StateObject(wrappedValue: DialogField(editing?.name ?? "", placeholder: "Group name, like Thursday crew", identifier: "group-name"))
        _picked = State(initialValue: Set((editing?.members ?? []).map(\.id)))
    }

    private var myId: String? { app.account?.account.id }
    /// Who can be in it: the group's members (not you), then your friends who aren't.
    private var people: [PlayerCard] {
        let members = (editing?.members ?? []).filter { $0.id != myId }
        let ids = Set(members.map(\.id))
        return members + app.friends.friends.filter { !ids.contains($0.id) }
    }
    private var changes: (name: String?, add: [String], remove: [String]) {
        guard let g = editing else { return (nil, [], []) }
        let was = Set(g.members.map(\.id)).subtracting([myId ?? ""])
        let now = picked.subtracting([myId ?? ""])
        let n = name.trimmed
        return (n == g.name ? nil : n, Array(now.subtracting(was)).sorted(), Array(was.subtracting(now)).sorted())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(editing == nil ? "MAKE A GROUP" : "EDIT GROUP").font(Painted.display(19)).tracking(1.3).foregroundStyle(Painted.titleGold).accessibilityAddTraits(.isHeader)
                Spacer()
                PaintedIconButton(icon: "xmark", label: "Cancel", identifier: "group-cancel") { dismiss() }
            }
            DialogFieldView(field: name)
            Text(editing == nil ? "FRIENDS IN IT" : "WHO’S IN IT").font(.caption.weight(.semibold)).tracking(1.4).foregroundStyle(Painted.paperDim)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(people) { p in
                        let on = picked.contains(p.id)
                        Button { if on { picked.remove(p.id) } else { picked.insert(p.id) }; Haptics.select() } label: {
                            HStack(spacing: 12) {
                                FaceView(face: p.face, size: 40)
                                Text(p.name).font(Painted.display(18)).foregroundStyle(Painted.paper)
                                Spacer()
                                PaintedCheck(on: on)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(on ? Painted.gold.opacity(0.14) : Color.white.opacity(0.04)))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(on ? Painted.gold : Painted.gold.opacity(0.25), lineWidth: on ? 1.5 : 1))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(p.name)
                        .accessibilityAddTraits(on ? .isSelected : [])
                        .accessibilityIdentifier("group-pick-\(p.id)")
                    }
                }
            }
            if let g = editing {
                let c = changes
                Button("Save") {
                    let a = app
                    if SocialDemo.on {
                        // the stand-in groups change in place, so the screen shows it
                        if let i = a.groups.firstIndex(where: { $0.id == g.id }) {
                            a.groups[i].name = c.name ?? g.name
                            let everyone = g.members + a.friends.friends
                            a.groups[i].members = g.members.filter { !c.remove.contains($0.id) } + c.add.compactMap { id in everyone.first { $0.id == id } }
                        }
                    } else {
                        Task { await a.social { try await a.api.editGroup(g.id, name: c.name, add: c.add, remove: c.remove) } }
                    }
                    Haptics.select()
                    dismiss()
                }
                .buttonStyle(PaintedButtonStyle(kind: .gold))
                .disabled(name.trimmed.count < 2 || (c.name == nil && c.add.isEmpty && c.remove.isEmpty))
                .accessibilityIdentifier("group-save")
                Text("Only friends can be put in. Anyone else joins with the group’s link.").font(.caption).foregroundStyle(Painted.paperDim)
            } else {
                Button(picked.isEmpty ? "Make it" : "Make it with \(picked.count) \(picked.count == 1 ? "friend" : "friends")") {
                    let n = name.trimmed, m = Array(picked), a = app
                    Task { await a.social { try await a.api.createGroup(name: n, members: m) } }
                    dismiss()
                }
                .buttonStyle(PaintedButtonStyle(kind: .gold))
                .disabled(name.trimmed.count < 2)
                .accessibilityIdentifier("group-make")
                Text("Anyone else can join with the group’s link, from Groups.").font(.caption).foregroundStyle(Painted.paperDim)
            }
        }
        .padding(20)
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(PaintedBackdrop().ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .presentationBackground { PaintedBackdrop() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(editing == nil ? "new-group" : "edit-group")
    }
}
