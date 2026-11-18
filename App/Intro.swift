import SwiftUI
import AVFoundation
import UIKit

/// You → "Intro at launch". Saved settings: a new key only, and a missing key reads as on, so the version before
/// (which has no intro) and this one never disagree about anything already saved.
enum IntroSettings {
    static let key = "t2p.intro"
    static var on: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
}

/// The intro at launch (wayloncore/tyleralocke#562): Tyler's clip of the Time2Play mark (App/Intro/intro.mp4), played
/// once on a fresh launch over the Play screen, then cross-faded away. It never stands between a player and a game:
/// a launch from a link, a QR scan, an invite, an alert or the widget skips it, and anything that opens a room ends it.
/// The app underneath starts as usual while it plays (its connections and loading don't wait for it).
///
/// The clip: Tyler's 3.0 s video with 3 frames of empty navy trimmed from the start and the 7 still frames from the end,
/// the motion (the 2's bouncy pop included) sped up 1.25x (every frame kept, 30 fps), then the finished mark held
/// 0.25 s: 2.37 s in all, 2.1 s of motion. No sound (the video's audio track is stripped).
/// Tests: the UI tests turn it off unless they ask for it (-t2p-intro); -t2p-intro-freeze <seconds> stops it at a moment
/// for screenshots; -t2p-reduce-motion acts as if Reduce Motion is on.
final class Intro: ObservableObject {
    static let shared = Intro()

    /// The clip's first-frame navy (#00071F), the launch screen's color too (LaunchNavy). The app's own navy is
    /// #0B1121, a shade lighter; the clip's is used here so launch, the clip and its letterbox bars are one color.
    static let navy = UIColor(named: "LaunchNavy") ?? UIColor(red: 0, green: 7 / 255, blue: 31 / 255, alpha: 1)

    @Published private(set) var showing: Bool
    /// How the intro leaves: the cross-fade's length, or nil for at once (a link).
    private(set) var leaveFade: Double? = Intro.fade
    /// The final mark, shown for Reduce Motion (it fades in, holds, then fades to Play).
    @Published private(set) var stillShown = false
    let reduced: Bool
    let freezeAt: Double?
    private(set) var player: AVPlayer?
    private var started = false
    private var leaving = false
    private var observers: [NSObjectProtocol] = []
    private var readyWatch: NSKeyValueObservation?

    /// How long the cross-fade into Play takes, and a tap's quicker one.
    static let fade = 0.35
    static let tapFade = 0.2

    private init() {
        let args = ProcessInfo.processInfo.arguments
        let testing = args.contains("-uitest-reset")
        let wanted = testing ? args.contains("-t2p-intro") : IntroSettings.on
        let hasClip = Bundle.main.url(forResource: "intro", withExtension: "mp4") != nil
        showing = wanted && hasClip
        reduced = UIAccessibility.isReduceMotionEnabled || args.contains("-t2p-reduce-motion")
        if let i = args.firstIndex(of: "-t2p-intro-freeze"), i + 1 < args.count { freezeAt = Double(args[i + 1]) } else { freezeAt = nil }
    }

    /// The app opened from a link, an alert or the widget, or a room is opening: straight in, no fade.
    func skip() {
        guard Thread.isMainThread else { DispatchQueue.main.async { self.skip() }; return }
        guard showing, freezeAt == nil else { return }
        leaving = true
        leaveFade = nil
        showing = false
        stop()
    }

    /// The clip ended (or a tap): cross-fade into Play.
    func finish(fade: Double = Intro.fade) {
        guard showing, !leaving, freezeAt == nil else { return }
        leaving = true
        leaveFade = fade
        showing = false
        DispatchQueue.main.asyncAfter(deadline: .now() + fade + 0.1) { self.stop() }
    }

    /// Called once the intro is on screen.
    func start() {
        guard showing, !started else { return }
        started = true
        if reduced {
            stillShown = true   // the view fades it in
            if freezeAt == nil { DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) { self.finish(fade: 0.3) } }
            return
        }
        guard let url = Bundle.main.url(forResource: "intro", withExtension: "mp4") else { skip(); return }
        // the clip has no sound; ambient (the app's own audio session, Feel.swift) never stops someone's music
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        p.isMuted = true
        p.actionAtItemEnd = .pause          // it rests on the finished mark while it fades
        p.preventsDisplaySleepDuringVideoPlayback = false
        player = p
        objectWillChange.send()
        if let at = freezeAt {
            // a test's still: once the clip is ready, show exactly this moment and stay there
            readyWatch = item.observe(\.status, options: [.initial, .new]) { [weak p] item, _ in
                guard item.status == .readyToPlay else { return }
                DispatchQueue.main.async { p?.seek(to: CMTime(seconds: at, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) }
            }
            return
        }
        observers.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            self?.finish()
        })
        observers.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            self?.finish(fade: Intro.tapFade)
        })
        p.play()
        // never longer than this, whatever the player does (a slow or broken decode)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { self.finish() }
    }

    private func stop() {
        player?.pause()
        player = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
    }
}

/// Over the Play screen while the intro shows. The clip keeps its shape on every screen: it fits inside the screen
/// on the clip's navy (on an iPad, in the middle with navy at the sides; on a phone, navy bars that don't show).
struct IntroOverlay: View {
    @ObservedObject var intro = Intro.shared

    private static let still = Bundle.main.path(forResource: "intro-end", ofType: "jpg").flatMap { UIImage(contentsOfFile: $0) }

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
        .accessibilityHint("Tap to skip")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("intro")
    }
}

/// The clip, drawn by an AVPlayerLayer at the clip's own shape (resizeAspect: never stretched or cropped).
private struct IntroPlayer: UIViewRepresentable {
    let player: AVPlayer?

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> PlayerView {
        let v = PlayerView()
        v.backgroundColor = .clear
        v.isUserInteractionEnabled = false
        v.playerLayer.videoGravity = .resizeAspect
        v.playerLayer.player = player
        return v
    }

    func updateUIView(_ v: PlayerView, context: Context) {
        if v.playerLayer.player !== player { v.playerLayer.player = player }
    }
}

/// You → Intro at launch.
struct IntroSection: View {
    @AppStorage(IntroSettings.key) private var on = true

    var body: some View {
        Section {
            Toggle("Intro at launch", isOn: $on)
                .tint(T2P.gold)
                .accessibilityIdentifier("toggle-intro")
        } footer: {
            Text("The Time2Play mark when the app opens. It never plays when you open a game’s link, an invite or an alert.")
                .foregroundStyle(T2P.muted)
        }
        .listRowBackground(T2P.panel)
    }
}
