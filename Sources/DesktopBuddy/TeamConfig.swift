import Foundation

/// Shared OAuth clients for the whole team, so teammates only click "Sign in".
///
/// Looked up in order:
///   1. `~/Library/Application Support/DesktopBuddy/team.json`  (per-Mac override)
///   2. `Desktop Buddy.app/Contents/Resources/team.json`         (bundled by build-app.sh)
///
/// {
///   "googleClientID": "…apps.googleusercontent.com",
///   "googleClientSecret": "GOCSPX-…",        // only for Desktop-type clients; leave out for an iOS-type client
///   "microsoftClientID": "00000000-0000-…",  // Entra app, "Mobile and desktop" platform, public client
///   "microsoftTenant": "organizations"        // or "common" / a specific tenant ID
/// }
struct TeamConfig: Codable {
    var googleClientID: String?
    var googleClientSecret: String?
    var microsoftClientID: String?
    var microsoftTenant: String?

    static var current: TeamConfig {
        let local = Paths.supportDir.appendingPathComponent("team.json")
        if let cfg = JSONFile.load(TeamConfig.self, from: local) { return cfg }
        if let url = Bundle.main.url(forResource: "team", withExtension: "json"),
           let cfg = JSONFile.load(TeamConfig.self, from: url) { return cfg }
        return TeamConfig()
    }

    static var source: String {
        if FileManager.default.fileExists(atPath: Paths.supportDir.appendingPathComponent("team.json").path) {
            return "This Mac (Application Support/DesktopBuddyV2/team.json)"
        }
        if Bundle.main.url(forResource: "team", withExtension: "json") != nil { return "Built into the app" }
        return "Not set up"
    }

    static var localURL: URL { Paths.supportDir.appendingPathComponent("team.json") }

    /// Saves this Mac's setup (Application Support), which takes priority over a bundled one.
    static func installLocal(_ cfg: TeamConfig) { JSONFile.save(cfg, to: localURL) }

    func hasClient(for provider: Provider) -> Bool {
        switch provider {
        case .google: return !(googleClientID ?? "").isEmpty      // the secret is optional (iOS-type clients have none)
        case .microsoft: return !(microsoftClientID ?? "").isEmpty
        }
    }
}
