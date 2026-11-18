import SwiftUI
import AVFoundation
import UIKit
import T2PCore

/// You → "Logo on the waiting screen". Saved settings: a new key only, and a missing key reads as on, so the version
/// before (which has no loop) and this one never disagree about anything already saved.
enum WaitingLoopSettings {
    static let key = "t2p.waitingLoop"
}

/// The waiting screen's logo (wayloncore/tyleralocke#543): Tyler's 10-second loop of the Time2Play mark (the wave
/// through the ring, the 2's jump that knocks the T loose, the little cream character on the "y"), on the host's
/// waiting screen until the game starts. About once a minute the launch intro (#562) plays in place of one pass
/// (WaitingLoopPlan in T2PCore), then the loop carries on.
///
/// One player for every screen that shows it, so an iPad and its TV show the same frames with one decode. It plays only
/// while at least one of them is on screen, and lets go of the video a few seconds after the last one leaves.
///
/// The clip (App/Intro/waiting-loop.mp4): Tyler's 10.0 s, 1080 × 1916, 24 fps video with its empty audio track
/// stripped, H.264. Its first and last frames match, but the edges shifted a hair at the wrap, so the last 3 frames
/// cross-fade into the first (25, 50, 75%) and the duplicate last frame is dropped: 240 frames, exactly 10 s. The intro
/// ends on the same finished mark the loop starts on, so the intro hands back to the loop without a jump.
/// Tests: -t2p-loop-freeze <seconds> stops the loop at a moment for screenshots; -t2p-loop-pass <n> starts the cycle at
/// pass n (5 starts on the intro); -t2p-reduce-motion acts as if Reduce Motion is on.
final class WaitingLoop: ObservableObject {
    static let shared = WaitingLoop()

    let player = AVQueuePlayer()
    /// The clip on screen now (the UI tests read it as the logo's accessibility value).
    @Published private(set) var clip: WaitingLoopPlan.Clip = .loop
    @Published private(set) var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    let testReduced: Bool
    let freezeAt: Double?
    private let firstPass: Int
    private let loopAsset: AVURLAsset?
    private let introAsset: AVURLAsset?
    private var viewers = Set<UUID>()
    private var queued = -1                              // the last pass put in the queue
    private var upcoming: [WaitingLoopPlan.Clip] = []    // the clips in the queue, in order; the first is on screen
    private var observers: [NSObjectProtocol] = []
    private var readyWatch: NSKeyValueObservation?
    private var letGo: DispatchWorkItem?

    var available: Bool { loopAsset != nil }

    private init() {
        let args = ProcessInfo.processInfo.arguments
        testReduced = args.contains("-t2p-reduce-motion")
        if let i = args.firstIndex(of: "-t2p-loop-freeze"), i + 1 < args.count { freezeAt = Double(args[i + 1]) } else { freezeAt = nil }
        if let i = args.firstIndex(of: "-t2p-loop-pass"), i + 1 < args.count { firstPass = max(0, Int(args[i + 1]) ?? 0) } else { firstPass = 0 }
        loopAsset = Bundle.main.url(forResource: "waiting-loop", withExtension: "mp4").map { AVURLAsset(url: $0) }
        introAsset = Bundle.main.url(forResource: "intro", withExtension: "mp4").map { AVURLAsset(url: $0) }
        player.isMuted = true                                 // the clips have no sound anyway
        player.actionAtItemEnd = .advance
        player.preventsDisplaySleepDuringVideoPlayback = false
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] n in
            guard let self, let item = n.object as? AVPlayerItem, self.owns(item) else { return }
            self.passEnded()
        })
        observers.append(center.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: nil, queue: .main) { [weak self] n in
            guard let self, let item = n.object as? AVPlayerItem, self.owns(item) else { return }
            self.passEnded()
        })
        observers.append(center.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        })
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.player.pause()
        })
    }

    private func owns(_ item: AVPlayerItem) -> Bool {
        (loopAsset != nil && item.asset === loopAsset) || (introAsset != nil && item.asset === introAsset)
    }

    /// Puts the next pass in the queue: the loop, or the intro in place of one pass in six.
    private func enqueue() {
        queued += 1
        let wanted = WaitingLoopPlan.clip(forPass: queued)
        let c: WaitingLoopPlan.Clip = wanted == .intro && introAsset != nil ? .intro : .loop
        guard let asset = c == .intro ? introAsset : loopAsset else { return }
        player.insert(AVPlayerItem(asset: asset), after: nil)
        upcoming.append(c)
    }

    /// A pass ended; the player has moved on to the next one, so queue the one after it (two are always queued, so
    /// the hand-over is seamless).
    private func passEnded() {
        if !upcoming.isEmpty { upcoming.removeFirst() }
        enqueue()
        clip = upcoming.first ?? .loop
    }

    private func fill() {
        guard player.items().isEmpty else { return }
        upcoming = []
        queued = firstPass - 1
        enqueue()
        enqueue()
        clip = upcoming.first ?? .loop
    }

    /// A screen showing the clip is on screen (or back on screen).
    func show(_ id: UUID) {
        letGo?.cancel(); letGo = nil
        viewers.insert(id)
        fill()
        if let at = freezeAt { freeze(at); return }
        if player.rate == 0 { player.play() }
    }

    /// It left the screen: the game started, the room closed, or the app went to the background.
    func hide(_ id: UUID) {
        guard viewers.remove(id) != nil, viewers.isEmpty else { return }
        player.pause()
        // nobody's looking: let go of the video after a moment (a rotation makes the view again straight away)
        let w = DispatchWorkItem { [weak self] in
            guard let self, self.viewers.isEmpty else { return }
            self.player.removeAllItems()
            self.upcoming = []
            self.readyWatch = nil
            self.clip = .loop
        }
        letGo = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: w)
    }

    /// A test's still: once the clip is ready, show exactly this moment and stay there.
    private func freeze(_ at: Double) {
        player.pause()
        guard readyWatch == nil, let item = player.currentItem else { return }
        readyWatch = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard item.status == .readyToPlay else { return }
            DispatchQueue.main.async {
                self?.player.seek(to: CMTime(seconds: at, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            }
        }
    }
}

