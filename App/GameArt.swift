import SwiftUI
import T2PCore

/// Each game's own picture (Tyler, Nov 18: the Recent rooms thumbnail "is very confusing"): drawn from the game's own
/// pieces, so it reads at any size, from a 44-point row to a Start card. Overdraft: two of its cards (the bundled art).
/// Hot Dice: ivory dice on the green felt in a wood tray. Roll Call: its paper score pad and two dice on the wood.
/// Close Enough: its gold range bar on the ruler, with the answer inside it. The website's Library pictures are
/// full-screen screenshots that turn to mush at row size (checked at 72 × 48), and Roll Call has none, so the app
/// draws these instead. One picture per game, used everywhere: Start cards, the Library's app games, Recent rooms,
/// invites, the game picker and presets.
struct GameArt: View {
    let game: Game?

    var body: some View {
        GeometryReader { g in
            art(g.size.width, g.size.height)
                .frame(width: g.size.width, height: g.size.height)
        }
        .clipped()
        .accessibilityHidden(true)
    }

    @ViewBuilder private func art(_ w: CGFloat, _ h: CGFloat) -> some View {
        switch game {
        case .overdraft?: overdraft(w, h)
        case .hotDice?: hotDice(w, h)
        case .rollCall?: rollCall(w, h)
        case .closeEnough?: closeEnough(w, h)
        case nil:
            ZStack {
                T2P.panelHi
                Image(systemName: "gamecontroller.fill").font(.system(size: h * 0.4)).foregroundStyle(T2P.muted)
            }
        }
    }

    // MARK: Overdraft: two cards, fanned, on the plum table

    private func overdraft(_ w: CGFloat, _ h: CGFloat) -> some View {
        let ch = h * 0.84, cw = ch * 2 / 3
        return ZStack {
            LinearGradient(colors: [Color(hex: 0x4A2A57), Color(hex: 0x1D1026)], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Painted.gold.opacity(0.25), .clear], center: .center, startRadius: 0, endRadius: max(w, h) * 0.55)
            card("wave_7").frame(width: cw, height: ch).rotationEffect(.degrees(-12)).offset(x: -cw * 0.34, y: h * 0.03)
            card("change_suit").frame(width: cw, height: ch).rotationEffect(.degrees(9)).offset(x: cw * 0.34, y: -h * 0.01)
        }
    }

    @ViewBuilder private func card(_ name: String) -> some View {
        if let i = Art.image(name) {
            Image(uiImage: i).resizable().scaledToFit().shadow(color: .black.opacity(0.45), radius: 3, y: 2)
        } else {
            RoundedRectangle(cornerRadius: 4).fill(Painted.faceTop).overlay(RoundedRectangle(cornerRadius: 4).stroke(Painted.gold))
        }
    }

    // MARK: Hot Dice: three dice on the felt, in the wood tray

    private func hotDice(_ w: CGFloat, _ h: CGFloat) -> some View {
        let s = min(w, h), d = h * 0.34
        return ZStack {
            LinearGradient(colors: [Color(hex: 0x7A4A25), Color(hex: 0x3E2312)], startPoint: .top, endPoint: .bottom)
            RoundedRectangle(cornerRadius: s * 0.1, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x2F7A58), Color(hex: 0x163F2D)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: s * 0.1, style: .continuous).stroke(Color.black.opacity(0.35), lineWidth: max(1, s * 0.02)))
                .padding(s * 0.08)
            ArtDie(value: 5, size: d).rotationEffect(.degrees(-15)).offset(x: -w * 0.2, y: h * 0.1)
            ArtDie(value: 1, size: d).rotationEffect(.degrees(11)).offset(x: w * 0.03, y: -h * 0.14)
            ArtDie(value: 3, size: d).rotationEffect(.degrees(-4)).offset(x: w * 0.23, y: h * 0.12)
        }
    }

    // MARK: Roll Call: the score pad and two dice on the wood

    private func rollCall(_ w: CGFloat, _ h: CGFloat) -> some View {
        let ph = h * 0.8, pw = ph * 0.74, d = h * 0.3
        return ZStack {
            LinearGradient(colors: [Color(hex: 0x6E4B2E), Color(hex: 0x3A281A)], startPoint: .topLeading, endPoint: .bottomTrailing)
            ScorePad()
                .frame(width: pw, height: ph)
                .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
                .rotationEffect(.degrees(-6))
                .offset(x: w * 0.13)
            ArtDie(value: 6, size: d).rotationEffect(.degrees(-12)).offset(x: -w * 0.24, y: h * 0.14)
            ArtDie(value: 6, size: d).rotationEffect(.degrees(8)).offset(x: -w * 0.05, y: h * 0.24)
        }
    }

    // MARK: Close Enough: the gold range bar on the ruler, the answer inside it

    private func closeEnough(_ w: CGFloat, _ h: CGFloat) -> some View {
        let bh = h * 0.2, bw = w * 0.5
        return ZStack {
            LinearGradient(colors: [Color(hex: 0x2B2218), Color(hex: 0x110D09)], startPoint: .top, endPoint: .bottom)
            Ruler().frame(width: w * 0.84, height: h * 0.22).offset(y: h * 0.22)
            ZStack {
                RoundedRectangle(cornerRadius: bh * 0.3, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0xF8DB94), Painted.gold, Color(hex: 0xB9832C)], startPoint: .top, endPoint: .bottom))
                    .frame(width: bw, height: bh)
                ForEach([-1.0, 1.0], id: \.self) { side in
                    RoundedRectangle(cornerRadius: bh * 0.2, style: .continuous)
                        .fill(LinearGradient(colors: [Color(hex: 0xC8913A), Color(hex: 0x7A4E16)], startPoint: .top, endPoint: .bottom))
                        .overlay(RoundedRectangle(cornerRadius: bh * 0.2, style: .continuous).stroke(Painted.goldHi.opacity(0.7), lineWidth: 0.75))
                        .frame(width: bh * 0.5, height: bh * 1.6)
                        .offset(x: side * bw / 2)
                }
            }
            .shadow(color: Painted.gold.opacity(0.35), radius: 4)
            .offset(y: -h * 0.1)
            // the answer: a small ember diamond on the ruler, inside the range
            Rectangle().fill(T2P.ember).frame(width: h * 0.09, height: h * 0.09).rotationEffect(.degrees(45))
                .offset(x: w * 0.06, y: h * 0.14)
        }
    }
}

