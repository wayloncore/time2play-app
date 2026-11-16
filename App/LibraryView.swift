import SwiftUI
import T2PCore

/// The Library, read from the server: the same cards the website's Library shows. The app's own games start a room
/// here; everything else opens on the website.
struct LibraryView: View {
    @EnvironmentObject var app: AppModel
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List {
                if let p = app.libraryProblem {
                    Text(p).foregroundStyle(T2P.muted).listRowBackground(T2P.panel)
                }
                if search.isEmpty {
                    Section {
                        ForEach(Game.allCases) { g in
                            Button { Task { await app.start(g) } } label: {
                                LibraryRow(title: g.title, line: g.blurb, detail: g.players, thumb: nil, symbol: g.symbol, tint: g.tint, action: "Start")
                            }
                            .accessibilityIdentifier("library-start-\(g.rawValue)")
                        }
                    } header: { Text("Play in the app") }
                    ForEach(app.library.categories) { c in
                        let items = app.library.items(in: c).filter { $0.game == nil }
                        if !items.isEmpty {
                            Section { ForEach(items) { item($0) } } header: { Text(c.name) } footer: { if !c.line.isEmpty { Text(c.line).foregroundStyle(T2P.muted) } }
                        }
                    }
                } else {
                    ForEach(app.library.search(search)) { item($0) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(T2P.navy.ignoresSafeArea())
            .listRowBackground(T2P.panel)
            .navigationTitle("Library")
            .searchable(text: $search, prompt: "Search the Library")
            .refreshable { await app.loadLibrary() }
            .task { await app.loadLibrary() }
        }
    }

    @ViewBuilder private func item(_ i: Library.Item) -> some View {
        if let g = i.game {
            Button { Task { await app.start(g) } } label: {
                LibraryRow(title: i.title, line: i.blurb, detail: i.playersLine, thumb: thumbURL(i), symbol: g.symbol, tint: g.tint, action: "Start")
            }
        } else {
            Link(destination: app.endpoints.api(String(i.page.drop(while: { $0 == "/" })))) {
                LibraryRow(title: i.title, line: i.blurb, detail: i.playersLine, thumb: thumbURL(i), symbol: "safari", tint: T2P.panelHi, action: nil)
            }
            .accessibilityHint("Opens on the website")
        }
    }

    private func thumbURL(_ i: Library.Item) -> URL? {
        guard let t = i.thumb else { return nil }
        return URL(string: t, relativeTo: app.endpoints.base)?.absoluteURL
    }
}

struct LibraryRow: View {
    let title: String; let line: String?; let detail: String?; let thumb: URL?; let symbol: String; let tint: Color; let action: String?
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                tint
                if let u = thumb {
                    AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { Image(systemName: symbol).foregroundStyle(.white.opacity(0.8)) }
                } else {
                    Image(systemName: symbol).font(.title2).foregroundStyle(.white.opacity(0.9))
                }
            }
            .frame(width: 72, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(T2P.text)
                if let l = line { Text(l).font(.subheadline).foregroundStyle(T2P.muted).lineLimit(2) }
                if let d = detail { Text(d).font(.caption).foregroundStyle(T2P.faint) }
            }
            Spacer(minLength: 4)
            if let a = action {
                Text(a).font(.subheadline.weight(.semibold)).foregroundStyle(T2P.ink)
                    .padding(.horizontal, 12).padding(.vertical, 6).background(T2P.gold, in: Capsule())
            } else {
                Image(systemName: "arrow.up.right").foregroundStyle(T2P.faint)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct FacePickerSheet: View {
    @Binding var face: Int?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 12)], spacing: 12) {
                    ForEach(0..<Faces.count, id: \.self) { i in
                        Button { face = i; Haptics.select(); dismiss() } label: {
                            FaceView(face: i, size: 64).overlay(Circle().stroke(face == i ? T2P.gold : .clear, lineWidth: 4).padding(-3))
                        }
                        .accessibilityLabel(Faces.label(i))
                        .accessibilityAddTraits(face == i ? .isSelected : [])
                    }
                }
                .padding(20)
            }
            .background(T2P.navy.ignoresSafeArea())
            .navigationTitle("Your face")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
