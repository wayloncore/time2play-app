import UIKit
import T2PCore

/// How smoothly the last game drew (wayloncore/tyleralocke#594): while a game is being played on this phone, a display
/// link times each frame (FrameMeter in T2PCore). When the game ends or the room closes, the numbers (average frame
/// rate, the worst frame, how many stutters) are kept on this phone, and only a report the player sends carries them.
/// Nothing is sent by itself, and nothing is kept about who played.
final class FrameWatch: NSObject {
    static let shared = FrameWatch()
    /// The last game's numbers (a FrameSummary), a new key. Saved data: add fields, never rename or remove.
    static let key = "t2p.lastFrames"

    private var link: CADisplayLink?
    private var meter = FrameMeter()
    private var game: Game?
    private var last: CFTimeInterval?

    private override init() {
        super.init()
        // a pause (Control Center, the phone locked) isn't a stutter: start timing again from the next frame
        NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.last = nil
        }
    }

    /// The room's view changed: a game is being played here now, or not.
    func playing(_ on: Bool, game g: Game) {
        if on {
            if game != nil && game != g { stop() }
            game = g
            guard link == nil else { return }
            let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
            l.add(to: .main, forMode: .common)
            link = l
            last = nil
        } else if link != nil {
            stop()
        }
    }

    /// The game ended or the room closed: keep what was measured (a few seconds at least), and stop timing.
    func stop() {
        link?.invalidate(); link = nil; last = nil
        if let g = game, let s = meter.summary(game: g.rawValue) {
            UserDefaults.standard.set(try? JSONEncoder().encode(s), forKey: Self.key)
        }
        meter = FrameMeter(); game = nil
    }

    @objc private func tick(_ l: CADisplayLink) {
        if let prev = last { meter.add(l.timestamp - prev, expected: l.duration) }
        last = l.timestamp
    }

    /// The last game's numbers, if a game has been measured on this phone.
    static var lastGame: FrameSummary? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(FrameSummary.self, from: $0) }
    }
}
