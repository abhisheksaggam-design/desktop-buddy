import SwiftUI
import AppKit

// MARK: - Logos

enum Logos {
    /// Bundled logos (Resources/Logos/<key>.png), matched by account/client name or email domain.
    static let bundledKeys = ["dynamatix", "iehub", "riskhawk", "gatehouse"]

    static func bundledURL(_ key: String) -> URL? {
        Bundle.main.url(forResource: key, withExtension: "png", subdirectory: "Logos")
            ?? devURL(key)
    }

    /// When running from `swift run`, read straight from the project folder.
    private static func devURL(_ key: String) -> URL? {
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        var dir = exe.deletingLastPathComponent()
        for _ in 0..<5 {
            let u = dir.appendingPathComponent("Resources/Logos/\(key).png")
            if FileManager.default.fileExists(atPath: u.path) { return u }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }

    static func guessKey(name: String, email: String = "") -> String? {
        let hay = (name + " " + email).lowercased().replacingOccurrences(of: " ", with: "")
        return bundledKeys.first { hay.contains($0) }
    }

    static func url(path: String?, name: String, email: String = "") -> URL? {
        if let path, FileManager.default.fileExists(atPath: path) { return URL(fileURLWithPath: path) }
        return guessKey(name: name, email: email).flatMap(bundledURL)
    }

    private static var cache: [String: NSImage] = [:]
    static func image(_ url: URL?) -> NSImage? {
        guard let url else { return nil }
        if let img = cache[url.path] { return img }
        let img = NSImage(contentsOf: url)
        cache[url.path] = img
        return img
    }

    /// Copies a picked image into Application Support so it survives the original moving.
    static func importImage(from src: URL, as name: String) -> String? {
        let dir = Paths.supportDir.appendingPathComponent("Logos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dst = dir.appendingPathComponent("\(name)-\(UUID().uuidString.prefix(6)).\(src.pathExtension.lowercased())")
        do { try FileManager.default.copyItem(at: src, to: dst); cache[dst.path] = nil; return dst.path } catch { return nil }
    }

    @MainActor
    static func choose() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .gif, .webP, .svg, .tiff]
        panel.message = "Choose a logo (a square PNG works best)"
        return panel.runModal() == .OK ? panel.url : nil
    }
}

/// App-icon–style logo tile: white continuous-corner square, logo fitted inside,
/// monogram fallback in the owner's colour.
struct LogoTile: View {
    var url: URL?
    var name: String
    var tint: Color
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous).fill(.white)
            if let img = Logos.image(url) {
                Image(nsImage: img).resizable().interpolation(.high).scaledToFit()
                    .padding(size * 0.14)
            } else {
                Text(monogram).font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(tint.gradient)
            }
        }
        .frame(width: size, height: size)
        .overlay(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous).stroke(.black.opacity(0.08), lineWidth: 0.5))
        .accessibilityLabel("\(name) logo")
    }

    private var monogram: String {
        let words = name.split(separator: " ").prefix(2)
        return words.map { String($0.prefix(1)) }.joined().uppercased()
    }
}

// MARK: - Owner presentation (account, client or reminders)

extension AppState {
    func client(_ id: String) -> ClientConfig? { config.clients.first { $0.id == id } }

    func ownerLogoURL(_ owner: String) -> URL? {
        if let a = account(owner) { return Logos.url(path: a.logoPath, name: a.label, email: a.email) }
        if let c = client(owner) { return Logos.url(path: c.logoPath, name: c.name) }
        return config.reminderLogoPath.map { URL(fileURLWithPath: $0) }
    }
}

/// Buddy shown on screen for an owner: its logo tile.
/// Static by design: no idle motion. A new arrival gets one soft ring pulse (skipped with Reduce Motion).
struct OwnerBuddy: View {
    let owner: String
    var excited: Bool
    var size: CGFloat = 64
    @ObservedObject var state = AppState.shared
    @Local private var ring = false

    var body: some View {
        tile
            .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
            .background(
                RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                    .stroke(ownerColor(owner), lineWidth: 3)
                    .scaleEffect(ring ? 1.35 : 1)
                    .opacity(ring ? 0 : 0.9)
                    .opacity(excited ? 1 : 0)
            )
            .onChange(of: excited) { _, on in
                ring = false
                guard on, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
                withAnimation(.easeOut(duration: 0.9)) { ring = true }
            }
    }

    @ViewBuilder private var tile: some View {
        if owner == reminderOwner && state.config.reminderLogoPath == nil {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.225, style: .continuous).fill(Color.teal.gradient)
                Image(systemName: "bell.fill").font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(.white)
            }
            .frame(width: size, height: size)
        } else {
            LogoTile(url: state.ownerLogoURL(owner), name: state.ownerName(owner), tint: ownerColor(owner), size: size)
        }
    }
}