/// An ivory die with its pips (a 1's pip is red, like the website's dice).
struct ArtDie: View {
    let value: Int
    var size: CGFloat = 24
    var body: some View {
        let spots: [(CGFloat, CGFloat)] = {
            let a: CGFloat = 0.27, b: CGFloat = 0.5, c: CGFloat = 0.73
            switch value {
            case 1: return [(b, b)]
            case 2: return [(a, a), (c, c)]
            case 3: return [(a, a), (b, b), (c, c)]
            case 4: return [(a, a), (c, a), (a, c), (c, c)]
            case 5: return [(a, a), (c, a), (b, b), (a, c), (c, c)]
            default: return [(a, a), (c, a), (a, b), (c, b), (a, c), (c, c)]
            }
        }()
        return ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0xFFFBF0), Color(hex: 0xE6DBC2)], startPoint: .topLeading, endPoint: .bottomTrailing))
            ForEach(spots.indices, id: \.self) { i in
                Circle().fill(value == 1 ? Color(hex: 0xB0302A) : Color(hex: 0x231A10))
                    .frame(width: size * (value == 1 ? 0.24 : 0.17), height: size * (value == 1 ? 0.24 : 0.17))
                    .position(x: spots[i].0 * size, y: spots[i].1 * size)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.45), radius: size * 0.08, y: size * 0.06)
    }
}

/// Roll Call's paper score pad: the red band, the ruled rows and a few pen marks in the score column.
private struct ScorePad: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let page = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: w * 0.06)
            ctx.fill(page, with: .color(RCPaper.paper))
            ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h * 0.15)), with: .color(RCPaper.band))
            let rows = 6
            var lines = Path()
            for i in 1...rows {
                let y = h * 0.15 + (h * 0.85) * CGFloat(i) / CGFloat(rows + 1)
                lines.move(to: CGPoint(x: w * 0.08, y: y)); lines.addLine(to: CGPoint(x: w * 0.92, y: y))
            }
            lines.move(to: CGPoint(x: w * 0.64, y: h * 0.2)); lines.addLine(to: CGPoint(x: w * 0.64, y: h * 0.95))
            ctx.stroke(lines, with: .color(RCPaper.rule), lineWidth: max(0.5, w * 0.02))
            // pen marks: short strokes in the score column on the first few rows, the name column's scribbles
            var pen = Path()
            for i in 0..<4 {
                let y = h * 0.15 + (h * 0.85) * (CGFloat(i) + 0.55) / CGFloat(rows + 1)
                pen.move(to: CGPoint(x: w * 0.7, y: y)); pen.addLine(to: CGPoint(x: w * (i % 2 == 0 ? 0.86 : 0.8), y: y - h * 0.01))
                pen.move(to: CGPoint(x: w * 0.14, y: y)); pen.addLine(to: CGPoint(x: w * (0.42 + CGFloat(i % 3) * 0.06), y: y))
            }
            ctx.stroke(pen, with: .color(RCPaper.pen.opacity(0.85)), style: StrokeStyle(lineWidth: max(0.8, w * 0.035), lineCap: .round))
        }
    }
}

