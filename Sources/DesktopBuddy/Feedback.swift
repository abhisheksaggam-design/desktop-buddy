import SwiftUI
import AppKit

// MARK: - Report a bug or an idea

/// Reports go to the team's inbox through a form service (Formspree), set up in team.json:
///   "feedbackFormID": "<Formspree form ID>",   // the service emails reports to the form's owner
///   "feedbackEmail": "you@example.com"          // used if the service can't be reached: the report opens in Mail
/// Nothing is sent except what the person typed and, if they leave it on, the app and macOS version.
enum FeedbackKind: String, CaseIterable, Identifiable {
    case bug, idea
    var id: String { rawValue }
    var title: String { self == .bug ? "Something's wrong" : "Idea or fix" }
    var subjectWord: String { self == .bug ? "Bug" : "Idea" }
}

struct FeedbackReport {
    var kind: FeedbackKind = .bug
    var message = ""
    var replyTo = ""
    var includeDetails = true

    var isReady: Bool { message.trimmingCharacters(in: .whitespacesAndNewlines).count >= 5 }
    var replyIsValid: Bool { replyTo.isEmpty || (replyTo.contains("@") && replyTo.contains(".") && !replyTo.contains(" ")) }
}

enum FeedbackSender {
    static func endpoint(_ formID: String) -> URL? { URL(string: "https://formspree.io/f/\(formID)") }

    static var key: String? { TeamConfig.current.feedbackFormID.flatMap { $0.isEmpty ? nil : $0 } }
    static var email: String? { TeamConfig.current.feedbackEmail.flatMap { $0.isEmpty ? nil : $0 } }
    /// Shown in menus only when reports have somewhere to go.
    static var isSetUp: Bool { key != nil || email != nil }

    static func subject(_ r: FeedbackReport) -> String {
        let first = r.message.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let short = first.count > 60 ? String(first.prefix(57)) + "…" : first
        return "Desktop Buddy \(r.kind.subjectWord): \(short)"
    }

    @MainActor static func details() -> String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let accounts = AppState.shared.config.accounts
        let google = accounts.filter { $0.provider == .google }.count
        let microsoft = accounts.count - google
        return "Desktop Buddy \(v) (\(b)) · macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion) · "
            + "\(google) Google, \(microsoft) Microsoft account\(accounts.count == 1 ? "" : "s")"
    }

    @MainActor static func body(_ r: FeedbackReport) -> String {
        var s = r.message.trimmingCharacters(in: .whitespacesAndNewlines)
        if !r.replyTo.isEmpty { s += "\n\nReply to: \(r.replyTo)" }
        if r.includeDetails { s += "\n\n— \(details())" }
        return s
    }

    @MainActor static func payload(_ r: FeedbackReport) -> [String: Any] {
        var p: [String: Any] = [
            "_subject": subject(r),
            "type": r.kind.title,
            "message": body(r),
        ]
        if !r.replyTo.isEmpty { p["email"] = r.replyTo }      // Formspree sets it as the reply-to address
        return p
    }

    enum Failure: LocalizedError {
        case notSetUp, rejected(String), offline
        var errorDescription: String? {
            switch self {
            case .notSetUp: return "Reporting isn't set up in this copy of Desktop Buddy."
            case .rejected(let m): return "The report wasn't accepted: \(m)"
            case .offline: return "Couldn't reach the internet. Check your connection and try again."
            }
        }
    }

    /// Sends the report. Throws if it wasn't delivered.
    @MainActor static func send(_ r: FeedbackReport) async throws {
        guard let key, let url = endpoint(key) else { throw Failure.notSetUp }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload(r))
        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: req) } catch { throw Failure.offline }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let ok = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
        guard ok, json?["ok"] as? Bool ?? true else {
            throw Failure.rejected(json?["error"] as? String ?? "unknown reply")
        }
    }

    /// The same report as a ready-to-send email in the person's own mail app.
    @MainActor static func mailURL(_ r: FeedbackReport) -> URL? {
        guard let email else { return nil }
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = email
        c.queryItems = [URLQueryItem(name: "subject", value: subject(r)), URLQueryItem(name: "body", value: body(r))]
        return c.url
    }
}

// MARK: - Window

