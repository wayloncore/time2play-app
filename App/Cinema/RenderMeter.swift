import Foundation
import QuartzCore
import SceneKit

/// #716: the frame rate a 3D scene really draws at, for the cinematic options' reports. Only with -t2p-cinema-fps:
/// every two seconds it prints one line to the app's console ("FPS overdraft 58.9 worst 21.4 ms"), which the Mac run
/// reads with `simctl launch --stdout`. Called from SceneKit's render callback (its render thread).
struct RenderMeter {
    static let on = ProcessInfo.processInfo.arguments.contains("-t2p-cinema-fps")
    let name: String
    private var start: TimeInterval?
    private var last: TimeInterval?
    private var count = 0
    private var worst = 0.0

    init(name: String) { self.name = name }

    mutating func frame(_ time: TimeInterval) {
        guard Self.on else { return }
        if let l = last { worst = max(worst, time - l) }
        last = time
        guard let s = start else { start = time; count = 0; return }
        count += 1
        let span = time - s
        if span >= 2 {
            print(String(format: "FPS %@ %.1f worst %.1f ms", name, Double(count) / span, worst * 1000))
            fflush(stdout)
            start = time; count = 0; worst = 0
        }
    }
}

/// A render delegate that only counts frames (for scenes that have no render delegate of their own, the dice).
final class RenderMeterDelegate: NSObject, SCNSceneRendererDelegate {
    private var meter: RenderMeter
    init(name: String) { meter = RenderMeter(name: name) }
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) { meter.frame(time) }
}
