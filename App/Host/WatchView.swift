import SwiftUI
import T2PCore

/// Watching a room without playing (#539): the table and the game as the big screen shows it (HostStage), with no hand
/// and no turns. The server sends a watcher either the room's public view or a phone's view marked `spectator`.
struct WatchView: View {
    @ObservedObject var room: RoomModel
    let view: JSON
    var onLeave: () -> Void

    /// The public view HostStage reads: a phone's single `table` becomes the floor's `tables`.
    private var floor: JSON {
        guard room.game == .overdraft, view["tables"].array.isEmpty, case var .object(o) = view, view["table"].object != nil else { return view }
        o["tables"] = .array([view["table"]])
        return .object(o)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Leave", action: onLeave).foregroundStyle(T2P.goldText).accessibilityIdentifier("leave")
                Spacer()
                Text(room.game.title).font(.headline).foregroundStyle(T2P.text)
                Spacer()
                Label("Watching", systemImage: "eye.fill").font(.subheadline.weight(.semibold)).foregroundStyle(T2P.text)
                    .padding(.horizontal, 12).padding(.vertical, 6).background(T2P.panelHi, in: Capsule())
                    .accessibilityIdentifier("watching-chip")
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            ScrollView {
                HostStage(floor: floor, game: room.game, code: room.code)
                    .frame(minHeight: 520)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }
            Text("You’re watching. You’ll see every move; you don’t get a hand or a turn.")
                .font(.footnote).foregroundStyle(T2P.muted).multilineTextAlignment(.center).padding(12)
        }
    }
}
