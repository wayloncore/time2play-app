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
    @State private var asking = false
    @State private var over13: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save your progress").font(.headline).foregroundStyle(T2P.text)
            Text("Sign in to add friends, make groups and get invites. You can keep playing as a guest without it.")
                .font(.subheadline).foregroundStyle(T2P.muted)
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
                    .foregroundStyle(T2P.text).accessibilityIdentifier("under-13")
            case .none:
                Button("Sign in") { asking = true }.buttonStyle(GoldButtonStyle()).accessibilityIdentifier("sign-in")
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
    @State private var confirmDelete = false
    @State private var taps = 0
    @State private var review = false
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        if let f = app.profile.face { FaceView(face: f, size: 64) }
                        else { Image(systemName: "person.crop.circle").font(.system(size: 56)).foregroundStyle(T2P.muted) }
                        VStack(alignment: .leading) {
                            Text(app.profile.name.isEmpty ? "Guest" : app.profile.name).font(.title2.bold()).foregroundStyle(T2P.text)
                                .accessibilityIdentifier("you-name")
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
                        Button("Sign out") { Task { await app.signOut() } }.accessibilityIdentifier("sign-out")
                        Button("Delete account", role: .destructive) { confirmDelete = true }.accessibilityIdentifier("delete-account")
                    } footer: { Text("Deleting removes your account, friends, groups and invites from Time2Play for good. You can still play as a guest.").foregroundStyle(T2P.muted) }
                    .listRowBackground(T2P.panel)
                } else {
                    Section { SignInPanel() }.listRowBackground(T2P.panel)
                }

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
            .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete account", role: .destructive) { Task { _ = await app.deleteAccount() } }
                Button("Keep it", role: .cancel) {}
            } message: { Text("Your account, friends, groups and invites go for good. This can’t be undone.") }
        }
    }

    private func save() {
        let n = String(name.trimmingCharacters(in: .whitespaces).prefix(12))
        app.profile.name = n
        if app.signedIn, n.count >= 2 { Task { await app.rename(n, face: nil) } }
    }
}

/// Friends (#403): invites, requests, friends, people you played with, groups, and your friend link. No search and
/// no directory: every way in starts with someone you already know (#385).
struct FriendsView: View {
    @EnvironmentObject var app: AppModel
    @State private var inviting: PlayerCard?
    @State private var invitingGroup: PlayerGroup?
    @State private var newGroup = false
    @State private var link: URL?

    var body: some View {
        NavigationStack {
            List {
                if !app.signedIn {
                    Section { SignInPanel() }.listRowBackground(T2P.panel)
                } else {
                    if !app.challenges.isEmpty {
                        Section("Invites") { ForEach(app.challenges) { ChallengeRow(c: $0) } }.listRowBackground(T2P.panel)
                    }
                    if !app.friends.incoming.isEmpty {
                        Section("Friend requests") {
                            ForEach(app.friends.incoming) { p in
                                PersonRow(p: p) {
                                    Button("Accept") { Task { await app.social { try await app.api.acceptFriend(p.id) } } }.buttonStyle(.borderless).foregroundStyle(T2P.goldText)
                                    Button("Decline") { Task { await app.social { try await app.api.declineFriend(p.id) } } }.buttonStyle(.borderless).foregroundStyle(T2P.muted)
                                }
                            }
                        }
                        .listRowBackground(T2P.panel)
                    }
                    Section {
                        if app.friends.friends.isEmpty {
                            Text("No friends yet. Send your link, or add people after a game.").foregroundStyle(T2P.muted)
                        }
                        ForEach(app.friends.friends) { p in
                            PersonRow(p: p) {
                                Button("Invite") { inviting = p }.buttonStyle(.borderless).foregroundStyle(T2P.goldText)
                            }
                            .contextMenu { personMenu(p, friend: true) }
                            .swipeActions { Button("Remove", role: .destructive) { Task { await app.social { try await app.api.removeFriend(p.id) } } } }
                        }
                        Button { Task { await shareLink() } } label: { Label("Send your friend link", systemImage: "link") }
                            .accessibilityIdentifier("friend-link")
                    } header: { Text("Friends") }
                    .listRowBackground(T2P.panel)
                    if !app.friends.recent.isEmpty {
                        Section {
                            ForEach(app.friends.recent) { p in
                                PersonRow(p: p) {
                                    Button("Add friend") { Task { await app.social { try await app.api.requestFriend(p.id) } } }.buttonStyle(.borderless).foregroundStyle(T2P.goldText)
                                }
                                .contextMenu { personMenu(p, friend: false) }
                            }
                        } header: { Text("You played with") } footer: { Text("Signed-in players from your games in the last 30 days.").foregroundStyle(T2P.muted) }
                        .listRowBackground(T2P.panel)
                    }
                    if !app.friends.outgoing.isEmpty {
                        Section("Waiting for them") { ForEach(app.friends.outgoing) { PersonRow(p: $0) { EmptyView() } } }.listRowBackground(T2P.panel)
                    }
                    Section {
                        ForEach(app.groups) { g in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(g.name).font(.headline).foregroundStyle(T2P.text)
                                    Spacer()
                                    Button("Invite") { invitingGroup = g }.buttonStyle(.borderless).foregroundStyle(T2P.goldText)
                                }
                                HStack(spacing: -8) { ForEach(g.members.prefix(8)) { FaceView(face: $0.face, size: 28) } }
                                Text("\(g.members.count) people").font(.caption).foregroundStyle(T2P.muted)
                            }
                            .swipeActions { Button(g.mine ? "Delete" : "Leave", role: .destructive) { Task { await app.social { try await app.api.leaveGroup(g.id) } } } }
                            .contextMenu { Button("Share the group’s link") { Task { await shareGroup(g) } } }
                        }
                        Button { newGroup = true } label: { Label("Make a group", systemImage: "person.3") }.disabled(app.friends.friends.isEmpty)
                    } header: { Text("Groups") }
                    .listRowBackground(T2P.panel)
                }
            }
            .scrollContentBackground(.hidden)
            .background(T2P.navy.ignoresSafeArea())
            .navigationTitle("Friends")
            .refreshable { await app.refreshSocial() }
            .task { await app.refreshSocial() }
            .sheet(item: $inviting) { p in GamePicker(title: "Invite \(p.name)") { g in Task { await app.challenge(g, to: [p.id]) } } }
            .sheet(item: $invitingGroup) { g in GamePicker(title: "Invite \(g.name)") { game in Task { await app.challenge(game, to: [], group: g.id) } } }
            .sheet(isPresented: $newGroup) { NewGroup() }
            .sheet(item: Binding(get: { link.map { ShareItem(url: $0) } }, set: { if $0 == nil { link = nil } })) { s in
                ShareSheet(items: [s.url])
            }
        }
    }

    @ViewBuilder private func personMenu(_ p: PlayerCard, friend: Bool) -> some View {
        if friend { Button("Remove friend", role: .destructive) { Task { await app.social { try await app.api.removeFriend(p.id) } } } }
        Button("Block", role: .destructive) { Task { await app.social { try await app.api.block(p.id) } } }
        Button("Report their name") { Task { await app.social { try await app.api.report(name: p.name, why: "name", account: p.id) } } }
    }

    private func shareLink() async {
        do { link = FriendLink.url(try await app.api.friendLink()) }
        catch { app.accountProblem = (error as? API.Failure)?.message ?? "Couldn’t make a link." }
    }
    private func shareGroup(_ g: PlayerGroup) async {
        do { link = FriendLink.url(try await app.api.groupLink(g.id)) }
        catch { app.accountProblem = (error as? API.Failure)?.message ?? "Couldn’t make a link." }
    }
}

