import Foundation

/// The waiting screen's logo (wayloncore/tyleralocke#543): Tyler's 10-second loop of the Time2Play mark plays on the
/// host's waiting screen (the iPad host screen, the TV, the phone lobby) until the game starts. About once a minute the
/// launch intro (#562) plays in place of one pass, then the loop carries on.
public enum WaitingLoopPlan {
    public enum Clip: Equatable, Sendable { case loop, intro }
    /// What the screen shows: nothing, the still mark, or the moving clip.
    public enum Mode: Equatable, Sendable { case hidden, still, moving }

    /// Passes in one cycle; the last one is the intro. Five 10 s loops and the 2.4 s intro: about a minute.
    public static let passesPerCycle = 6

    /// The clip for pass n (0 is the first one the screen shows): the loop, and the intro for every sixth pass.
    public static func clip(forPass n: Int) -> Clip {
        n >= 0 && n % passesPerCycle == passesPerCycle - 1 ? .intro : .loop
    }

    /// Only while the room waits in its lobby (the clip stops the moment the game starts). The setting off hides it;
    /// Reduce Motion and Low Power Mode show the still mark instead of the clip.
    public static func mode(phase: String?, on: Bool, reduceMotion: Bool, lowPower: Bool) -> Mode {
        guard on, (phase ?? "lobby") == "lobby" else { return .hidden }
        return reduceMotion || lowPower ? .still : .moving
    }
}