@MainActor
final class FeedbackController: NSObject, NSWindowDelegate {
    static let shared = FeedbackController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: FeedbackView { [weak self] in self?.window?.close() })
            host.sceneBridgingOptions = []
            let w = NSWindow(contentViewController: host)
            w.title = "Report a Bug or Idea"
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        let others = NSApp.windows.contains { $0.isVisible && $0 !== notification.object as? NSWindow && $0.styleMask.contains(.titled) }
        if !others { NSApp.setActivationPolicy(.accessory) }
    }
}

struct FeedbackView: View {
    var close: () -> Void
    @ObservedObject var state = AppState.shared
    @Local private var report = FeedbackReport()
    @Local private var phase: Phase

    init(showingSent: Bool = false, close: @escaping () -> Void) {
        self.close = close
        _phase = Local(wrappedValue: showingSent ? .sent : .editing)
    }
    @FocusState private var messageFocused: Bool

    enum Phase: Equatable { case editing, sending, sent, failed(String) }

    var body: some View {
        Group {
            if phase == .sent { sent } else { form }
        }
        .frame(width: 460)
        .animation(.easeOut(duration: 0.2), value: phase)
        .onAppear {
            if report.replyTo.isEmpty { report.replyTo = state.config.accounts.first?.email ?? "" }
            messageFocused = true
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                SettingsIcon(symbol: "ladybug.fill", tint: .orange, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Report a Bug or Idea").font(.title3.weight(.semibold))
                    Text("Goes straight to the Desktop Buddy team.").font(.callout).foregroundStyle(.secondary)
                }
            }
            Picker("", selection: $report.kind) {
                ForEach(FeedbackKind.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()

            VStack(alignment: .leading, spacing: 6) {
                Text(report.kind == .bug ? "What happened?" : "What would make it better?").font(.callout.weight(.medium))
                TextEditor(text: $report.message)
                    .accessibilityLabel(report.kind == .bug ? "What happened?" : "What would make it better?")
                    .font(.body)
                    .focused($messageFocused)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(height: 140)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(messageFocused ? 0.35 : 0.15)))
                    .overlay(alignment: .topLeading) {
                        if report.message.isEmpty {
                            Text(report.kind == .bug ? "e.g. The logo didn't update after I renamed a client." : "e.g. Let me snooze a whole account for an hour.")
                                .foregroundStyle(.tertiary).padding(.horizontal, 11).padding(.vertical, 6).allowsHitTesting(false)
                        }
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Your email, so we can reply (optional)").font(.callout.weight(.medium))
                TextField("Your email", text: $report.replyTo, prompt: Text("name@company.com"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                if !report.replyIsValid {
                    Text("That doesn't look like an email address.").font(.caption).foregroundStyle(.red)
                }
            }

            Toggle(isOn: $report.includeDetails) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Include app and macOS version")
                    Text(FeedbackSender.details()).font(.caption).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)

            if case .failed(let message) = phase {
                VStack(alignment: .leading, spacing: 6) {
                    Label(message, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange)
                    if let url = FeedbackSender.mailURL(report) {
                        Button("Send by Email Instead") { NSWorkspace.shared.open(url); close() }.controlSize(.small)
                    }
                }
            }

            HStack {
                Text("No notifications, mail or chats are included.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: close).keyboardShortcut(.cancelAction)
                Button {
                    Task { await submit() }
                } label: {
                    if phase == .sending {
                        HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Sending…") }
                    } else {
                        Text("Send Report")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!report.isReady || !report.replyIsValid || phase == .sending)
            }
        }
        .padding(22)
        .padding(.top, 8)
    }

    private var sent: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 54))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: phase)
            Text("Report sent").font(.title2.weight(.semibold))
            Text(report.replyTo.isEmpty ? "Thanks for helping make Desktop Buddy better."
                                        : "Thanks! We'll reply to \(report.replyTo) if we need more details.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Done", action: close).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).padding(.top, 6)
        }
        .padding(36)
        .frame(maxWidth: .infinity)
    }

    private func submit() async {
        phase = .sending
        if FeedbackSender.key == nil, let url = FeedbackSender.mailURL(report) {
            // No form service set up: hand over to the mail app with everything filled in.
            NSWorkspace.shared.open(url)
            close()
            return
        }
        do {
            try await FeedbackSender.send(report)
            phase = .sent
            NSSound(named: "Glass")?.play()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
