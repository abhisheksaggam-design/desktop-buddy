import SwiftUI
import AppKit

/// Asks GitHub Releases whether a newer version exists: one anonymous GET, nothing about
/// the person or their accounts is sent. Updating is still "download and drag to Applications".
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()
    static let latestAPI = URL(string: "https://api.github.com/repos/abhisheksaggam-design/desktop-buddy/releases/latest")!
    static let releasesPage = URL(string: "https://github.com/abhisheksaggam-design/desktop-buddy/releases/latest")!

    struct Release: Equatable {
        var version: String
        var page: URL
        var download: URL?
    }

    @Published private(set) var available: Release?
    @Published private(set) var checking = false
    @Published private(set) var lastChecked: Date?
    @Published private(set) var lastError: String?
    private var timer: Timer?

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Checks shortly after launch, then once a day, while automatic checks are on.
    func start() {
        timer?.invalidate()
        timer = nil
        guard AppState.shared.config.checkForUpdates else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { Task { await UpdateChecker.shared.check() } }
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { _ in
            Task { @MainActor in await UpdateChecker.shared.check() }
        }
    }

    func check() async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
        do {
            var req = URLRequest(url: Self.latestAPI, timeoutInterval: 20)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: req)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else { throw URLError(.badServerResponse) }
            let version = Self.version(fromTag: tag)
            let page = (json["html_url"] as? String).flatMap(URL.init(string:)) ?? Self.releasesPage
            let dmg = (json["assets"] as? [[String: Any]])?
                .first { ($0["name"] as? String)?.lowercased().hasSuffix(".dmg") == true }?["browser_download_url"] as? String
            available = Self.isNewer(version, than: currentVersion)
                ? Release(version: version, page: page, download: dmg.flatMap(URL.init(string:))) : nil
            lastError = nil
        } catch {
            lastError = "Couldn't check for updates. Check your internet connection and try again."
        }
        lastChecked = Date()
    }

    /// Downloads the new DMG in the browser (or opens the release page if it has none).
    func download() {
        guard let r = available else { return }
        NSWorkspace.shared.open(r.download ?? r.page)
    }

    func openReleaseNotes() { NSWorkspace.shared.open(available?.page ?? Self.releasesPage) }

    nonisolated static func version(fromTag tag: String) -> String {
        let t = tag.trimmingCharacters(in: .whitespaces)
        return t.lowercased().hasPrefix("v") ? String(t.dropFirst()) : t
    }

    /// "2.10" is newer than "2.9"; missing parts count as 0, so "2.1" equals "2.1.0".
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] { s.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 } }
        let pa = parts(a), pb = parts(b)
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

/// Shown at the top of the menu bar popover when a newer version is out. "Later" hides it
/// until the next version.
struct UpdateBanner: View {
    @ObservedObject var updates = UpdateChecker.shared
    @AppStorage("dismissedUpdateVersion") private var dismissed = ""

    var body: some View {
        if let r = updates.available, r.version != dismissed {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 22)).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Desktop Buddy \(r.version) is available").font(.callout.weight(.semibold))
                    Text("Your accounts and settings stay as they are.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                Button("Later") { dismissed = r.version }
                    .buttonStyle(.borderless).font(.callout).foregroundStyle(.secondary)
                Button("Download") { updates.download() }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Color.accentColor.opacity(0.08))
        }
    }
}

/// Settings → General: current version, status, Check Now, and the automatic-check switch.
struct UpdatesSection: View {
    @ObservedObject var updates = UpdateChecker.shared
    @ObservedObject var state = AppState.shared

    var body: some View {
        Section {
            LabeledContent("Version", value: updates.currentVersion)
            if let r = updates.available {
                LabeledContent {
                    HStack(spacing: 8) {
                        Button("What's New") { updates.openReleaseNotes() }
                        Button("Download") { updates.download() }.buttonStyle(.borderedProminent)
                    }
                } label: {
                    Text("Desktop Buddy \(r.version) is available")
                    Text("Download it, open it and drag Desktop Buddy into Applications.")
                }
            } else {
                LabeledContent {
                    if updates.checking {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Check Now") { Task { await updates.check() } }
                    }
                } label: {
                    Text(updates.lastError != nil ? "Couldn't check" : updates.lastChecked == nil ? "Not checked yet" : "Up to date")
                    Text(statusLine)
                }
            }
            Toggle("Check for Updates Automatically", isOn: $state.config.checkForUpdates)
                .onChange(of: state.config.checkForUpdates) { _, _ in updates.start() }
        } header: {
            Text("Updates")
        } footer: {
            Footnote("Desktop Buddy asks GitHub once a day whether a newer version exists. Nothing about you or your accounts is sent.")
        }
    }

    private var statusLine: String {
        if let e = updates.lastError { return e }
        guard let d = updates.lastChecked else { return "Checks automatically once a day" }
        return "Checked \(d.formatted(.relative(presentation: .named)))"
    }
}
