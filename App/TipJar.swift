import SwiftUI
import StoreKit
import T2PCore

/// The tip jar (wayloncore/tyleralocke#598): three consumable in-app purchases through StoreKit 2 (Tip, Big tip, Huge
/// tip; Tips in T2PCore). They say thanks and unlock nothing: no perks, no ads. Afterward a painted thank-you, and a
/// Supporter star on the player's own You screen, kept on this phone (Tips.countKey, a new key). Apple handles the
/// payment; nothing about it goes to Time2Play's server.
///
/// It shows only when StoreKit returns the products, so before the products exist in App Store Connect (they can't
/// until the Paid Apps agreement is in effect) the Tip jar and its end-of-game line simply aren't there.
/// The simulator uses StoreKit/Time2Play.storekit (the scheme's run options). The UI tests use -t2p-tips-demo: the
/// test build stands in for StoreKit (the command line doesn't load a StoreKit configuration), the same screens.
@MainActor
final class TipJar: ObservableObject {
    static let shared = TipJar()

    struct Tip: Identifiable, Equatable {
        let id: String
        let name: String
        let line: String
        let symbol: String
        let price: String
        static func == (a: Tip, b: Tip) -> Bool { a.id == b.id && a.price == b.price }
    }

    @Published private(set) var tips: [Tip] = []
    @Published private(set) var buying: String?
    /// The tip jar as a sheet (from a game's end screen).
    @Published var sheet = false
    private var products: [String: Product] = [:]
    private var loading = false
    private var listening: Task<Void, Never>?

    var available: Bool { !tips.isEmpty }

    /// The test build's stand-in for StoreKit (-t2p-tips-demo).
    let demo: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-t2p-tips-demo")
        #else
        return false
        #endif
    }()

    private init() {}

    /// Loads the products once (again only if none came back the first time). The app calls it at launch and each time
    /// it comes back to the front, so the Tip jar appears by itself once the products exist.
    func load() async {
        guard tips.isEmpty, !loading else { return }
        loading = true; defer { loading = false }
        if demo {
            tips = Tips.all.map { Tip(id: $0.id, name: $0.name, line: $0.line, symbol: $0.symbol, price: "$" + $0.price) }
            return
        }
        guard let got = try? await Product.products(for: Tips.ids) else { return }
        products = Dictionary(got.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        tips = Tips.all.compactMap { k in
            products[k.id].map { Tip(id: k.id, name: k.name, line: k.line, symbol: k.symbol, price: $0.displayPrice) }
        }
        print("TIPJAR products loaded: \(tips.count)")
    }

    /// Tips that finish later (Ask to Buy, a payment that needed a moment): finished and thanked when they arrive.
    func listen() {
        guard listening == nil, !demo else { return }
        listening = Task.detached {
            for await update in Transaction.updates {
                guard case let .verified(t) = update, Tips.ids.contains(t.productID) else { continue }
                await t.finish()
                await MainActor.run { TipJar.shared.thank() }
            }
        }
    }

    func buy(_ tip: Tip) async {
        guard buying == nil else { return }
        buying = tip.id; defer { buying = nil }
        if demo { try? await Task.sleep(nanoseconds: 300_000_000); thank(); return }
        guard let p = products[tip.id] else { return }
        do {
            switch try await p.purchase() {
            case let .success(.verified(t)):
                await t.finish()
                thank()
            case .success(.unverified(_, _)):
                AppDialogs.shared.say("That tip didn’t go through", "Apple couldn’t confirm it, so nothing was charged as a tip here. Try again later.", identifier: "dialog-tip-problem")
            case .pending:
                AppDialogs.shared.say("Waiting for approval", "Your tip goes through once it’s approved. Thank you!", identifier: "dialog-tip-pending")
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            AppDialogs.shared.say("That tip didn’t go through", "Check your connection and try again.", identifier: "dialog-tip-problem")
        }
    }

    /// The painted thank-you, and one more tip on this phone (the Supporter star).
    func thank() {
        let d = UserDefaults.standard
        d.set(d.integer(forKey: Tips.countKey) + 1, forKey: Tips.countKey)
        Haptics.yourTurn()
        let showsStar = !d.bool(forKey: Tips.hideStarKey)
        AppDialogs.shared.show(GameDialog(
            title: "Thank you!",
            message: "Tips keep Time2Play going: new games, fixes, and no ads, ever." + (showsStar ? " Your Supporter star is on your You screen." : ""),
            cancel: "Back to the games", identifier: "dialog-tip-thanks"))
    }
}

/// You → Tip jar: the three tips, with their prices from the App Store. Hidden when there are none.
struct TipJarSection: View {
    @ObservedObject private var jar = TipJar.shared

    var body: some View {
        Group {
            if jar.available {
                Section {
                    TipButtons()
                } header: {
                    Text("Tip jar")
                } footer: {
                    Text("Enjoying Time2Play? A tip says thanks. It unlocks nothing: every game stays free for everyone. Apple handles the payment.")
                        .foregroundStyle(T2P.muted)
                }
                .listRowBackground(T2P.panel)
            }
        }
    }
}

/// The three tips as rows (the You tab's section and the sheet share them).
struct TipButtons: View {
    @ObservedObject private var jar = TipJar.shared

    var body: some View {
        ForEach(jar.tips) { tip in
            Button { Task { await jar.buy(tip) } } label: {
                HStack(spacing: 12) {
                    Image(systemName: tip.symbol).font(.title3).foregroundStyle(T2P.gold).frame(width: 30)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tip.name).font(.headline).foregroundStyle(T2P.text)
                        Text(tip.line).font(.subheadline).foregroundStyle(T2P.muted)
                    }
                    Spacer(minLength: 8)
                    Group {
                        if jar.buying == tip.id { ProgressView() } else { Text(tip.price).font(.headline.monospacedDigit()) }
                    }
                    .foregroundStyle(T2P.ink)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(T2P.gold, in: Capsule())
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(jar.buying != nil)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(tip.name), \(tip.price)")
            .accessibilityHint(tip.line)
            .accessibilityIdentifier("tip-\(tip.id.split(separator: ".").last ?? "")")
        }
    }
}

/// The tip jar as a sheet, from a game's end screen.
struct TipJarSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TipButtons()
                } footer: {
                    Text("A tip says thanks. It unlocks nothing: every game stays free for everyone. Apple handles the payment.")
                        .foregroundStyle(T2P.muted)
                }
                .listRowBackground(T2P.panel)
            }
            .scrollContentBackground(.hidden)
            .background(T2P.navy.ignoresSafeArea())
            .navigationTitle("Tip jar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("tip-sheet-done") } }
        }
        .presentationDetents([.medium, .large])
    }
}

