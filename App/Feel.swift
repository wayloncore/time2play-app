import SwiftUI
import AVFoundation
import T2PCore

/// The game's feel: haptics, sound effects and the optional background music, each with its own switch in You.
/// Saved settings (UserDefaults): new keys only, and a missing key reads as the default, so the version before
/// (which has none of them) and this one never disagree about anything already saved.
enum FeelSettings {
    /// "Haptics": on unless turned off.
    static let hapticsKey = "t2p.haptics"
    /// "Sound effects": on unless turned off.
    static let soundKey = "t2p.sound"
    /// "Music": off unless turned on.
    static let musicKey = "t2p.music"
    static var all: [String] { [hapticsKey, soundKey, musicKey] }

    static func flag(_ key: String, default d: Bool) -> Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? d }
    static var haptics: Bool { flag(hapticsKey, default: true) }
    static var sound: Bool { flag(soundKey, default: true) }
    static var music: Bool { flag(musicKey, default: false) }
}

extension Haptics {
    /// A strong jolt: a Bolt (+2 or +4) aimed at you, or your Farkle. Two hits close together, so it's felt.
    static func jolt() {
        guard on else { return }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 1) }
    }
    /// A light tap: a Buzzer press that counted, or a die you kept.
    static func light() {
        guard on else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.7)
    }
}

/// One place that turns what happened in a game into a sound and a haptic. The screens call the dice moments (they
/// wait for the dice to land); everything else comes from the room's views (RoomModel, FeelEvents in Core).
/// Called on the main thread (the 3D dice hop there before they call back).
enum Feel {
    static func events(_ list: [FeelEvent]) {
        for e in list {
            switch e {
            case .yourTurn: Sounds.shared.play(.yourTurn)          // the screens already tap for your turn
            case .cardPlayed: Sounds.shared.play(.cardPlay, volume: 0.8)
            case .drew: Sounds.shared.play(.draw)
            case .bolt: Haptics.jolt(); Sounds.shared.play(.bolt)
            case .diceRolled: Sounds.shared.play(.diceRoll)
            case .won: Sounds.shared.play(.win)                    // the end screens already tap for a win
            }
        }
    }

    /// Dice came to rest (the flat dice's tumble ended, or the 3D dice hit the felt).
    static func landed(mine: Bool = true) {
        if mine { Haptics.play() }
        Sounds.shared.play(.diceLand, volume: mine ? 1 : 0.7)
    }

    /// A Farkle, once its dice can be seen: the sound for anyone's, the jolt for yours.
    static func farkle(mine: Bool) {
        if mine { Haptics.jolt() }
        Sounds.shared.play(.farkle, volume: mine ? 1 : 0.6)
    }

    /// A Buzzer press that counted (for the Buzzer games, when the app plays them).
    static func buzzerCounted() { Haptics.light() }

    /// A die you kept.
    static func kept() { Haptics.light() }
}

/// The sound effects, small files in App/Sounds: recorded ones (.caf, from free CC0 packs, scripts/recorded-sounds.py)
/// and any still synthesized (.wav, scripts/sounds.py). App/Sounds/LICENSES.md says where each comes from.
/// The audio session is "ambient": the silent switch silences them, and they mix with whatever else is playing.
final class Sounds: ObservableObject {
    static let shared = Sounds()
    enum Effect: String, CaseIterable {
        case cardPlay = "card-play", draw, yourTurn = "your-turn", diceRoll = "dice-roll", diceLand = "dice-land"
        case farkle, win, bolt
    }

    private var data: [Effect: Data] = [:]
    private var playing: [AVAudioPlayer] = []
    private var lastPlayed: [Effect: Date] = [:]
    private var sessionReady = false

    /// UI tests can say which sounds played (-t2p-sound-log), since a simulator run can't listen.
    @Published private(set) var log: [String] = []
    static let logging = ProcessInfo.processInfo.arguments.contains("-t2p-sound-log")

    static func prepareSession() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    /// Called on the main thread; the audio itself starts on its own queue, so a slow audio start-up (the first
    /// sound wakes the audio session) never holds up the screen.
    func play(_ e: Effect, volume: Float = 1) {
        guard FeelSettings.sound else { return }
        let now = Date()
        // one of each at a time: three dice landing together are one clack, not three
        if let t = lastPlayed[e], now.timeIntervalSince(t) < 0.08 { return }
        lastPlayed[e] = now
        if Sounds.logging { log.append(e.rawValue) }
        audio.async { [self] in
            if !sessionReady { Sounds.prepareSession(); sessionReady = true }
            guard let d = file(e), let p = try? AVAudioPlayer(data: d) else { report("load:\(e.rawValue)"); return }
            p.volume = volume
            playing.removeAll { !$0.isPlaying }
            playing.append(p)
            if !p.play() { report("play:\(e.rawValue)") }
        }
    }