/// The loop on a waiting screen. It sizes itself to the part of the clip's frame the mark uses (the 2's jump above the
/// ring, and the ring; the rest is empty navy), with its edges feathered into the screen's own background. It's put
/// beside the room code and the QR code, never under them, so they stay big and sharp.
/// Reduce Motion and Low Power Mode show the still mark; it's gone the moment the game starts (or when You → Logo on
/// the waiting screen is off).
struct WaitingLogo: View {
    /// How it sits on its screen: blended (its edges melt into a screen of the clip's own navy: the iPad host's stage
    /// and the TV), or a badge (a rounded square around the ring, for the phone lobby, light or dark).
    enum Style { case blend, badge }
    /// The room's phase: the clip shows only in the lobby.
    var phase: String?
    var style: Style = .blend
    @ObservedObject private var loop = WaitingLoop.shared
    @AppStorage(WaitingLoopSettings.key) private var on = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var id = UUID()
    @State private var onScreen = false

    /// The clip's frame, and the part of it shown (rows 0 to 1480: the mark rests in rows 465 to 1405, and the 2's
    /// jump reaches the top).
    static let clipSize = CGSize(width: 1080, height: 1916)
    static let shownHeight: CGFloat = 1480
    static var aspect: CGFloat { clipSize.width / shownHeight }
    /// The badge: a square around the ring (its center is at row 935), so rows 395 to 1475.
    static let badgeTop: CGFloat = 395
    private static let still = Bundle.main.path(forResource: "waiting-still", ofType: "jpg").flatMap { UIImage(contentsOfFile: $0) }

    private var mode: WaitingLoopPlan.Mode {
        let m = WaitingLoopPlan.mode(phase: phase, on: on, reduceMotion: reduceMotion || loop.testReduced, lowPower: loop.lowPower)
        return m == .moving && !loop.available ? .still : m
    }

    var body: some View {
        if mode != .hidden {
            picture
                .aspectRatio(style == .badge ? 1 : Self.aspect, contentMode: .fit)
                .onAppear { onScreen = true; update() }
                .onDisappear { onScreen = false; update() }
                .onChange(of: scenePhase) { _, _ in update() }
                .onChange(of: mode) { _, _ in update() }
                .accessibilityElement()
                .accessibilityLabel("Time2Play")
                .accessibilityValue(mode == .moving ? (loop.clip == .intro ? "intro" : "loop") : "still")
                .accessibilityAddTraits(.isImage)
                .accessibilityIdentifier("waiting-loop")
        }
    }

    /// Plays while it's on screen and its screen is up (inactive counts: Control Center over it, while someone picks
    /// the TV); otherwise it pauses.
    private func update() {
        if onScreen && mode == .moving && scenePhase != .background { loop.show(id) } else { loop.hide(id) }
    }

    @ViewBuilder private var picture: some View {
        if style == .badge {
            frames(top: Self.badgeTop)
                .background(Color(uiColor: Intro.navy))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else {
            frames(top: 0).mask { feather }
        }
    }

    /// The clip (or the still) at its own shape, shown from row `top` of its frame down.
    private func frames(top: CGFloat) -> some View {
        GeometryReader { g in
            let scale = g.size.width / Self.clipSize.width
            Group {
                if mode == .moving {
                    LoopPlayerView(player: loop.player)
                } else if let ui = Self.still {
                    Image(uiImage: ui).resizable()
                }
            }
            .frame(width: g.size.width, height: Self.clipSize.height * scale)
            .offset(y: -top * scale)
            .frame(width: g.size.width, height: g.size.height, alignment: .top)
            .clipped()
        }
    }

    /// Soft edges, so the clip's navy melts into the screen behind it (the same navy) (wide at the top, where the 2 jumps out of
    /// the frame; narrow at the sides, where the ring nearly touches them).
    private var feather: some View {
        LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.08),
                               .init(color: .black, location: 0.955), .init(color: .clear, location: 1)],
                       startPoint: .top, endPoint: .bottom)
            .mask {
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.035),
                                       .init(color: .black, location: 0.965), .init(color: .clear, location: 1)],
                               startPoint: .leading, endPoint: .trailing)
            }
    }
}

/// The shared player, drawn by an AVPlayerLayer at the clip's own shape (the frame above is the clip's shape, so
/// nothing is stretched or cropped by the layer itself).
private struct LoopPlayerView: UIViewRepresentable {
    let player: AVPlayer

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> PlayerView {
        let v = PlayerView()
        v.backgroundColor = .clear
        v.isUserInteractionEnabled = false
        v.playerLayer.videoGravity = .resizeAspectFill
        v.playerLayer.player = player
        return v
    }

    func updateUIView(_ v: PlayerView, context: Context) {
        if v.playerLayer.player !== player { v.playerLayer.player = player }
    }
}