/// The quiet line on a game's end screen: never during play, never a pop-up. Only when there are tips to give.
struct TipLine: View {
    @ObservedObject private var jar = TipJar.shared
    var body: some View {
        Group {
            if jar.available {
                Button { jar.sheet = true } label: {
                    Label("Enjoying Time2Play? Leave a tip", systemImage: "heart")
                        .font(.footnote).foregroundStyle(Painted.paperDim)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tip-line")
            }
        }
    }
}

/// The Supporter star beside your name on You, once you've tipped (and unless you hid it).
struct SupporterStar: View {
    @AppStorage(Tips.countKey) private var tips = 0
    @AppStorage(Tips.hideStarKey) private var hidden = false
    var body: some View {
        if tips > 0 && !hidden {
            Label("Supporter", systemImage: "star.fill")
                .font(.caption.weight(.bold)).foregroundStyle(T2P.ink)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(T2P.gold, in: Capsule())
                .accessibilityIdentifier("supporter-star")
        }
    }
}

/// You → show or hide the Supporter star (only once you've tipped).
struct SupporterSection: View {
    @AppStorage(Tips.countKey) private var tips = 0
    @AppStorage(Tips.hideStarKey) private var hidden = false
    var body: some View {
        if tips > 0 {
            Section {
                Toggle("Show my Supporter star", isOn: Binding(get: { !hidden }, set: { hidden = !$0 }))
                    .tint(T2P.gold)
                    .accessibilityIdentifier("toggle-supporter-star")
            } footer: {
                Text("Thank you for \(tips == 1 ? "your tip" : "your \(tips) tips"). The star is only on this phone.").foregroundStyle(T2P.muted)
            }
            .listRowBackground(T2P.panel)
        }
    }
}
