import SwiftUI
import T2PCore

/// You's settings for the 3D boards (#535): each one's own switch back to the flat version.
struct BoardSettingsSection: View {
    @AppStorage(Boards3D.flatCloseEnoughKey) private var flatCloseEnough = false
    @AppStorage(Boards3D.flatWheelKey) private var flatWheel = false
    var body: some View {
        Section {
            Toggle("Flat Close Enough board", isOn: $flatCloseEnough).tint(T2P.gold).accessibilityIdentifier("toggle-flat-ce")
            Toggle("Flat wheel", isOn: $flatWheel).tint(T2P.gold).accessibilityIdentifier("toggle-flat-wheel")
        } footer: {
            Text("Close Enough’s answers drop onto a 3D board, and the Wheel of Names spins in 3D. Turn either on for the flat version.")
                .foregroundStyle(T2P.muted)
        }
        .listRowBackground(T2P.panel)
    }
}
