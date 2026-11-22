import SwiftUI
import T2PCore

/// You's settings for the 3D boards (#535): each one's own switch back to the flat version.
struct BoardSettingsSection: View {
    @AppStorage(Boards3D.closeEnough3DKey) private var closeEnough3D = false
    @AppStorage(Boards3D.flatWheelKey) private var flatWheel = false
    var body: some View {
        Section {
            Toggle("3D Close Enough board", isOn: $closeEnough3D).tint(T2P.gold).accessibilityIdentifier("toggle-3d-ce")
            Toggle("Flat wheel", isOn: $flatWheel).tint(T2P.gold).accessibilityIdentifier("toggle-flat-wheel")
        } footer: {
            Text("Close Enough looks like it does on time2play.live; turn on its 3D board to play on that instead. The Wheel of Names spins in 3D; turn on Flat wheel for the flat one.")
                .foregroundStyle(T2P.muted)
        }
        .listRowBackground(T2P.panel)
    }
}