    /// UI tests: a sound that wouldn't open or start (-t2p-sound-log only).
    @Published private(set) var failed: [String] = []
    private func report(_ s: String) {
        guard Sounds.logging else { return }
        DispatchQueue.main.async { self.failed.append(s) }
    }

    /// A recorded effect is a .caf (scripts/recorded-sounds.py); one still synthesized is a .wav (scripts/sounds.py).
    static func url(_ e: Effect) -> URL? {
        Bundle.main.url(forResource: e.rawValue, withExtension: "caf") ?? Bundle.main.url(forResource: e.rawValue, withExtension: "wav")
    }

    /// UI tests: whether every effect's file is there and opens ("ok", or the ones that don't), checked once.
    static let fileCheck: String = {
        let bad = Effect.allCases.filter { e in
            guard let u = url(e), let d = try? Data(contentsOf: u), let p = try? AVAudioPlayer(data: d) else { return true }
            return !p.prepareToPlay() || p.duration < 0.02
        }
        return bad.isEmpty ? "ok" : bad.map(\.rawValue).joined(separator: ",")
    }()

    /// The audio queue's: the loaded files, the players still sounding, whether the session is set up.
    private let audio = DispatchQueue(label: "live.time2play.sounds", qos: .userInitiated)

    private func file(_ e: Effect) -> Data? {
        if let d = data[e] { return d }
        guard let url = Sounds.url(e), let d = try? Data(contentsOf: url) else { return nil }
        data[e] = d
        return d
    }
}

/// The background music: one quiet, original loop (scripts/sounds.py), only while you're in a room, and only when
/// "Music" is on. Off by default. It loops without a gap (decoded once, played as a looping buffer). Main thread only.
final class Music {
    static let shared = Music()
    private var engine: AVAudioEngine?
    private var node: AVAudioPlayerNode?
    private var buffer: AVAudioPCMBuffer?
    private var observer: NSObjectProtocol?
    private(set) var isPlaying = false
    static let volume: Float = 0.35

    func start() {
        guard FeelSettings.music, !isPlaying else { return }
        Sounds.prepareSession()
        if buffer == nil {
            guard let url = Bundle.main.url(forResource: "music", withExtension: "m4a"), let f = try? AVAudioFile(forReading: url),
                  let b = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length)),
                  (try? f.read(into: b)) != nil else { return }
            buffer = b
        }
        guard let b = buffer else { return }
        let e = AVAudioEngine(), n = AVAudioPlayerNode()
        e.attach(n)
        e.connect(n, to: e.mainMixerNode, format: b.format)
        n.volume = Music.volume
        do { try e.start() } catch { return }
        n.scheduleBuffer(b, at: nil, options: .loops)
        n.play()
        engine = e; node = n; isPlaying = true
        // a call, headphones out, Bluetooth: the engine stops itself; start it again where it was
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: e, queue: .main) { _ in
            Music.shared.restart()
        }
    }

    func stop() {
        node?.stop(); engine?.stop()
        if let o = observer { NotificationCenter.default.removeObserver(o) }
        engine = nil; node = nil; observer = nil; isPlaying = false
    }

    /// Back from the background (or a call): the system may have stopped the engine.
    func resumeIfStopped() {
        guard isPlaying, engine?.isRunning != true else { return }
        restart()
    }

    private func restart() {
        guard isPlaying else { return }
        stop(); start()
    }
}

/// The sounds a room has played, as an invisible line a UI test reads (-t2p-sound-log only).
struct SoundLog: View {
    @ObservedObject var sounds = Sounds.shared
    var body: some View {
        VStack(spacing: 0) {
            Text(sounds.log.joined(separator: ","))
                .accessibilityIdentifier("sound-log")
                .accessibilityLabel(sounds.log.isEmpty ? "none" : sounds.log.joined(separator: ","))
            // every effect's file opens, and any sound that wouldn't open or start
            Text("files")
                .accessibilityIdentifier("sound-files")
                .accessibilityLabel(Sounds.fileCheck)
            Text("failed")
                .accessibilityIdentifier("sound-failed")
                .accessibilityLabel(sounds.failed.isEmpty ? "none" : sounds.failed.joined(separator: ","))
        }
        .font(.system(size: 1)).opacity(0.02)
        .allowsHitTesting(false)
    }
}
