import Foundation
import AppKit
import Combine

/// Live health of one service (e.g. "Teams chats") for one account.
struct Snoozed: Codable, Equatable {
    var item: BuddyItem
    var until: Date
}

struct ServiceStatus: Equatable {
    var lastChecked: Date?
    var count = 0
    var error: String?
    var fixURL: URL?
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var config: AppConfig { didSet { JSONFile.save(config, to: Paths.config) } }
    @Published private(set) var items: [BuddyItem] = [] { didSet { JSONFile.save(items, to: Paths.inbox) } }
    @Published var expanded = false
    @Published var filterOwner: String?             // nil = show every owner in the list
    @Published var lastArrival: BuddyItem?          // drives the speech bubble
    @Published var serviceStatus: [String: ServiceStatus] = [:]   // "<accountID>.<source>"
    @Published var signedIn: Set<String> = []                     // account IDs with a saved sign-in
    @Published var checking: Set<String> = []                     // account IDs being checked right now
    @Published private(set) var snoozed: [Snoozed] = [] { didSet { JSONFile.save(snoozed, to: Paths.snoozed) } }
    @Published var screenshotsAllowedUntil: Date?                // "Allow Screenshots for 1 Minute"
    @Published var coachStep: CoachStep?                          // tip showing in the menu bar dropdown
    @Published var expired: Set<String> = []                      // account IDs whose sign-in the provider rejected

    /// accountID -> the address that actually signed in, when it isn't the account's email.
    @Published var wrongAccount: [String: String] = [:]

    /// True when the account can't be checked until you sign in (never, expired, or as someone else).
    func needsSignIn(_ id: String) -> Bool { !signedIn.contains(id) || expired.contains(id) || wrongAccount[id] != nil }

    /// Muted mail IDs, so Gmail doesn't download them again every check. Cleared when mute rules change.
    var mutedMail: Set<String> = []

    /// IDs already shown (or dismissed) so they never pop up twice.
    private var seen: [String] = [] { didSet { JSONFile.save(seen, to: Paths.seen) } }
    private var seenSet: Set<String> = []

    private init() {
        config = JSONFile.load(AppConfig.self, from: Paths.config) ?? AppConfig()
        var loaded = JSONFile.load([BuddyItem].self, from: Paths.inbox) ?? []
        // v1 items only had a label; attach them to the matching account.
        for i in loaded.indices where loaded[i].accountID == nil && loaded[i].accountLabel != nil {
            loaded[i].accountID = config.accounts.first { $0.label == loaded[i].accountLabel }?.id
        }
        items = loaded
        seen = JSONFile.load([String].self, from: Paths.seen) ?? []
        snoozed = JSONFile.load([Snoozed].self, from: Paths.snoozed) ?? []
        seenSet = Set(seen)
        refreshSignedIn()
        seedDefaultClients()
        DispatchQueue.main.async { AppState.shared.reassignClients() }   // sort what's already on screen
    }

    /// First run of v3: add the team's known clients (logos are bundled). Rules can be edited in Settings.
    private func seedDefaultClients() {
        guard config.seededClients != true else { return }
        let existing = Set(config.clients.map { $0.name.lowercased() })
        for (name, tint) in [("Gatehouse", AccountTint.green), ("RiskHawk", AccountTint.orange)] where !existing.contains(name.lowercased()) {
            config.clients.append(ClientConfig(name: name, tintChoice: tint, keywords: [name]))
        }
        config.seededClients = true
    }

    // MARK: - Clients

    func addClient(_ c: ClientConfig) {
        config.clients.append(c)
        reassignClients()
    }

    func updateClient(_ c: ClientConfig) {
        guard let i = config.clients.firstIndex(where: { $0.id == c.id }) else { return }
        config.clients[i] = c
        reassignClients()
    }

    func removeClient(_ id: String) {
        config.clients.removeAll { $0.id == id }
        reassignClients()
    }

    /// Re-applies client rules to everything on screen (after rules change).
    func reassignClients() {
        var changed = items
        for i in changed.indices {
            guard let acc = changed[i].accountID else { continue }
            changed[i].clientID = ClientMatcher.assign([changed[i]], accountID: acc).first?.clientID
        }
        if changed != items { items = changed }
        tidyAfterRemoval()
    }

