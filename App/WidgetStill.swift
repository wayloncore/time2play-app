import SwiftUI
import T2PCore

/// The home screen widget drawn inside the app at its real sizes (iPhone: small 170 × 170, medium 364 × 170 points),
/// for the screenshots a simulator run can take (-t2p-widget-still). The widget itself can't be screenshotted there.
struct WidgetStill {
    var noRoom: Bool
    static func fromArgs() -> WidgetStill? {
        let a = ProcessInfo.processInfo.arguments
        guard a.contains("-t2p-widget-still") else { return nil }
        return WidgetStill(noRoom: a.contains("-t2p-widget-noroom"))
    }
}

struct WidgetStillView: View {
    let still: WidgetStill
    var body: some View {
        let c: WidgetContent = {
            var x = WidgetContent.make(Date(), library: .appOnly, last: RecentRoom(code: "K7QP", game: .overdraft, at: Date().addingTimeInterval(-600)))
            if still.noRoom { x.last = nil }
            return x
        }()
        ZStack {
            LinearGradient(colors: [Color(red: 0.33, green: 0.42, blue: 0.62), Color(red: 0.62, green: 0.46, blue: 0.52)],
                           startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            VStack(spacing: 28) {
                tile(width: 170) { GameOfTheDayView(c: c) }
                tile(width: 364) {
                    HStack(spacing: 12) { GameOfTheDayView(c: c); RejoinView(last: c.last).frame(width: 132) }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("widget-still")
        }
    }

    private func tile<V: View>(width: CGFloat, @ViewBuilder _ v: () -> V) -> some View {
        v()
            .padding(16)
            .frame(width: width, height: 170)
            .background(WidgetBackdrop(game: still.noRoom ? nil : WidgetContent.make(Date(), library: .appOnly, last: nil).game))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
    }
}