// MARK: - Client rules

enum ClientMatcher {
    /// Tags items with the first enabled client whose rules match. Returns the items tagged.
    @MainActor
    static func assign(_ items: [BuddyItem], accountID: String) -> [BuddyItem] {
        let clients = AppState.shared.config.clients.filter { $0.enabled && ($0.accountIDs.isEmpty || $0.accountIDs.contains(accountID)) }
        // Always recompute (no early return), so turning a client off clears its old tags.
        return items.map { item in
            var x = item
            x.clientID = clients.first { matches($0, item) }?.id
            return x
        }
    }

    static func matches(_ c: ClientConfig, _ item: BuddyItem) -> Bool {
        switch item.source {
        case .mail:
            if c.senders.contains(where: { senderMatches($0, item) }) { return true }
            return c.keywords.contains { containsWord($0, in: mailText(item)) }
        case .chat:
            if let ref = item.chatRef, c.chats.contains(where: { $0.chatID == ref && $0.accountID == item.accountID }) { return true }
            guard c.matchChatNames else { return false }
            if containsWord(c.name, in: item.title) { return true }
            // Direct messages have no name; match the person you're talking to instead.
            return item.title == "Direct message" && containsWord(c.name, in: item.from ?? "")
        default:
            return false
        }
    }

    /// A domain rule ("gatehouse.co.uk") matches it and its subdomains; an address rule matches exactly.
    static func senderMatches(_ rule: String, _ item: BuddyItem) -> Bool {
        let addr = (item.fromAddress ?? "").lowercased()
        let r = rule.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " @"))
        guard !r.isEmpty else { return false }
        return r.contains("@") ? addr == r : (addr.hasSuffix("@" + r) || addr.hasSuffix("." + r))
    }

    /// What keywords are looked for in: subject, preview and sender name.
    static func mailText(_ item: BuddyItem) -> String {
        item.title + " " + (item.detail ?? "") + " " + (item.from ?? "")
    }

    /// Case-insensitive match on word boundaries: "Hub" matches "IE Hub team" but not "GitHub".
    static func containsWord(_ needle: String, in haystack: String) -> Bool {
        let n = needle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return false }
        let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: n) + "(?![\\p{L}\\p{N}])"
        return haystack.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

// MARK: - Muted mail

/// An account's mute rules: mail from these senders, or with these words, never pops up.
enum MailFilter {
    static func isMuted(_ item: BuddyItem, _ account: AccountConfig) -> Bool {
        guard item.source == .mail else { return false }
        return account.mutedSenders.contains { ClientMatcher.senderMatches($0, item) }
            || account.mutedKeywords.contains { ClientMatcher.containsWord($0, in: ClientMatcher.mailText(item)) }
    }

    /// Drops muted mail from a fetch, including from the live IDs, so muted mail already on screen clears too.
    /// Returns the IDs dropped.
    static func apply(_ result: inout FetchResult, _ account: AccountConfig) -> Set<String> {
        guard result.source == .mail else { return [] }
        let muted = Set(result.items.filter { isMuted($0, account) }.map(\.id))
        guard !muted.isEmpty else { return [] }
        result.items.removeAll { muted.contains($0.id) }
        result.liveIDs.subtract(muted)
        return muted
    }
}

// MARK: - Chat directory (for picking client chats)

enum ChatDirectory {
    /// Names for unnamed Google Chat DMs / group chats, cached on disk (space -> name).
    private static let cacheURL = Paths.supportDir.appendingPathComponent("chat-names.json")

    /// Lists the Google Chat spaces / Teams chats you're in, most recently active first.
    /// `progress(done, total)` reports name lookups for direct messages.
    static func list(_ account: AccountConfig,
                     progress: @escaping @MainActor (Int, Int) -> Void = { _, _ in }) async throws -> [ChatRef] {
        switch account.provider {
        case .google: return try await google(account, progress: progress)
        case .microsoft: return try await microsoft(account)
        }
    }