/// Close Enough's ruler: a gold line and its ticks, the tall ones every fifth.
private struct Ruler: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            var p = Path()
            p.move(to: CGPoint(x: 0, y: h * 0.2)); p.addLine(to: CGPoint(x: w, y: h * 0.2))
            let n = 20
            for i in 0...n {
                let x = w * CGFloat(i) / CGFloat(n)
                p.move(to: CGPoint(x: x, y: h * 0.2)); p.addLine(to: CGPoint(x: x, y: h * (i % 5 == 0 ? 0.95 : 0.55)))
            }
            ctx.stroke(p, with: .color(Painted.gold.opacity(0.6)), lineWidth: max(0.5, h * 0.06))
        }
    }
}

/// One row with a game's picture: Recent rooms, invites and the game picker (the three match, Nov 18).
/// `painted`: on a painted screen (Friends, the game picker), the paper-and-gold colors; otherwise the app's own.
struct GameRowLabel: View {
    let game: Game?
    let title: String
    var tag: String? = nil
    var line: String? = nil
    var small: String? = nil
    var action: String? = nil
    var face: Int? = nil
    var painted = false
    @ScaledMetric(relativeTo: .headline) private var artHeight: CGFloat = 52

    var body: some View {
        HStack(spacing: 12) {
            GameArt(game: game)
                .frame(width: artHeight * 1.3, height: artHeight)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(painted ? Painted.gold.opacity(0.55) : Color.black.opacity(0.12), lineWidth: 1))
                .overlay(alignment: .bottomTrailing) {
                    if let f = face {
                        FaceView(face: f, size: 26)
                            .overlay(Circle().stroke(painted ? Painted.faceBottom : T2P.panel, lineWidth: 2))
                            .offset(x: 7, y: 7)
                    }
                }
                .padding(.trailing, face == nil ? 0 : 4)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(painted ? Painted.display(18) : .headline)
                        .foregroundStyle(painted ? Painted.paper : T2P.text)
                        .lineLimit(1)
                    if let t = tag { if painted { PaintedTag(text: t) } else { Tag(text: t) } }
                }
                if let l = line {
                    Text(l).font(.subheadline).foregroundStyle(painted ? Painted.paperDim : T2P.muted).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let s = small {
                    Text(s).font(.caption).foregroundStyle(painted ? Painted.paperDim.opacity(0.8) : T2P.faint).lineLimit(1).minimumScaleFactor(0.85)
                }
            }
            Spacer(minLength: 8)
            if let a = action {
                Text(a).font(painted ? Painted.display(15) : .subheadline.weight(.semibold))
                    .foregroundStyle(painted ? Color(hex: 0x2A1A05) : T2P.ink)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(painted
                        ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xF8DB94), Painted.gold, Color(hex: 0xB9832C)], startPoint: .top, endPoint: .bottom))
                        : AnyShapeStyle(T2P.gold)))
                    .fixedSize()
            }
        }
        .contentShape(Rectangle())
    }
}

#if DEBUG
/// The test build's gallery of the game pictures at their real sizes (-t2p-art-gallery): a Start card, a Library row,
/// a Recent rooms row, a preset and the invite banner.
struct ArtGallery: View {
    static var requested: Bool { ProcessInfo.processInfo.arguments.contains("-t2p-art-gallery") }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Game pictures").font(.title2.bold()).foregroundStyle(T2P.text)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(Game.allCases) { GameCard(game: $0) }
                }
                Panel {
                    VStack(spacing: 12) {
                        ForEach(Game.allCases) { g in
                            GameRowLabel(game: g, title: g.title, tag: g == .rollCall ? "Solo" : "Live",
                                         line: g == .rollCall ? "You and 2 bots" : "With Sam and Jo, and 1 bot",
                                         small: "Room K7QP · 5 min ago", action: g == .rollCall ? "Resume" : "Rejoin")
                        }
                    }
                }
                VStack(spacing: 12) {
                    ForEach(Game.allCases) { g in
                        GameRowLabel(game: g, title: g.title, line: "Sam invited you", small: "Room K7QP · just now", action: "Join", face: 3, painted: true)
                    }
                }
                .padding(16)
                .background(PaintedBackdrop().clipShape(RoundedRectangle(cornerRadius: 18)))
                HStack(spacing: 10) {
                    ForEach(Game.allCases) { g in
                        GameArt(game: g).frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                InviteBannerView(note: InviteNote(text: "Sam invited you to Hot Dice", game: .hotDice, room: "K7QP", face: 3), join: {}, close: {})
            }
            .padding(16)
        }
        .background(T2P.navy.ignoresSafeArea())
        .accessibilityIdentifier("art-gallery")
    }
}
#endif
