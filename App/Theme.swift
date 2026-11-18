import SwiftUI
import UIKit
import T2PCore

/// The Time2Play colors (the join site's, time2play.live), each with its light-mode partner (docs/app/step1, phone.css).
enum T2P {
    static let navy = dyn(0x0B1121, light: 0xF4F1EA)       // the page
    static let navyDeep = dyn(0x070B17, light: 0xE9E4D8)
    static let panel = dyn(0x121A2E, light: 0xFFFFFF)      // a card
    static let panelHi = dyn(0x18223A, light: 0xFBF8F2)
    static let line = dyn(0x26324F, light: 0xDDD6C7)
    static let gold = dyn(0xE9B45A, light: 0xB97A14)       // the one accent
    static let goldText = dyn(0xE9B45A, light: 0x8A5A08)   // gold used as text: darker in light mode for contrast
    static let ink = dyn(0x2A1A05, light: 0xFFFFFF)        // text on gold
    static let text = dyn(0xEEF1F7, light: 0x151B2B)
    static let muted = dyn(0xB8C1D3, light: 0x4C5468)
    static let faint = dyn(0x8A95AD, light: 0x5E6478)
    static let good = dyn(0x5CC88A, light: 0x1E7A45)
    static let ember = Color(hex: 0xE2662A)
    static let suit: [String: Color] = ["ember": Color(hex: 0xE2662A), "wave": Color(hex: 0x2E7FD4),
                                        "bolt": Color(hex: 0x8B5FD6), "leaf": Color(hex: 0x4A9E4E)]
    /// Overdraft's table felt, and Hot Dice's green.
    static let table = Color(hex: 0x17111C)
    static let felt = Color(hex: 0x1F4A3A)

    static func dyn(_ dark: UInt32, light: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .light ? UIColor(hex: light) : UIColor(hex: dark) })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension Color {
    init(hex: UInt32) { self.init(uiColor: UIColor(hex: hex)) }
}

/// The website's own art, bundled in the app: the 47 faces, Overdraft's 55 cards and the logo (App/Art).
enum Art {
    private static let cache = NSCache<NSString, UIImage>()
    static func image(_ name: String) -> UIImage? {
        if let i = cache.object(forKey: name as NSString) { return i }
        guard let path = Bundle.main.path(forResource: name, ofType: "webp"), let i = UIImage(contentsOfFile: path) else { return nil }
        cache.setObject(i, forKey: name as NSString)
        return i
    }
}

/// A player's painted portrait (it carries its own gold ring).
struct FaceView: View {
    let face: Int
    var size: CGFloat = 44
    var dimmed = false
    var body: some View {
        Group {
            if let ui = Art.image(Faces.name(face)) {
                Image(uiImage: ui).resizable().scaledToFill()
            } else {
                Circle().fill(T2P.panelHi).overlay(Text(Faces.label(face).prefix(1)).font(.headline).foregroundStyle(T2P.text))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .opacity(dimmed ? 0.45 : 1)
        .accessibilityHidden(true)
    }
}

struct GoldButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, 16)
            .foregroundStyle(enabled ? T2P.ink : T2P.faint)
            .background(enabled ? T2P.gold : T2P.panelHi, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(enabled ? .clear : T2P.line))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .contentShape(Rectangle())
    }
}

struct QuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(minHeight: 44)
            .padding(.horizontal, 16)
            .foregroundStyle(T2P.text.opacity(enabled ? 1 : 0.45))
            .background(T2P.panelHi, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(T2P.line))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Rectangle())
    }
}

/// A rounded panel, the cards on Play and in lobbies.
struct Panel<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(T2P.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(T2P.line))
    }
}

/// A small label in capitals over a list ("PLAYERS · 4 OF 8").
struct SectionLabel: View {
    let text: String
    var trailing: String? = nil
    var body: some View {
        HStack {
            Text(text.uppercased()).accessibilityAddTraits(.isHeader)
            Spacer()
            if let t = trailing { Text(t.uppercased()) }
        }
        .font(.footnote.weight(.semibold))
        .tracking(1)
        .foregroundStyle(T2P.faint)
        .padding(.horizontal, 6)
    }
}

/// Haptics: a light tap for a play, a firmer one when it's your turn, a warning for a card that can't go.
/// All of them stay quiet when You → "Haptics" is off (App/Feel.swift has the strong jolt and the light tap).
enum Haptics {
    static var on: Bool { FeelSettings.haptics }
    static func play() { if on { UIImpactFeedbackGenerator(style: .light).impactOccurred() } }
    static func yourTurn() { if on { UINotificationFeedbackGenerator().notificationOccurred(.success) } }
    static func nope() { if on { UINotificationFeedbackGenerator().notificationOccurred(.warning) } }
    static func select() { if on { UISelectionFeedbackGenerator().selectionChanged() } }
}

extension Game {
    /// The picture on a game's Start card (system symbols; Overdraft uses its own card art).
    var symbol: String {
        switch self {
        case .overdraft: return "rectangle.stack.fill"
        case .hotDice: return "dice.fill"
        case .rollCall: return "die.face.5.fill"
        case .closeEnough: return "arrow.left.and.right.circle.fill"
        }
    }
    var tint: Color {
        switch self {
        case .overdraft: return Color(hex: 0x2A1A2E)
        case .hotDice: return T2P.felt
        case .rollCall: return Color(hex: 0x3B2B1F)
        case .closeEnough: return Color(hex: 0x17283A)
        }
    }
    /// "3–10 · bots ok"
    var players: String {
        switch self {
        case .overdraft: return "3–10 · bots ok"
        case .hotDice: return "2–8 · bots ok"
        case .rollCall: return "1–8 · solo too"
        case .closeEnough: return "1–8 · solo too"
        }
    }
    var blurb: String {
        switch self {
        case .overdraft: return "Match the suit or the number, and be first to empty your hand."
        case .hotDice: return "Roll six dice, keep what scores, and know when to bank."
        case .rollCall: return "Five dice, three rolls, thirteen boxes to fill."
        case .closeEnough: return "Give a range that holds the answer. Tighter scores more."
        }
    }
    /// The bots the room owner can add: each game's own.
    var bots: [(level: String, name: String)] {
        switch self {
        case .overdraft: return [("easy", "Easy"), ("normal", "Normal")]
        case .hotDice: return HotDice.bots
        case .rollCall: return RollCall.bots
        case .closeEnough: return CloseEnough.bots
        }
    }
    var minPlayers: Int {
        switch self { case .overdraft: return Overdraft.tableMin; case .hotDice: return HotDice.tableMin; default: return 1 }
    }
    var maxPlayers: Int { self == .overdraft ? 10 : 8 }
}
