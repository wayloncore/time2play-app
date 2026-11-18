import SwiftUI
import T2PCore

/// Game-painted pieces (Tyler, Nov 18: "Make this look like a game option not an apple option"): the choices you make
/// while you play look like part of the game, never an iOS sheet, alert, menu or gray capsule. A dark card-face panel
/// with a gold rim and the cards' corner stars, the game's serif display type, and painted plaques for the choices.
/// Settings screens and account forms keep the system look: they aren't game moments.
enum Painted {
    /// The gold of the cards' frames, light to dark.
    static let goldHi = Color(hex: 0xFFF0C2)
    static let goldLight = Color(hex: 0xF6DFA0)
    static let gold = Color(hex: 0xE9B45A)
    static let goldMid = Color(hex: 0xC8913A)
    static let goldDeep = Color(hex: 0x7A4E16)
    /// Text on the dark panel: warm paper, and a dimmer line under it.
    static let paper = Color(hex: 0xF4EAD5)
    static let paperDim = Color(hex: 0xC9BBA6)
    static let titleGold = Color(hex: 0xF2D79B)
    /// The card face's near-black, a little warm, top to bottom.
    static let faceTop = Color(hex: 0x221B29)
    static let faceBottom = Color(hex: 0x110D16)

    static var rim: LinearGradient {
        LinearGradient(colors: [goldLight, goldMid, goldDeep, gold, goldHi, goldMid], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static var rimRing: AngularGradient {
        AngularGradient(colors: [goldHi, gold, goldDeep, goldMid, goldLight, gold, goldDeep, goldMid, goldHi], center: .center)
    }

    /// The game's display type: the cards' serif ("CHANGE SUIT", "SKIP"), the website's --display.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font { .system(size: size, weight: weight, design: .serif) }
}

/// The four-point star in the cards' corners (and at the middle of the Change Suit card).
struct CardStar: Shape {
    func path(in r: CGRect) -> Path {
        let c = CGPoint(x: r.midX, y: r.midY), w = r.width / 2, h = r.height / 2, k: CGFloat = 0.18
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - h))
        p.addQuadCurve(to: CGPoint(x: c.x + w, y: c.y), control: CGPoint(x: c.x + w * k, y: c.y - h * k))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + h), control: CGPoint(x: c.x + w * k, y: c.y + h * k))
        p.addQuadCurve(to: CGPoint(x: c.x - w, y: c.y), control: CGPoint(x: c.x - w * k, y: c.y + h * k))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - h), control: CGPoint(x: c.x - w * k, y: c.y - h * k))
        p.closeSubpath()
        return p
    }
}

/// The faint arcane lines on every card face: two circles and a cross.
struct CardLines: View {
    var opacity: Double = 0.16
    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2), r = min(size.width, size.height) / 2
            var p = Path()
            p.addEllipse(in: CGRect(x: c.x - r * 0.62, y: c.y - r * 0.62, width: r * 1.24, height: r * 1.24))
            p.addEllipse(in: CGRect(x: c.x - r * 0.9, y: c.y - r * 0.9, width: r * 1.8, height: r * 1.8))
            p.move(to: CGPoint(x: c.x, y: 0)); p.addLine(to: CGPoint(x: c.x, y: size.height))
            p.move(to: CGPoint(x: 0, y: c.y)); p.addLine(to: CGPoint(x: size.width, y: c.y))
            ctx.stroke(p, with: .color(Painted.gold.opacity(opacity)), lineWidth: 0.75)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A gold line with a star in its middle, under a painted title.
struct PaintedDivider: View {
    var body: some View {
        HStack(spacing: 8) {
            LinearGradient(colors: [.clear, Painted.gold.opacity(0.8)], startPoint: .leading, endPoint: .trailing).frame(height: 1)
            CardStar().fill(Painted.goldLight).frame(width: 12, height: 12)
            LinearGradient(colors: [Painted.gold.opacity(0.8), .clear], startPoint: .leading, endPoint: .trailing).frame(height: 1)
        }
        .frame(maxWidth: 220)
        .accessibilityHidden(true)
    }
}

/// The painted panel: a card face in a gold frame, with the cards' corner stars.
struct PaintedPanel: View {
    var corner: CGFloat = 24
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        ZStack {
            shape.fill(LinearGradient(colors: [Painted.faceTop, Painted.faceBottom], startPoint: .top, endPoint: .bottom))
            CardLines(opacity: 0.1).clipShape(shape)
            RoundedRectangle(cornerRadius: max(4, corner - 6), style: .continuous)
                .strokeBorder(Painted.gold.opacity(0.35), lineWidth: 0.75)
                .padding(6)
            GeometryReader { g in
                ForEach(0..<4, id: \.self) { i in
                    CardStar().fill(Painted.goldLight.opacity(0.85))
                        .frame(width: 11, height: 11)
                        .position(x: i % 2 == 0 ? 15 : g.size.width - 15, y: i < 2 ? 15 : g.size.height - 15)
                }
            }
        }
        .overlay(shape.strokeBorder(Painted.rim, lineWidth: 2.5))
        .shadow(color: .black.opacity(0.6), radius: 24, y: 10)
        .accessibilityHidden(true)
    }
}

