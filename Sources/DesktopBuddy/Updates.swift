import SwiftUI
import AppKit
import CryptoKit
import Security

/// Asks GitHub Releases whether a newer version exists: one anonymous GET, nothing about
/// the person or their accounts is sent. "Update and Restart" then downloads the new DMG,
/// checks it (checksum, same app, newer version, signed by the same team certificate),
/// swaps the app in place and reopens it.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()
    static let latestAPI: URL = {
        // DESKTOPBUDDY_UPDATE_FEED lets the update be tested against a local release (file:// URLs).
        if let feed = ProcessInfo.processInfo.environment["DESKTOPBUDDY_UPDATE_FEED"], let u = URL(string: feed) { return u }
        return URL(string: "https://api.github.com/repos/abhisheksaggam-design/desktop-buddy/releases/latest")!
    }()
    static let releasesPage = URL(string: "https://github.com/abhisheksaggam-design/desktop-buddy/releases/latest")!

    struct Release: Equatable {
        var version: String
        var page: URL
        var download: URL?
        var checksum: URL?
    }

    enum InstallPhase: Equatable {
        case idle, downloading, checking, restarting
        case failed(String)
    }

    @Published private(set) var available: Release?
    @Published private(set) var checking = false
    @Published private(set) var lastChecked: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var phase: InstallPhase = .idle
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
            guard (response as? HTTPURLResponse).map({ $0.statusCode == 200 }) ?? true,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else { throw URLError(.badServerResponse) }
            let version = Self.version(fromTag: tag)
            let page = (json["html_url"] as? String).flatMap(URL.init(string:)) ?? Self.releasesPage
            let assets = json["assets"] as? [[String: Any]] ?? []
            func asset(_ suffix: String) -> URL? {
                (assets.first { ($0["name"] as? String)?.lowercased().hasSuffix(suffix) == true }?["browser_download_url"] as? String)
                    .flatMap(URL.init(string:))
            }
            available = Self.isNewer(version, than: currentVersion)
                ? Release(version: version, page: page, download: asset(".dmg"), checksum: asset(".dmg.sha256")) : nil
            lastError = nil
        } catch {
            lastError = "Couldn't check for updates. Check your internet connection and try again."
        }
        lastChecked = Date()
    }

    /// Whether this release can be installed from inside the app (older releases have no checksum).
    var canInstallInPlace: Bool {
        guard let r = available else { return false }
        return r.download != nil && r.checksum != nil
            && FileManager.default.isWritableFile(atPath: Bundle.main.bundleURL.deletingLastPathComponent().path)
    }

    /// Downloads, checks and installs the update, then restarts. Anything unexpected stops it
    /// with a message; "Download Manually" is always the way out.
    func installAndRestart() async {
        guard let r = available, let dmgURL = r.download, let sumURL = r.checksum else { return }
        guard phase == .idle || phase.isFailure else { return }
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("DesktopBuddyUpdate-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            phase = .downloading
            let (tmp, _) = try await URLSession.shared.download(from: dmgURL)
            let dmg = work.appendingPathComponent("Desktop-Buddy.dmg")
            try FileManager.default.moveItem(at: tmp, to: dmg)
            let (sumData, _) = try await URLSession.shared.data(from: sumURL)

            phase = .checking
            let staged = try await Task.detached { () throws -> URL in
                guard let expected = Self.expectedChecksum(String(decoding: sumData, as: UTF8.self)),
                      try Self.sha256(of: dmg) == expected else { throw UpdateError("The download didn't match. Try again later.") }
                let app = try Self.extractApp(from: dmg, into: work)
                try Self.verify(app)
                return app
            }.value

            phase = .restarting
            try Self.swapAndRelaunch(staged: staged, target: Bundle.main.bundleURL, work: work)
            NSApp.terminate(nil)
        } catch {
            try? FileManager.default.removeItem(at: work)
            phase = .failed((error as? UpdateError)?.message ?? "Couldn't download the update. Check your internet connection and try again.")
        }
    }

    struct UpdateError: Error {
        var message: String
        init(_ m: String) { message = m }
    }

    /// "abc123…  Desktop-Buddy.dmg" (shasum format) → "abc123…"
    nonisolated static func expectedChecksum(_ text: String) -> String? {
        let first = text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).first.map(String.init)?.lowercased()
        guard let first, first.count == 64, first.allSatisfy(\.isHexDigit) else { return nil }
        return first
    }

    nonisolated static func sha256(of url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Mounts the DMG read-only (hidden from Finder), copies the app out, unmounts.
    nonisolated static func extractApp(from dmg: URL, into work: URL) throws -> URL {
        let mount = work.appendingPathComponent("mnt")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        try run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path])
        defer { _ = try? run("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) }
        let source = mount.appendingPathComponent("Desktop Buddy.app")
        guard FileManager.default.fileExists(atPath: source.path) else { throw UpdateError("The update doesn't contain Desktop Buddy.") }
        let staged = work.appendingPathComponent("Desktop Buddy.app")
        try run("/usr/bin/ditto", [source.path, staged.path])
        return staged
    }

    /// Same app, newer version, intact signature from the same certificate as this copy.
    nonisolated static func verify(_ app: URL) throws {
        guard let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
              let version = info["CFBundleShortVersionString"] as? String else {
            throw UpdateError("The update isn't Desktop Buddy.")
        }
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        guard isNewer(version, than: current) else { throw UpdateError("The update isn't newer than this version.") }

        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else {
            throw UpdateError("The update isn't signed.")
        }
        // Builds signed with the team certificate only accept updates signed with it too.
        let requirement = signedByTeamCertificate() ? designatedRequirement() : nil
        guard SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate),
                                         requirement) == errSecSuccess else {
            throw UpdateError("The update isn't signed by Desktop Buddy, so it wasn't installed.")
        }
    }

    /// This running copy's identity ("com.desktopbuddy.v2, signed by our certificate").
    nonisolated static func designatedRequirement() -> SecRequirement? {
        var me: SecCode?
        var staticMe: SecStaticCode?
        var req: SecRequirement?
        guard SecCodeCopySelf([], &me) == errSecSuccess, let me,
              SecCodeCopyStaticCode(me, [], &staticMe) == errSecSuccess, let staticMe,
              SecCodeCopyDesignatedRequirement(staticMe, [], &req) == errSecSuccess else { return nil }
        return req
    }

    /// False for ad-hoc (local test) builds, whose identity changes with every build.
    nonisolated static func signedByTeamCertificate() -> Bool {
        var me: SecCode?
        var staticMe: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &me) == errSecSuccess, let me,
              SecCodeCopyStaticCode(me, [], &staticMe) == errSecSuccess, let staticMe,
              SecCodeCopySigningInformation(staticMe, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return false }
        return (dict[kSecCodeInfoCertificates as String] as? [Any])?.isEmpty == false
    }

    /// A tiny helper waits for this app to quit, swaps the new copy in (restoring the old one if
    /// anything fails), reopens it and cleans up.
    nonisolated static func swapAndRelaunch(staged: URL, target: URL, work: URL) throws {
        let script = work.appendingPathComponent("swap.sh")
        try """
        #!/bin/sh
        while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
        rm -rf "$3.old"
        if mv "$3" "$3.old" && /usr/bin/ditto "$2" "$3"; then
          rm -rf "$3.old"
        else
          rm -rf "$3"; mv "$3.old" "$3"
        fi
        [ "$5" = "relaunch" ] && /usr/bin/open "$3"
        rm -rf "$4"
        """.write(to: script, atomically: true, encoding: .utf8)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Local update tests (DESKTOPBUDDY_UPDATE_FEED) swap but don't reopen, so nothing touches your real data.
        let relaunch = ProcessInfo.processInfo.environment["DESKTOPBUDDY_UPDATE_FEED"] == nil ? "relaunch" : "test"
        p.arguments = [script.path, "\(ProcessInfo.processInfo.processIdentifier)", staged.path, target.path, work.path, relaunch]
        try p.run()
    }

    @discardableResult
    nonisolated private static func run(_ tool: String, _ args: [String]) throws -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw UpdateError("Couldn't open the update. Try Download Manually.") }
        return p.terminationStatus
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

