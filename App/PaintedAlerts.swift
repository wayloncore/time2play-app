import SwiftUI
import UIKit
import T2PCore

/// The app's own painted dialogs (Tyler, Nov 18: "whatever style is applied everywhere"): errors, the account
/// questions, Friends' confirms, the friend link's question, a failed invite. They show in a window of their own over
/// everything (sheets and rooms too), the way an iOS alert does, so any screen can ask one. A room's in-game dialogs
/// keep the room's own host (RoomView), which they had already.
/// The invite banner (an invite that arrives while the app is open) has a window of its own too: a strip at the top,
/// so the screen under it keeps working.
@MainActor
final class AppDialogs {
    static let shared = AppDialogs()
    let dialogs = GameDialogs()
    let banner = BannerState()
    /// What the banner's Join does (the app sets it: open the room, and clear that invite).
    var onJoin: ((String) -> Void)?

    private var dialogWindow: UIWindow?
    private var bannerWindow: UIWindow?
    private weak var mainWindow: UIWindow?
    private var bannerHide: DispatchWorkItem?

    private init() {
        dialogs.onChange = { [weak self] d in
            MainActor.assumeIsolated { self?.dialogChanged(d) }
        }
    }

    func show(_ d: GameDialog) { dialogs.show(d) }

    /// A plain message with one way out ("OK"), painted.
    func say(_ title: String, _ message: String? = nil, ok: String = "OK", identifier: String = "dialog-message-box", then: @escaping () -> Void = {}) {
        show(GameDialog(title: title, message: message, cancel: ok, onCancel: then, identifier: identifier))
    }

    // MARK: the windows

    private func scene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.filter { $0.session.role == .windowApplication }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }

    private func makeWindow<V: View>(_ scene: UIWindowScene, level: UIWindow.Level, _ root: V) -> UIWindow {
        let w = UIWindow(windowScene: scene)
        w.windowLevel = level
        w.backgroundColor = .clear
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        w.rootViewController = host
        return w
    }

    private func dialogChanged(_ d: GameDialog?) {
        if d != nil {
            guard let sc = scene() else { return }
            if dialogWindow == nil { dialogWindow = makeWindow(sc, level: .alert + 1, DialogLayer(dialogs: dialogs)) }
            guard let w = dialogWindow else { return }
            if w.isHidden, let k = sc.keyWindow, k !== w, k !== bannerWindow { mainWindow = k }
            w.isHidden = false
            w.makeKey()   // a dialog's text box needs the keyboard
        } else {
            // after the fade (a choice that opens the next dialog keeps the window up)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.dialogs.current == nil, let w = self.dialogWindow, !w.isHidden else { return }
                    w.isHidden = true
                    self.mainWindow?.makeKey()
                }
            }
        }
    }

    // MARK: the invite banner

    func showBanner(_ n: InviteNote) {
        if banner.note?.room == n.room { return }
        guard let sc = scene() else { return }
        if bannerWindow == nil {
            bannerWindow = makeWindow(sc, level: .alert, BannerLayer(state: banner,
                join: { [weak self] room in MainActor.assumeIsolated { self?.hideBanner(); self?.onJoin?(room) } },
                close: { [weak self] in MainActor.assumeIsolated { self?.hideBanner() } }))
        }
        guard let w = bannerWindow else { return }
        let top = sc.keyWindow?.safeAreaInsets.top ?? 47
        w.frame = CGRect(x: 0, y: 0, width: sc.coordinateSpace.bounds.width, height: top + 132)
        w.isHidden = false   // never key: whatever's being typed under it keeps the keyboard
        banner.note = n
        UIAccessibility.post(notification: .announcement, argument: n.text)
        Haptics.yourTurn()
        bannerHide?.cancel()
        let hide = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.hideBanner() } }
        bannerHide = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: hide)
    }

    func hideBanner() {
        bannerHide?.cancel()
        banner.note = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.banner.note == nil else { return }
                self.bannerWindow?.isHidden = true
            }
        }
    }
}

/// The dialog window's content: the current dialog, painted, or nothing.
private struct DialogLayer: View {
    @ObservedObject var dialogs: GameDialogs
    var body: some View {
        ZStack {
            if let d = dialogs.current {
                GameDialogView(dialog: d, dialogs: dialogs).id(d.id).transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.22), value: dialogs.current?.id)
    }
}

/// An invite that came in while the app is open.
struct InviteNote: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let game: Game?
    let room: String
    var face: Int? = nil
}

@MainActor
final class BannerState: ObservableObject {
    @Published var note: InviteNote?
}

private struct BannerLayer: View {
    @ObservedObject var state: BannerState
    var join: (String) -> Void
    var close: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            if let n = state.note {
                InviteBannerView(note: n, join: { join(n.room) }, close: close)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .frame(maxWidth: .infinity)
        .animation(.spring(duration: 0.35), value: state.note)
    }
}