/// A painted plaque for a choice: gold for the main one, ember for a choice that ends or leaves something, and a dark
/// plaque with a gold edge for the rest.
struct PaintedButtonStyle: ButtonStyle {
    enum Kind { case gold, danger, quiet }
    var kind: Kind = .quiet
    var wide = true
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        configuration.label
            .font(Painted.display(17))
            .tracking(0.3)
            .multilineTextAlignment(.center)
            .foregroundStyle(text)
            .padding(.horizontal, 18)
            .frame(maxWidth: wide ? CGFloat.infinity : nil, minHeight: 52)
            .background(shape.fill(fill))
            .overlay(shape.inset(by: 2).stroke(.white.opacity(kind == .quiet ? 0.06 : 0.28), lineWidth: 1).mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center)))
            .overlay(shape.strokeBorder(kind == .quiet ? AnyShapeStyle(Painted.gold.opacity(0.6)) : AnyShapeStyle(Painted.rim), lineWidth: kind == .quiet ? 1 : 1.5))
            .shadow(color: glow.opacity(configuration.isPressed ? 0.6 : 0.3), radius: configuration.isPressed ? 12 : 6, y: 2)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? 0.06 : 0)
            .opacity(enabled ? 1 : 0.5)
            .contentShape(shape)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var fill: LinearGradient {
        switch kind {
        case .gold: return LinearGradient(colors: [Color(hex: 0xF8DB94), Painted.gold, Color(hex: 0xB9832C)], startPoint: .top, endPoint: .bottom)
        case .danger: return LinearGradient(colors: [Color(hex: 0xF0803F), Color(hex: 0xC8501C), Color(hex: 0x8E2F0C)], startPoint: .top, endPoint: .bottom)
        case .quiet: return LinearGradient(colors: [Color(hex: 0x2C2335), Color(hex: 0x1A1422)], startPoint: .top, endPoint: .bottom)
        }
    }
    private var text: Color {
        switch kind { case .gold: return Color(hex: 0x2A1A05); case .danger: return .white; case .quiet: return Painted.paper }
    }
    private var glow: Color {
        switch kind { case .gold: return Painted.gold; case .danger: return Color(hex: 0xE2662A); case .quiet: return .black }
    }
}

// MARK: dialogs

/// One choice in a painted dialog.
struct GameChoice: Identifiable {
    let id = UUID()
    let label: String
    var kind: PaintedButtonStyle.Kind = .quiet
    var icon: String? = nil
    var identifier: String? = nil
    /// A link to share (Invite people): the plaque opens the share sheet and the dialog stays open behind it.
    var share: URL? = nil
    var action: () -> Void = {}
}

/// A painted dialog: a title, a line under it, small chips (the reactions), the choices, and a way back.
struct GameDialog: Identifiable {
    let id = UUID()
    let title: String
    var message: String? = nil
    var chipsTitle: String? = nil
    var chips: [GameChoice] = []
    var choices: [GameChoice] = []
    /// The way back (also a tap outside the panel); nil: none but a tap outside.
    var cancel: String? = "Cancel"
    var onCancel: () -> Void = {}
    var identifier = "game-dialog"
}

/// The dialogs one screen shows, over everything on it (RoomView and HostView each keep one; the tables find it in
/// the environment).
final class GameDialogs: ObservableObject {
    @Published private(set) var current: GameDialog?
    func show(_ d: GameDialog) { current = d; Haptics.select() }
    func close() { current = nil }
    func cancel() { let d = current; current = nil; d?.onCancel() }
}

private struct GameDialogsKey: EnvironmentKey { static let defaultValue: GameDialogs? = nil }
extension EnvironmentValues {
    /// The screen's painted dialogs (nil in the screenshot stills, which have none).
    var gameDialogs: GameDialogs? {
        get { self[GameDialogsKey.self] }
        set { self[GameDialogsKey.self] = newValue }
    }
}

extension View {
    /// Shows `dialogs` over this view, and hands them to everything inside it.
    func gameDialogHost(_ dialogs: GameDialogs) -> some View { modifier(GameDialogHost(dialogs: dialogs)) }
}

private struct GameDialogHost: ViewModifier {
    @ObservedObject var dialogs: GameDialogs
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .environment(\.gameDialogs, dialogs)
            .overlay {
                ZStack {
                    if let d = dialogs.current {
                        GameDialogView(dialog: d, dialogs: dialogs).id(d.id).transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: reduceMotion ? 0.2 : 0.22), value: dialogs.current?.id)
            }
    }
}

