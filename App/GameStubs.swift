import SwiftUI
import T2PCore

// The game tables, filled in by #400 (Overdraft) and #401 (Hot Dice); Roll Call and Close Enough follow.
struct OverdraftTableView: View {
    @ObservedObject var room: RoomModel; let view: Overdraft.View; var onLeave: () -> Void
    var body: some View { InPlay(room: room, onLeave: onLeave) }
}
struct HotDiceView: View {
    @ObservedObject var room: RoomModel; let view: HotDice.View; var onLeave: () -> Void
    var body: some View { InPlay(room: room, onLeave: onLeave) }
}
struct RollCallView: View {
    @ObservedObject var room: RoomModel; let view: RollCall.View; var onLeave: () -> Void
    var body: some View { InPlay(room: room, onLeave: onLeave) }
}
struct CloseEnoughView: View {
    @ObservedObject var room: RoomModel; let view: CloseEnough.View; var onLeave: () -> Void
    var body: some View { InPlay(room: room, onLeave: onLeave) }
}
private struct InPlay: View {
    @ObservedObject var room: RoomModel; var onLeave: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Text("\(room.game.title) is on").font(.title2.bold()).foregroundStyle(T2P.text)
            Button("Leave", action: onLeave).buttonStyle(QuietButtonStyle())
        }
    }
}