    private static func google(_ account: AccountConfig, progress: @escaping @MainActor (Int, Int) -> Void) async throws -> [ChatRef] {
        let api = APIClient(account: account)
        var raw: [[String: Any]] = []
        var token: String?
        repeat {
            var q = ["pageSize": "200"]
            if let token { q["pageToken"] = token }
            let page = try await api.get("https://chat.googleapis.com/v1/spaces", q)
            raw += page["spaces"] as? [[String: Any]] ?? []
            token = page["nextPageToken"] as? String
        } while token != nil && raw.count < 1000

        // Google gives DMs and many group chats no name: name them after the people in them.
        let me = "users/" + ((try? await api.get("https://openidconnect.googleapis.com/v1/userinfo"))?["sub"] as? String ?? "")
        var cache = JSONFile.load([String: String].self, from: cacheURL) ?? [:]
        let unnamed = raw.compactMap { s -> String? in
            guard let id = s["name"] as? String,
                  ((s["displayName"] as? String) ?? "").isEmpty, cache[id] == nil else { return nil }
            return id
        }
        var done = 0
        await progress(0, unnamed.count)
        // Look names up a few at a time (polite to the API, fast enough for a few hundred chats).
        for batch in stride(from: 0, to: unnamed.count, by: 8).map({ Array(unnamed[$0..<min($0 + 8, unnamed.count)]) }) {
            await withTaskGroup(of: (String, String?).self) { group in
                for id in batch { group.addTask { (id, await peopleIn(id, me: me, api: api)) } }
                for await (id, name) in group {
                    if let name { cache[id] = name }
                    done += 1
                }
            }
            await progress(done, unnamed.count)
        }
        JSONFile.save(cache, to: cacheURL)

        return raw.compactMap { s -> ChatRef? in
            guard let id = s["name"] as? String else { return nil }
            let type = s["spaceType"] as? String ?? ""
            let kind: ChatRef.Kind = type == "DIRECT_MESSAGE" ? .direct : (type == "GROUP_CHAT" ? .group : .space)
            let named = (s["displayName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let name = named ?? cache[id] ?? (kind == .direct ? "Direct message (no recent messages)" : "Unnamed group chat")
            return ChatRef(accountID: account.id, chatID: id, name: name, kind: kind,
                           lastActive: parseDate(s["lastActiveTime"] as? String))
        }
        .sorted { ($0.lastActive ?? .distantPast) > ($1.lastActive ?? .distantPast) }
    }

    /// The other people in a chat, from its recent messages (needs only read access to messages).
    private static func peopleIn(_ space: String, me: String, api: APIClient) async -> String? {
        guard let page = try? await api.get("https://chat.googleapis.com/v1/\(space)/messages",
                                            ["pageSize": "25", "orderBy": "createTime desc"]) else { return nil }
        var names: [String] = []
        for m in page["messages"] as? [[String: Any]] ?? [] {
            let sender = m["sender"] as? [String: Any] ?? [:]
            guard (sender["name"] as? String) != me,
                  let n = (sender["displayName"] as? String).flatMap({ $0.isEmpty ? nil : $0 }),
                  !names.contains(n) else { continue }
            names.append(n)
            if names.count == 3 { break }
        }
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }

    private static func microsoft(_ account: AccountConfig) async throws -> [ChatRef] {
        let api = APIClient(account: account)
        let me = try await api.get("https://graph.microsoft.com/v1.0/me", ["$select": "id"])["id"] as? String
        let json = try await api.get("https://graph.microsoft.com/v1.0/me/chats",
                                     ["$expand": "members", "$top": "50", "$orderby": "lastMessagePreview/createdDateTime desc"])
        return (json["value"] as? [[String: Any]] ?? []).compactMap { c in
            guard let id = c["id"] as? String else { return nil }
            let others = (c["members"] as? [[String: Any]] ?? [])
                .filter { ($0["userId"] as? String) != me }
                .compactMap { $0["displayName"] as? String }
            let topic = (c["topic"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let type = c["chatType"] as? String ?? ""
            return ChatRef(accountID: account.id, chatID: id,
                           name: topic ?? (others.isEmpty ? "Chat" : others.prefix(3).joined(separator: ", ")),
                           kind: type == "oneOnOne" ? .direct : .group,
                           lastActive: graphDate(c["lastUpdatedDateTime"] as? String))
        }
    }
}

/// The Desktop Buddy app mark (Dynamatix tree) in an app-icon tile.
struct AppMark: View {
    var size: CGFloat = 64
    var body: some View {
        LogoTile(url: Logos.bundledURL("dynamatix"), name: "Desktop Buddy", tint: .brown, size: size)
            .shadow(color: .black.opacity(0.15), radius: size * 0.06, y: size * 0.03)
    }
}

/// Account logo with a small provider badge in the corner (Google "G" / Microsoft squares).
struct AccountMark: View {
    let account: AccountConfig
    var size: CGFloat = 20
    @ObservedObject var state = AppState.shared
    var body: some View {
        LogoTile(url: state.ownerLogoURL(account.id), name: account.label, tint: account.tint.color, size: size)
            .overlay(alignment: .bottomTrailing) {
                ProviderBadge(provider: account.provider, size: size * 0.5)
                    .shadow(color: .black.opacity(0.2), radius: 1)
                    .offset(x: size * 0.15, y: size * 0.15)
            }
            .accessibilityLabel("\(account.label), \(account.provider.name)")
    }
}