struct GameDialogView: View {
    let dialog: GameDialog
    @ObservedObject var dialogs: GameDialogs
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var hsize
    @State private var shown = false

    var body: some View {
        ZStack {
            Color(hex: 0x07050A).opacity(0.62).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dialogs.cancel() }
                .accessibilityHidden(true)
            ViewThatFits(in: .vertical) {
                panel
                ScrollView { panel }.scrollBounceBehavior(.basedOnSize)
            }
            .frame(maxWidth: hsize == .regular ? 440 : 360)
            .padding(.horizontal, 22)
            .scaleEffect(reduceMotion || shown ? 1 : 0.86)
            .offset(y: reduceMotion || shown ? 0 : 28)
            .opacity(shown ? 1 : 0)
        }
        .onAppear {
            withAnimation(reduceMotion ? Animation.easeOut(duration: 0.2) : Animation.spring(duration: 0.38, bounce: 0.3)) { shown = true }
        }
    }

    private var panel: some View {
        VStack(spacing: 14) {
            Text(dialog.title.uppercased())
                .font(Painted.display(19)).tracking(1.6)
                .foregroundStyle(Painted.titleGold)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            PaintedDivider()
            if let m = dialog.message {
                Text(m).font(.callout).foregroundStyle(Painted.paperDim).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !dialog.chips.isEmpty {
                VStack(spacing: 8) {
                    if let t = dialog.chipsTitle {
                        Text(t.uppercased()).font(.caption.weight(.semibold)).tracking(1.4).foregroundStyle(Painted.paperDim)
                    }
                    HStack(spacing: 8) {
                        ForEach(dialog.chips) { c in
                            Button { dialogs.close(); c.action() } label: { Text(c.label).lineLimit(1).minimumScaleFactor(0.7) }
                                .buttonStyle(PaintedButtonStyle(kind: .quiet))
                                .accessibilityIdentifier(c.identifier ?? c.label)
                        }
                    }
                }
            }
            VStack(spacing: 10) {
                ForEach(dialog.choices) { c in choiceButton(c) }
            }
            if let cancel = dialog.cancel {
                Button(cancel) { dialogs.cancel() }
                    .buttonStyle(PaintedButtonStyle(kind: .quiet))
                    .accessibilityIdentifier("dialog-cancel")
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 24)
        .background(PaintedPanel(corner: 24))
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(dialog.identifier)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { dialogs.cancel() }
    }

    @ViewBuilder private func choiceButton(_ c: GameChoice) -> some View {
        if let url = c.share {
            ShareLink(item: url) { label(c) }
                .buttonStyle(PaintedButtonStyle(kind: c.kind))
                .accessibilityIdentifier(c.identifier ?? c.label)
        } else {
            Button { dialogs.close(); c.action() } label: { label(c) }
                .buttonStyle(PaintedButtonStyle(kind: c.kind))
                .accessibilityLabel(c.label)
                .accessibilityIdentifier(c.identifier ?? c.label)
        }
    }

    @ViewBuilder private func label(_ c: GameChoice) -> some View {
        if let icon = c.icon {
            HStack(spacing: 8) { Image(systemName: icon).font(.system(size: 15, weight: .semibold)); Text(c.label) }
        } else {
            Text(c.label)
        }
    }
}

extension GameDialog {
    /// "End the room for everyone?", from a table's room menu or the host screen.
    static func endRoom(keep: String = "Keep playing", onCancel: @escaping () -> Void = {}, end: @escaping () -> Void) -> GameDialog {
        GameDialog(title: "End the room for everyone?", message: "The game stops for everyone in it.",
                   choices: [GameChoice(label: "End the room", kind: .danger, action: end)], cancel: keep, onCancel: onCancel,
                   identifier: "dialog-end-room")
    }

    /// The room menu over a table: invite, the reactions (the 3D table has no reaction bar), end the room, leave.
    static func roomMenu(room: RoomModel, reactions: Bool, onEnd: @escaping () -> Void, onLeave: (() -> Void)?) -> GameDialog {
        var choices: [GameChoice] = []
        if !room.offline { choices.append(GameChoice(label: "Invite people", icon: "square.and.arrow.up", identifier: "menu-invite", share: room.inviteLink)) }
        if room.isOwner { choices.append(GameChoice(label: "End the room", kind: .danger, identifier: "menu-end-room", action: onEnd)) }
        if let onLeave { choices.append(GameChoice(label: "Leave", kind: .danger, identifier: "menu-leave", action: onLeave)) }
        let chips = reactions ? Reaction.allCases.map { r in
            GameChoice(label: r == .gg ? "GG" : r.words, identifier: "send-\(r.rawValue)") { room.react(r) }
        } : []
        return GameDialog(title: room.offline ? "Practice room" : "Room \(room.code)", chipsTitle: chips.isEmpty ? nil : "Send", chips: chips,
                          choices: choices, cancel: "Back to the game", identifier: "dialog-room-menu")
    }
}
