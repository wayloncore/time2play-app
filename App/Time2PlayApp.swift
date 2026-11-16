import SwiftUI
import T2PCore

@main
struct Time2PlayApp: App {
    var body: some Scene {
        WindowGroup { HomeView() }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
    static let t2pNavy = Color(hex: 0x0B1121)
    static let t2pPanel = Color(hex: 0x121A2E)
    static let t2pLine = Color(hex: 0x26324F)
    static let t2pGold = Color(hex: 0xE9B45A)
    static let t2pInk = Color(hex: 0x2A1A05)
    static let t2pText = Color(hex: 0xEEF1F7)
    static let t2pMuted = Color(hex: 0xB8C1D3)
}

struct HomeView: View {
    @State private var code = ""
    private var normalized: String? { RoomCode.normalize(code) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Time2Play")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Color.t2pText)
                    .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Join a game").font(.headline).foregroundStyle(Color.t2pText)
                    TextField("", text: $code, prompt: Text("Room code").foregroundStyle(Color.t2pMuted))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.title2.monospaced().weight(.semibold))
                        .foregroundStyle(Color.t2pText)
                        .padding(14)
                        .background(Color.t2pNavy, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.t2pLine))
                        .accessibilityLabel("Room code")
                        .accessibilityIdentifier("room-code")
                    Button { } label: {
                        Text(normalized.map { "Join \($0)" } ?? "Join")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                    }
                    .foregroundStyle(Color.t2pInk)
                    .background(Color.t2pGold, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("join")
                    .disabled(normalized == nil)
                    .opacity(normalized == nil ? 0.55 : 1)
                }
                .padding(18)
                .background(Color.t2pPanel, in: RoundedRectangle(cornerRadius: 18))

                VStack(alignment: .leading, spacing: 12) {
                    Text("Start a game").font(.headline).foregroundStyle(Color.t2pText)
                    ForEach(["Overdraft", "Hot Dice", "Roll Call"], id: \.self) { name in
                        HStack {
                            Text(name).foregroundStyle(Color.t2pText)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Color.t2pMuted)
                        }
                        .padding(.vertical, 12)
                        .accessibilityElement(children: .combine)
                        Divider().overlay(Color.t2pLine)
                    }
                }
                .padding(18)
                .background(Color.t2pPanel, in: RoundedRectangle(cornerRadius: 18))

                Text("Test build · protocol v\(protocolVersion)")
                    .font(.footnote).foregroundStyle(Color.t2pMuted)
            }
            .padding(20)
        }
        .background(Color.t2pNavy.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}