    // MARK: - Accounts

    func account(_ id: String) -> AccountConfig? { config.accounts.first { $0.id == id } }

    func refreshSignedIn() {
        signedIn = Set(config.accounts.filter(OAuth.isSignedIn).map(\.id))
    }

    func addAccount(_ a: AccountConfig) {
        config.accounts.append(a)
        refreshSignedIn()
    }

    func removeAccount(_ id: String) {
        guard let a = account(id) else { return }
        Task { await OAuth.shared.forget(a) }
        config.accounts.removeAll { $0.id == id }
        for i in config.clients.indices {
            config.clients[i].chats.removeAll { $0.accountID == id }
            config.clients[i].accountIDs.removeAll { $0 == id }
        }
        items.removeAll { $0.accountID == id }
        serviceStatus = serviceStatus.filter { !$0.key.hasPrefix(id + ".") }
        signedIn.remove(id)
        tidyAfterRemoval()
    }

    func update(_ a: AccountConfig) {
        guard let i = config.accounts.firstIndex(where: { $0.id == a.id }) else { return }
        let old = config.accounts[i]
        config.accounts[i] = a
        if old.mutedSenders != a.mutedSenders || old.mutedKeywords != a.mutedKeywords || old.onlyLabelsList != a.onlyLabelsList {
            // Rules changed: muted mail may now be wanted (forget the cache), and newly muted mail leaves at once.
            mutedMail = mutedMail.filter { !$0.hasPrefix("mail:\(a.id):") }
            let before = items.count
            items.removeAll { $0.accountID == a.id && MailFilter.isMuted($0, a) }
            if items.count != before { tidyAfterRemoval() }
        }
        // Turning a service off clears what it was showing.
        let watched: [(ItemSource, Bool)] = [(.mail, a.watchMail), (.chat, a.watchChat), (.meeting, a.watchMeetings), (.task, a.watchTasks)]
        let off = watched.filter { !$0.1 }.map(\.0)
        if !a.enabled || !off.isEmpty {
            items.removeAll { $0.accountID == a.id && (!a.enabled || off.contains($0.source)) }
            tidyAfterRemoval()
        }
    }

    func status(_ accountID: String, _ source: ItemSource) -> ServiceStatus {
        serviceStatus["\(accountID).\(source.rawValue)"] ?? ServiceStatus()
    }

    func setStatus(_ accountID: String, _ source: ItemSource, _ s: ServiceStatus) {
        serviceStatus["\(accountID).\(source.rawValue)"] = s
    }

    func errorCount(for accountID: String) -> Int {
        ItemSource.allCases.filter { status(accountID, $0).error != nil }.count
    }

    // MARK: - Incoming

    /// Adds items that have never been seen before. Returns how many were new.
    @discardableResult
    func offer(_ incoming: [BuddyItem]) -> Int {
        let fresh = incoming.filter { !seenSet.contains($0.id) }
        guard !fresh.isEmpty else { return 0 }
        for item in fresh { markSeen(item.id) }
        items.insert(contentsOf: fresh.sorted { $0.date > $1.date }, at: 0)
        lastArrival = fresh.max { $0.date < $1.date }
        if config.playSound, let lead = Sounds.leadSource(of: fresh) { Sounds.play(config.sound(for: lead)) }
        return fresh.count
    }

    /// Removes items of a source/account that are no longer "live" upstream —
    /// e.g. the mail was read, the task completed, the meeting is over.
    func reconcile(source: ItemSource, accountID: String, liveIDs: Set<String>) {
        let before = items.count
        items.removeAll { $0.source == source && $0.accountID == accountID && !liveIDs.contains($0.id) }
        if items.count != before { tidyAfterRemoval() }
    }

    /// Updates text on items already on screen (e.g. "Starts in 3 min").
    func refreshDetails(_ fresh: [BuddyItem]) {
        for f in fresh {
            if let i = items.firstIndex(where: { $0.id == f.id }), items[i].detail != f.detail {
                items[i].detail = f.detail
            }
        }
    }

