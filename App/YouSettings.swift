import SwiftUI
import UserNotifications
import T2PCore

/// "Alerts for my turn" (wayloncore/tyleralocke#534): the server sends "Your turn in Overdraft" when your turn comes
/// and the app isn't open. Off unless turned on; the app tells the server with its push token. Until the server sends
/// them, nothing arrives, and nothing breaks.
enum TurnAlerts {
    static let key = "t2p.turnAlerts"
    static var on: Bool { UserDefaults.standard.bool(forKey: key) }
}

/// The app icons you can pick in You (App/Assets.xcassets: AppIcon and the AppIcon-… sets). Each is the Time2Play
/// mark, the gold 2 in its ring, on its own background (scripts/icons.py). nil is the usual icon.
enum AppIcons {
    struct Choice: Identifiable { let id: String?; let name: String; let preview: String }
    static let all: [Choice] = [
        Choice(id: nil, name: "Navy", preview: "icon-navy"),
        Choice(id: "AppIcon-Midnight", name: "Midnight", preview: "icon-midnight"),
        Choice(id: "AppIcon-Felt", name: "Felt", preview: "icon-felt"),
        Choice(id: "AppIcon-Plum", name: "Plum", preview: "icon-plum"),
        Choice(id: "AppIcon-Gold", name: "Gold", preview: "icon-gold"),
    ]
}

/// You → Game feel: haptics, sound effects and music, each on its own.
struct FeelSection: View {
    @AppStorage(FeelSettings.hapticsKey) private var haptics = true
    @AppStorage(FeelSettings.soundKey) private var sound = true
    @AppStorage(FeelSettings.musicKey) private var music = false

    var body: some View {
        Section {
            Toggle("Haptics", isOn: $haptics)
                .onChange(of: haptics) { _, on in if on { Haptics.yourTurn() } }
                .accessibilityIdentifier("toggle-haptics")
            Toggle("Sound effects", isOn: $sound)
                .onChange(of: sound) { _, on in if on { Sounds.shared.play(.yourTurn) } }   // a taste of what they sound like
                .accessibilityIdentifier("toggle-sound")
            Toggle("Music", isOn: $music)
                .accessibilityIdentifier("toggle-music")
        } header: {
            Text("Game feel")
        } footer: {
            Text("Music is a quiet loop while you’re in a room. Sounds and music follow your phone’s silent switch.")
                .foregroundStyle(T2P.muted)
        }
        .tint(T2P.gold)
        .listRowBackground(T2P.panel)
    }
}

/// You → Classic dice: the flat dice instead of the 3D ones (#521), the way Classic table works for Overdraft. Since
/// Nov 20 it's 10,000's only: Yacht Dice always rolls its dice in place.
struct DiceSection: View {
    @AppStorage(Dice3DSwitch.key) private var dice3D = false
    @AppStorage(Dice3DSwitch.classicKey) private var classicDice = false

    var body: some View {
        Section {
            Toggle("Classic dice", isOn: $classicDice)
                .tint(T2P.gold)
                .onChange(of: classicDice) { _, c in dice3D = !c }   // the old key, kept in step for the version before
                .accessibilityIdentifier("toggle-classic-dice")
        } footer: {
            Text("Rolls 10,000 with the flat dice instead of the 3D ones. Yacht Dice always rolls its dice in place.").foregroundStyle(T2P.muted)
        }
        .listRowBackground(T2P.panel)
    }
}

/// You → App icon: the Time2Play mark on a few backgrounds.
struct AppIconSection: View {
    @State private var current: String? = UIApplication.shared.alternateIconName
    @State private var problem: String?

    var body: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(AppIcons.all) { c in
                        Button { pick(c.id) } label: {
                            VStack(spacing: 6) {
                                Group {
                                    if let img = UIImage(named: c.preview) { Image(uiImage: img).resizable() }
                                    else { RoundedRectangle(cornerRadius: 14).fill(T2P.panelHi) }
                                }
                                .frame(width: 54, height: 54)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(current == c.id ? T2P.gold : .clear, lineWidth: 3).padding(-3))
                                Text(c.name).font(.caption.weight(current == c.id ? .bold : .regular))
                                    .foregroundStyle(current == c.id ? T2P.text : T2P.muted)
                            }
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(c.name) icon")
                        .accessibilityAddTraits(current == c.id ? .isSelected : [])
                        .accessibilityIdentifier("icon-\(c.name.lowercased())")
                    }
                }
                .padding(.horizontal, 4)
            }
        } header: {
            Text("App icon")
        } footer: {
            if let p = problem { Text(p).foregroundStyle(T2P.muted) }
        }
        .listRowBackground(T2P.panel)
    }

    private func pick(_ id: String?) {
        guard UIApplication.shared.supportsAlternateIcons, id != current else { return }
        Haptics.select()
        UIApplication.shared.setAlternateIconName(id) { error in
            DispatchQueue.main.async {
                if error == nil { current = id; problem = nil } else { problem = "The icon didn’t change. Try again in a moment." }
            }
        }
    }
}

/// You → Alerts: invite alerts (on once you allow notifications) and "Alerts for my turn".
struct AlertsSection: View {
    @EnvironmentObject var app: AppModel
    @AppStorage(TurnAlerts.key) private var turnAlerts = false
    @State private var allowed: UNAuthorizationStatus = .notDetermined
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            HStack {
                Text("Invite alerts")
                Spacer()
                Text(inviteState).foregroundStyle(T2P.muted)
            }
            .accessibilityElement(children: .combine)
            Toggle("Alerts for my turn", isOn: $turnAlerts)
                .tint(T2P.gold)
                .disabled(!app.signedIn)
                .onChange(of: turnAlerts) { _, on in Task { await app.turnAlertsChanged(on) ; await check() } }
                .accessibilityIdentifier("toggle-turn-alerts")
            if app.signedIn && allowed == .denied, let u = URL(string: UIApplication.openSettingsURLString) {
                Button("Turn on notifications in Settings") { openURL(u) }.foregroundStyle(T2P.goldText)
            }
        } header: {
            Text("Alerts")
        } footer: {
            Text(app.signedIn ? "Your turn, when the app is closed: “Your turn in 10,000.” Tapping it opens the room. Never for practice games."
                 : "Alerts are for signed-in players. Sign in above to get invites and turn alerts.")
                .foregroundStyle(T2P.muted)
        }
        .listRowBackground(T2P.panel)
        .task { await check() }
    }

    private var inviteState: String {
        guard app.signedIn else { return "Sign in first" }
        switch allowed {
        case .authorized, .provisional, .ephemeral: return "On"
        case .denied: return "Off in Settings"
        default: return "Off"
        }
    }

    private func check() async { allowed = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
}