struct ShareItem: Identifiable { let url: URL; var id: String { url.absoluteString } }

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct PersonRow<Actions: View>: View {
    let p: PlayerCard
    @ViewBuilder var actions: Actions
    var body: some View {
        HStack(spacing: 12) {
            FaceView(face: p.face, size: 40)
            Text(p.name).font(.headline).foregroundStyle(T2P.text)
            Spacer()
            actions
        }
        .accessibilityElement(children: .contain)
    }
}

struct ChallengeRow: View {
    @EnvironmentObject var app: AppModel
    let c: Challenge
    var body: some View {
        HStack(spacing: 12) {
            FaceView(face: c.from.face, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(c.from.name) invited you to \(c.game?.title ?? "a game")").font(.headline).foregroundStyle(T2P.text)
                Text(Date(timeIntervalSince1970: c.created / 1000), style: .relative).font(.caption).foregroundStyle(T2P.muted)
            }
            Spacer()
            Button("Join") { Task { await app.joinChallenge(c) } }
                .font(.headline).foregroundStyle(T2P.ink).padding(.horizontal, 16).padding(.vertical, 8).background(T2P.gold, in: Capsule())
                .buttonStyle(.borderless)
                .accessibilityIdentifier("join-invite")
        }
        .accessibilityElement(children: .combine)
    }
}

/// Which game to invite someone to (the server's challenge list: Overdraft and Hot Dice).
struct GamePicker: View {
    let title: String
    var pick: (Game) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List(Game.allCases.filter(\.challengeable)) { g in
                Button { dismiss(); pick(g) } label: { LibraryRow(title: g.title, line: g.blurb, detail: g.players, thumb: nil, symbol: g.symbol, tint: g.tint, action: "Invite") }
            }
            .navigationTitle(title)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

struct NewGroup: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var picked: Set<String> = []
    var body: some View {
        NavigationStack {
            Form {
                TextField("Group name (like Thursday crew)", text: $name)
                Section("Friends in it") {
                    ForEach(app.friends.friends) { p in
                        Button { if picked.contains(p.id) { picked.remove(p.id) } else { picked.insert(p.id) } } label: {
                            HStack { PersonRow(p: p) { EmptyView() }; if picked.contains(p.id) { Image(systemName: "checkmark").foregroundStyle(T2P.gold) } }
                        }
                        .accessibilityAddTraits(picked.contains(p.id) ? .isSelected : [])
                    }
                }
            }
            .navigationTitle("Make a group")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Make it") { Task { await app.social { try await app.api.createGroup(name: name, members: Array(picked)) }; dismiss() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).count < 2)
                }
            }
        }
    }
}