/// The painted banner: the game's picture, who invited you, and Join.
struct InviteBannerView: View {
    let note: InviteNote
    var join: () -> Void
    var close: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            GameArt(game: note.game)
                .frame(width: 58, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Painted.gold.opacity(0.6), lineWidth: 1))
                .overlay(alignment: .bottomTrailing) {
                    if let f = note.face { FaceView(face: f, size: 24).overlay(Circle().stroke(Painted.faceBottom, lineWidth: 2)).offset(x: 6, y: 6) }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text("INVITE").font(.caption2.weight(.bold)).tracking(1.4).foregroundStyle(Painted.gold)
                Text(note.text).font(.subheadline.weight(.semibold)).foregroundStyle(Painted.paper).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Button("Join", action: join)
                .buttonStyle(PaintedButtonStyle(kind: .gold, wide: false, compact: true))
                .accessibilityIdentifier("banner-join")
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Painted.paperDim)
                    .frame(width: 32, height: 38).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .accessibilityIdentifier("banner-close")
        }
        .padding(.leading, 14).padding(.trailing, 6).padding(.vertical, 12)
        .background(PaintedPanel(corner: 18))
        .frame(maxWidth: 560)
        .gesture(DragGesture(minimumDistance: 12).onEnded { if $0.translation.height < -16 { close() } })
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("invite-banner")
        .environment(\.colorScheme, .dark)
    }
}

// MARK: painted screens (Friends, the invite screen, the game picker)

/// A painted screen's backdrop: the card face's warm near-black and its faint lines.
struct PaintedBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Painted.faceTop, Painted.faceBottom], startPoint: .top, endPoint: .bottom)
            CardLines(opacity: 0.05)
        }
        .accessibilityHidden(true)
    }
}

/// A painted section: a gold-rimmed card with a serif title and a star.
struct PaintedCard<Content: View>: View {
    let title: String
    var footer: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                CardStar().fill(Painted.goldLight).frame(width: 10, height: 10).accessibilityHidden(true)
                Text(title.uppercased()).font(Painted.display(15)).tracking(1.6).foregroundStyle(Painted.titleGold)
                    .accessibilityAddTraits(.isHeader)
            }
            content
            if let f = footer {
                Text(f).font(.footnote).foregroundStyle(Painted.paperDim).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: 0x2B2233), Color(hex: 0x18121E)], startPoint: .top, endPoint: .bottom)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Painted.rim, lineWidth: 1.5))
    }
}

/// A small painted label ("YOURS", "LIVE").
struct PaintedTag: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.caption2.weight(.bold)).tracking(1).foregroundStyle(Painted.goldLight).fixedSize()
            .padding(.horizontal, 6).padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Painted.gold.opacity(0.6), lineWidth: 1))
    }
}

/// A painted round check: gold with a tick when picked, an empty gold ring when not.
struct PaintedCheck: View {
    let on: Bool
    var body: some View {
        ZStack {
            Circle().fill(on ? Painted.gold : Color.clear)
            Circle().strokeBorder(Painted.gold.opacity(on ? 1 : 0.55), lineWidth: 1.5)
            if on { Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(Color(hex: 0x2A1A05)) }
        }
        .frame(width: 26, height: 26)
        .accessibilityHidden(true)
    }
}

/// A painted two-way (or more) switch: Friends | Groups.
struct PaintedTabs<T: Hashable>: View {
    struct Option { let value: T; let label: String; let identifier: String }
    let options: [Option]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options.indices, id: \.self) { i in
                tab(options[i])
            }
        }
        .padding(4)
        .background(Capsule().fill(Color.black.opacity(0.4)))
        .overlay(Capsule().strokeBorder(Painted.gold.opacity(0.55), lineWidth: 1))
    }

    private func tab(_ o: Option) -> some View {
        let on = o.value == selection
        return Button {
            withAnimation(.snappy(duration: 0.2)) { selection = o.value }
            Haptics.select()
        } label: {
            Text(o.label)
                .font(Painted.display(16))
                .foregroundStyle(on ? Color(hex: 0x2A1A05) : Painted.paper)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background {
                    if on {
                        Capsule().fill(LinearGradient(colors: [Color(hex: 0xF8DB94), Painted.gold, Color(hex: 0xB9832C)], startPoint: .top, endPoint: .bottom))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier(o.identifier)
    }
}

/// A round painted icon button (the "…" on a friend or a group).
struct PaintedIconButton: View {
    let icon: String
    let label: String
    let identifier: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 16, weight: .bold)).foregroundStyle(Painted.goldLight)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color.black.opacity(0.35)))
                .overlay(Circle().strokeBorder(Painted.gold.opacity(0.5), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}
