import SwiftUI
import AVFoundation
import UIKit
import T2PCore

/// You → "Logo when you join a room". Saved settings: a new key only, and a missing key reads as on, so the version
/// before (which has no join logo) and this one never disagree about anything already saved.
enum JoinIntroSettings {
    static let key = "t2p.joinIntro"
    static var on: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
}

/// The logo as a joined room opens (wayloncore/tyleralocke#596): when you join someone's room by its code, its link or
/// an invite, the launch intro's clip (App/Intro/intro.mp4, 2.4 s, no sound) plays once over the room as it opens,
/// then cross-fades into it; a tap skips it. The room connects underneath while it plays. Starting your own room,
/// practice offline, and coming back to a seat you hold (a "your turn" alert, Recent rooms) go straight in
/// (JoinIntroPlan). Reduce Motion shows the finished mark, still, for a moment instead. The lobby's own looping logo
/// (WaitingLoop.swift, #543) carries on from there while the room waits.
/// Tests: the UI tests leave it off unless they ask for it (-t2p-join-intro); -t2p-join-freeze <seconds> stops the clip
/// at a moment for screenshots; -t2p-reduce-motion acts as if Reduce Motion is on.
final class JoinIntro: ObservableObject {
    static let shared = JoinIntro()

    @Published private(set) var showing = false
    @Published private(set) var stillShown = false
    /// How it leaves: the cross-fade's length, or nil for at once (the room closed).
    private(set) var leaveFade: Double? = Intro.fade
    private(set) var reduced = false
    private(set) var player: AVPlayer?
    let freezeAt: Double?
    private let testing: Bool
    private let asked: Bool
    private var round = 0
    private var started = false
    private var observers: [NSObjectProtocol] = []
    private var readyWatch: NSKeyValueObservation?

    private init() {
        let args = ProcessInfo.processInfo.arguments
        testing = args.contains("-uitest-reset")
        asked = args.contains("-t2p-join-intro")
        if let i = args.firstIndex(of: "-t2p-join-freeze"), i + 1 < args.count { freezeAt = Double(args[i + 1]) } else { freezeAt = nil }
    }

    /// Whether this phone plays it at all (the setting, and the UI tests' own switch).
    var wanted: Bool {
        guard Bundle.main.url(forResource: "intro", withExtension: "mp4") != nil else { return false }
        return testing ? asked : JoinIntroSettings.on
    }

    /// A room is opening: plays the logo over it if this is a join (JoinIntroPlan).
    func roomOpening(starting: Bool, offline: Bool, returning: Bool) {
        guard JoinIntroPlan.plays(on: wanted, starting: starting, offline: offline, returning: returning) else { skip(); return }
        stop()
        round += 1
        started = false
        reduced = UIAccessibility.isReduceMotionEnabled || ProcessInfo.processInfo.arguments.contains("-t2p-reduce-motion")
        leaveFade = Intro.fade
        stillShown = false
        showing = true
    }

    /// Called once the cover is on screen (the room's own screen is under it).
    func start() {
        guard showing, !started else { return }
        started = true
        let r = round
        if reduced {
            stillShown = true
            if freezeAt == nil { DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { if self.round == r { self.finish(fade: 0.3) } } }
            return
        }
        guard let url = Bundle.main.url(forResource: "intro", withExtension: "mp4") else { skip(); return }
        // no sound, and ambient never stops someone's music (the clip has no audio track anyway)
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        p.isMuted = true
        p.actionAtItemEnd = .pause
        p.preventsDisplaySleepDuringVideoPlayback = false
        player = p
        objectWillChange.send()
        if let at = freezeAt {
            readyWatch = item.observe(\.status, options: [.initial, .new]) { [weak p] item, _ in
                guard item.status == .readyToPlay else { return }
                DispatchQueue.main.async { p?.seek(to: CMTime(seconds: at, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) }
            }
            return
        }
        observers.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            if self?.round == r { self?.finish() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            if self?.round == r { self?.finish(fade: Intro.tapFade) }
        })
        p.play()
        // never longer than this, whatever the player does
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { if self.round == r { self.finish() } }
    }

    /// The clip ended, or a tap: cross-fade into the room.
    func finish(fade: Double = Intro.fade) {
        guard showing, freezeAt == nil else { return }
        leaveFade = fade
        showing = false
        let r = round
        DispatchQueue.main.asyncAfter(deadline: .now() + fade + 0.1) { if self.round == r { self.stop() } }
    }

    /// The room closed (or this open isn't a join): gone at once.
    func skip() {
        guard Thread.isMainThread else { DispatchQueue.main.async { self.skip() }; return }
        guard showing else { return }
        leaveFade = nil
        showing = false
        stop()
    }

    private func stop() {
        player?.pause()
        player = nil
        readyWatch = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
    }
}

/// Over the room while the join logo plays: the clip at its own shape on its navy (on an iPad, in the middle).
struct JoinIntroOverlay: View {
    @ObservedObject var intro = JoinIntro.shared

    var body: some View {
        ZStack {
            if intro.showing { cover.transition(.opacity) }
        }
        .ignoresSafeArea()
        .animation(intro.leaveFade.map { Animation.easeInOut(duration: $0) }, value: intro.showing)
    }

    private var cover: some View {
        ZStack {
            Color(uiColor: Intro.navy)
            if intro.reduced {
                ZStack {
                    if intro.stillShown, let ui = IntroOverlay.still {
                        Image(uiImage: ui).resizable().scaledToFit().transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.25), value: intro.stillShown)
            } else {
                IntroPlayer(player: intro.player)
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { intro.finish(fade: Intro.tapFade) }
        .onAppear { intro.start() }
        .accessibilityElement()
        .accessibilityLabel("Time2Play")
        .accessibilityValue(intro.reduced ? "still" : "playing")
        .accessibilityHint("Tap to skip")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("join-intro")
    }
}