    /// Lets a repeating item (meeting, task, reminder) show again later.
    func forget(_ id: String) {
        seenSet.remove(id)
        seen.removeAll { $0 == id }
    }

    /// Self-test only: forget everything seen/snoozed so each scenario starts clean.
    func resetForTesting() {
        seen = []; seenSet = []; snoozed = []; items = []
        expired = []; wrongAccount = [:]; serviceStatus = [:]; mutedMail = []
    }

    /// Removes sample items left over from a `--demo` run.
    func purgeDemoItems() {
        items.removeAll { $0.id.hasPrefix("test:") }
        tidyAfterRemoval()
    }

    // MARK: - User actions

    func dismiss(_ id: String) {
        items.removeAll { $0.id == id }
        tidyAfterRemoval()
    }

    func clearAll(owner: String? = nil) {
        if let owner { items.removeAll { $0.owner == owner } } else { items.removeAll() }
        tidyAfterRemoval()
    }

    func open(_ item: BuddyItem) {
        if let url = item.url { NSWorkspace.shared.open(url) }
        dismiss(item.id)
    }

    /// Snoozes survive quitting the app: they're saved and brought back by `wakeSnoozed`.
    func snooze(_ item: BuddyItem, minutes: Int = 10, now: Date = Date()) {
        dismiss(item.id)
        snoozed.removeAll { $0.item.id == item.id }
        snoozed.append(Snoozed(item: item, until: now.addingTimeInterval(Double(minutes) * 60)))
    }

    /// Called on the reminder tick: returns due snoozes to the screen.
    func wakeSnoozed(now: Date = Date()) {
        let due = snoozed.filter { $0.until <= now }
        guard !due.isEmpty else { return }
        snoozed.removeAll { $0.until <= now }
        for s in due {
            var again = s.item
            again.date = now
            items.removeAll { $0.id == again.id }
            items.insert(again, at: 0)
            lastArrival = again
        }
    }

    /// Google Chat can't tell us what you've read, so chat notifications clear themselves after a day.
    func expireStaleChats(now: Date = Date(), after hours: Double = 24) {
        let before = items.count
        items.removeAll { $0.source == .chat && now.timeIntervalSince($0.date) > hours * 3600 }
        if items.count != before { tidyAfterRemoval() }
    }

    // MARK: - Owners (one character per account, plus your reminders)

    /// Owners that currently have something to show, in a stable left-to-right order.
    var activeOwners: [String] {
        let order = config.clients.map(\.id) + config.accounts.map(\.id) + [reminderOwner]
        let present = Set(items.map(\.owner))
        return order.filter(present.contains)
    }

    func ownerName(_ owner: String) -> String {
        if owner == reminderOwner { return "Reminders" }
        return account(owner)?.label ?? client(owner)?.name ?? "Account"
    }

    func ownerTint(_ owner: String) -> AccountTint {
        if owner == reminderOwner { return .teal }
        return account(owner)?.tint ?? client(owner)?.tint ?? .blue
    }

    func toggleList(for owner: String) {
        if expanded && filterOwner == owner { expanded = false; return }
        filterOwner = owner
        expanded = true
    }

    var isQuietNow: Bool { isQuiet(at: Date()) }

    func isQuiet(at date: Date) -> Bool {
        guard let s = config.quietStartHour, let e = config.quietEndHour, s != e else { return false }
        let h = Calendar.current.component(.hour, from: date)
        return s < e ? (h >= s && h < e) : (h >= s || h < e)
    }

    private func markSeen(_ id: String) {
        guard seenSet.insert(id).inserted else { return }
        seen.append(id)
        if seen.count > 3000 {
            let drop = seen.prefix(seen.count - 2500)
            drop.forEach { seenSet.remove($0) }
            seen.removeFirst(drop.count)
        }
    }

    private func tidyAfterRemoval() {
        if let last = lastArrival, !items.contains(where: { $0.id == last.id }) {
            lastArrival = nil
        }
        if items.isEmpty { expanded = false }
        if let f = filterOwner, !items.contains(where: { $0.owner == f }) { filterOwner = nil }
    }
}