extension UpdateChecker.InstallPhase {
    var isFailure: Bool { if case .failed = self { return true } else { return false } }
    var busyText: String? {
        switch self {
        case .downloading: return "Downloading…"
        case .checking: return "Checking the download…"
        case .restarting: return "Restarting…"
        default: return nil
        }
    }
}

/// The primary update button: Update and Restart when possible, otherwise Download.
struct UpdateButton: View {
    @ObservedObject var updates = UpdateChecker.shared
    var small = false

    var body: some View {
        if let busy = updates.phase.busyText {
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text(busy).foregroundStyle(.secondary) }
                .font(small ? .caption : .callout)
        } else if updates.canInstallInPlace {
            Button("Update and Restart") { Task { await updates.installAndRestart() } }
                .buttonStyle(.borderedProminent).controlSize(small ? .small : .regular)
        } else {
            Button("Download") { updates.download() }
                .buttonStyle(.borderedProminent).controlSize(small ? .small : .regular)
        }
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
                    if case .failed(let message) = updates.phase {
                        Text(message).font(.caption).foregroundStyle(.orange)
                    } else {
                        Text("Your accounts and settings stay as they are.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 6)
                if updates.phase == .idle || updates.phase.isFailure {
                    Button("Later") { dismissed = r.version }
                        .buttonStyle(.borderless).font(.callout).foregroundStyle(.secondary)
                }
                UpdateButton(small: true)
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
                        if updates.phase.isFailure && updates.canInstallInPlace {
                            Button("Download Manually") { updates.download() }
                        }
                        UpdateButton()
                    }
                } label: {
                    Text("Desktop Buddy \(r.version) is available")
                    if case .failed(let message) = updates.phase {
                        Text(message).foregroundStyle(.orange)
                    } else if updates.canInstallInPlace {
                        Text("Desktop Buddy downloads it, checks it and restarts. Your accounts and settings stay.")
                    } else {
                        Text("Download it, open it and drag Desktop Buddy into Applications.")
                    }
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
