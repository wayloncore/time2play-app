import Foundation
import CoreHaptics

/// #717 (option B, the storm): thunder from one AHAP (App/Sounds/thunder.ahap), so the crack you feel and the rumble
/// you hear come from one pattern and never drift apart: a sharp transient at the return stroke, then the rumble a
/// beat later (sound is slower than light). Its sound, thunder.caf, is Time2Play's own (scripts/thunder.py).
/// Haptics and Sound effects in You are respected: either one off mutes that half of the pattern.
/// A strike far off in the storm is heard quietly and not felt; a Bolt aimed at you is both, in full.
/// No Core Haptics (an iPad, the simulator): the sound alone, through Sounds.
final class Thunder {
    static let shared = Thunder()
    private var engine: CHHapticEngine?
    private var failed = false
    private let queue = DispatchQueue(label: "live.time2play.thunder", qos: .userInitiated)

    /// Thunder for a strike: `near` is a Bolt aimed at you (felt and heard in full), otherwise the storm's own (heard
    /// quietly, not felt). Any thread.
    func play(near: Bool) {
        let haptics = FeelSettings.haptics && near, sound = FeelSettings.sound
        guard haptics || sound else { return }
        let volume: Float = near ? 1 : 0.35
        queue.async { [self] in
            guard let e = engineReady(), let pattern = Self.pattern else {
                if sound { DispatchQueue.main.async { Sounds.shared.play(.thunder, volume: volume) } }
                return
            }
            do {
                e.isMutedForHaptics = !haptics
                e.isMutedForAudio = !sound
                let p = try e.makePlayer(with: pattern)
                try p.sendParameters([CHHapticDynamicParameter(parameterID: .audioVolumeControl, value: volume, relativeTime: 0)],
                                     atTime: CHHapticTimeImmediate)
                try p.start(atTime: CHHapticTimeImmediate)
            } catch {
                if sound { DispatchQueue.main.async { Sounds.shared.play(.thunder, volume: volume) } }
            }
        }
    }

    private func engineReady() -> CHHapticEngine? {
        if let e = engine { return e }
        guard !failed, CHHapticEngine.capabilitiesForHardware().supportsHaptics else { failed = true; return nil }
        do {
            let e = try CHHapticEngine()
            e.playsHapticsOnly = false
            e.isAutoShutdownEnabled = true
            e.resetHandler = { [weak self] in try? self?.engine?.start() }
            try e.start()
            engine = e
            return e
        } catch {
            failed = true
            return nil
        }
    }

    /// thunder.ahap, with its sound file's path made absolute (an AHAP's paths are otherwise read from where the app
    /// was started, not from the bundle).
    static let pattern: CHHapticPattern? = {
        guard let url = Bundle.main.url(forResource: "thunder", withExtension: "ahap"),
              let caf = Bundle.main.url(forResource: "thunder", withExtension: "caf"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var events = json["Pattern"] as? [[String: Any]] else { return nil }
        for i in events.indices {
            guard var ev = events[i]["Event"] as? [String: Any], ev["EventWaveformPath"] != nil else { continue }
            ev["EventWaveformPath"] = caf.path
            events[i]["Event"] = ev
        }
        var dict: [CHHapticPattern.Key: Any] = [:]
        for (k, v) in json { dict[CHHapticPattern.Key(rawValue: k)] = v }
        dict[CHHapticPattern.Key(rawValue: "Pattern")] = events
        return try? CHHapticPattern(dictionary: dict)
    }()
}
