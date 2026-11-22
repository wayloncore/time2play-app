import SwiftUI
import T2PCore

/// You's settings for the 3D boards (#535): each one's own switch back to the flat version.
/// The options branch's TestFlight test (#708, Nov 22): pick which cinematic option the Overdraft table and the 10000
/// dice use, then open a new game. Not on main: it goes away once Tyler picks one.
struct CinemaTestSection: View {
    @AppStorage(CinemaStyle.settingKey) private var style = CinemaStyle.off.rawValue
    var body: some View {
        Section {
            Picker("Cinematic test", selection: $style) {
                Text("Today (off)").tag(CinemaStyle.off.rawValue)
                Text("A · The director").tag(CinemaStyle.director.rawValue)
                Text("B · The storm").tag(CinemaStyle.storm.rawValue)
                Text("C · Big moments").tag(CinemaStyle.moments.rawValue)
            }
            .tint(T2P.gold)
            .accessibilityIdentifier("picker-cinema-test")
        } header: {
            Text("Cinematic test").foregroundStyle(T2P.muted)
        } footer: {
            Text("Overdraft’s lightning and 10000’s dice. Pick one, then start a new game (Practice is quickest). A: the camera on every Bolt and roll. B: the storm itself, with thunder you feel. C: slow motion only for the big moments.")
                .foregroundStyle(T2P.muted)
        }
        .listRowBackground(T2P.panel)
    }
}

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
