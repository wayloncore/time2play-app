import SwiftUI
import UIKit
import T2PCore

/// You → "Something slow or broken? Send a report" (wayloncore/tyleralocke#594 part 2). Only when the player taps
/// Send: what happened (a few choices and optional words), the phone's model, iOS version, the app's version and
/// build, and the last game's frame numbers (FrameWatch). The sheet shows exactly what goes before it's sent. It goes
/// to the website's own report form (POST tyleralocke.com/report), which keeps it on the studio's Problems page, and
/// the morning digest files it as a to-do. No name, no account, no email, nothing tracked.
/// The UI tests never send one (they run with -uitest-reset): the sheet says "Sent" without sending.
struct ReportSection: View {
    /// The sheet's switch, held by the screen around the list (a sheet on a row inside a Form doesn't present).
    @Binding var open: Bool
    var body: some View {
        Section {
            Button { open = true } label: {
                Label("Something slow or broken? Send a report", systemImage: "exclamationmark.bubble")
                    .foregroundStyle(T2P.goldText)
            }
            .accessibilityIdentifier("send-report")
        } footer: {
            Text("Only when you tap Send. It says what happened, this phone’s model and iOS version, and how smoothly your last game drew. No name or account goes with it.")
                .foregroundStyle(T2P.muted)
        }
        .listRowBackground(T2P.panel)
    }
}

enum DeviceFacts {
    /// The model identifier ("iPhone16,1"); the simulator says which model it stands in for.
    static var model: String {
        if let sim = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return sim + " (simulator)" }
        var u = utsname()
        uname(&u)
        return withUnsafeBytes(of: &u.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
    static var build: String { (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "0" }
}

struct ReportSheet: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var picked: Set<AppReport.Choice> = []
    @State private var words = ""
    @State private var sending = false
    @State private var problem: String?
    @State private var opened = Date()

    private var report: AppReport {
        AppReport(choices: AppReport.Choice.allCases.filter { picked.contains($0) }, words: words,
                  device: DeviceFacts.model, system: UIDevice.current.systemVersion,
                  version: AppModel.appVersion, build: DeviceFacts.build, frames: FrameWatch.lastGame)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(AppReport.Choice.allCases) { c in
                        Button {
                            if picked.contains(c) { picked.remove(c) } else { picked.insert(c) }
                            Haptics.select()
                        } label: {
                            HStack {
                                Text(c.label).foregroundStyle(T2P.text)
                                Spacer()
                                Image(systemName: picked.contains(c) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(picked.contains(c) ? T2P.gold : T2P.faint)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(picked.contains(c) ? .isSelected : [])
                        .accessibilityIdentifier("report-\(c.rawValue)")
                    }
                } header: { Text("What happened?") }
                .listRowBackground(T2P.panel)

                Section {
                    TextField("Optional: which game, what you were doing", text: $words, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityIdentifier("report-words")
                } header: { Text("In your words") }
                .listRowBackground(T2P.panel)

                Section {
                    ForEach(report.facts, id: \.self) {
                        Text($0).font(.footnote.monospaced()).foregroundStyle(T2P.muted).accessibilityIdentifier("report-fact")
                    }
                } header: {
                    Text("Sent with it")
                } footer: {
                    Text("That’s all. It goes to Tyler, who makes the games, to find what’s slow or broken. Nothing is sold or tracked.")
                        .foregroundStyle(T2P.muted)
                }
                .listRowBackground(T2P.panel)

                if let p = problem {
                    Section { Label(p, systemImage: "exclamationmark.circle.fill").foregroundStyle(T2P.ember) }
                        .listRowBackground(T2P.panel)
                }
            }
            .scrollContentBackground(.hidden)
            .background(T2P.navy.ignoresSafeArea())
            .navigationTitle("Send a report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if sending { ProgressView() } else {
                        Button("Send") { Task { await send() } }.disabled(!report.ready).accessibilityIdentifier("report-send")
                    }
                }
            }
        }
        .onAppear { opened = Date() }
    }

    private func send() async {
        let r = report
        guard r.ready else { return }
        sending = true; problem = nil
        defer { sending = false }
        // the form takes a report only once it has been open 3 seconds: a quick one waits the rest, honestly
        let open = Int(Date().timeIntervalSince(opened) * 1000)
        if open < AppReport.minimumOpenMs { try? await Task.sleep(nanoseconds: UInt64(AppReport.minimumOpenMs - open + 100) * 1_000_000) }
        let elapsed = Int(Date().timeIntervalSince(opened) * 1000)
        if ProcessInfo.processInfo.arguments.contains("-uitest-reset") {
            print("REPORT (not sent, a test) page=\(r.page) elapsed=\(elapsed)\n\(r.text)")
        } else {
            do { try await app.api.sendReport(r, elapsedMs: elapsed) }
            catch {
                problem = (error as? API.Failure)?.message ?? "It didn’t send. Check your signal and try again."
                return
            }
        }
        dismiss()
        AppDialogs.shared.say("Thanks, it’s sent", "Tyler reads every one. If it’s something he can fix, the fix comes in an update.", identifier: "dialog-report-sent")
    }
}
