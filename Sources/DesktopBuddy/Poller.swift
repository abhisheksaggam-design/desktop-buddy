import Foundation

/// Checks every connected account on a timer, plus local reminders every 20s.
@MainActor
final class Poller {
    static let shared = Poller()
    private var accountTimer: Timer?
    private var reminderTimer: Timer?
    private var running = false

    func start() {
        stop()
        let state = AppState.shared
        accountTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(max(30, state.config.pollSeconds)), repeats: true) { _ in
            Task { @MainActor in await Poller.shared.pollAll() }
        }
        reminderTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { _ in
            Task { @MainActor in Poller.shared.checkReminders() }
        }
        Task { await pollAll() }
        checkReminders()
    }

    func stop() {
        accountTimer?.invalidate()
        reminderTimer?.invalidate()
    }

    func pollAll() async {
        let state = AppState.shared
        guard !running, !state.config.paused else { return }
        running = true
        defer { running = false }
        for account in state.config.accounts where account.enabled && OAuth.isSignedIn(account) && !state.needsSignIn(account.id) {
            await poll(account)
        }
    }

    /// Checks one account now (also used by "Check Now" in Settings).
    func poll(_ account: AccountConfig) async {
        let state = AppState.shared
        state.checking.insert(account.id)
        defer { state.checking.remove(account.id) }

        let api = APIClient(account: account)
        let lead = state.config.meetingLeadMinutes
        var jobs: [(ItemSource, () async throws -> FetchResult)] = []
        switch account.provider {
        case .google:
            if account.watchMail { jobs.append((.mail, { try await GmailSource.fetch(api) })) }
            if account.watchChat { jobs.append((.chat, { try await ChatSource.shared.fetch(api) })) }
            if account.watchMeetings { jobs.append((.meeting, { try await CalendarSource.fetch(api, leadMinutes: lead) })) }
            if account.watchTasks { jobs.append((.task, { try await TasksSource.fetch(api) })) }
        case .microsoft:
            if account.watchMail { jobs.append((.mail, { try await OutlookMailSource.fetch(api) })) }
            if account.watchChat { jobs.append((.chat, { try await TeamsChatSource.shared.fetch(api) })) }
            if account.watchMeetings { jobs.append((.meeting, { try await OutlookCalendarSource.fetch(api, leadMinutes: lead) })) }
            if account.watchTasks { jobs.append((.task, { try await ToDoSource.fetch(api) })) }
        }

        for (source, job) in jobs {
            do {
                var result = try await job()
                state.mutedMail.formUnion(MailFilter.apply(&result, account))
                result.items = ClientMatcher.assign(result.items, accountID: account.id)
                state.reconcile(source: result.source, accountID: account.id, liveIDs: result.liveIDs)
                state.refreshDetails(result.items)
                let added = state.isQuietNow ? 0 : state.offer(result.items)
                state.setStatus(account.id, source, ServiceStatus(lastChecked: Date(), count: result.liveIDs.count))
                StatusLog.write("\(account.label) \(source.rawValue): fetched \(result.items.count), live \(result.liveIDs.count), new \(added)")
            } catch {
                let fix = (error as? APIError)?.fixURL
                state.setStatus(account.id, source, ServiceStatus(lastChecked: Date(), error: error.localizedDescription, fixURL: fix))
                StatusLog.write("\(account.label) \(source.rawValue): ERROR \(error.localizedDescription)")
                if case AuthError.notSignedIn = error { state.refreshSignedIn() }
                if case AuthError.expired = error {
                    // One expired sign-in breaks every service: flag the account once and stop.
                    state.expired.insert(account.id)
                    for s in ItemSource.allCases { state.setStatus(account.id, s, ServiceStatus()) }
                    StatusLog.write("\(account.label): sign-in expired")
                    return
                }
            }
        }
    }

    func checkReminders(now: Date = Date()) {
        let state = AppState.shared
        state.expireStaleChats(now: now)
        guard !state.config.paused, !state.isQuiet(at: now) else { return }
        state.wakeSnoozed(now: now)
        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)
        let weekday = cal.component(.weekday, from: now)

        for (i, r) in state.config.reminders.enumerated() where r.enabled {
            guard r.weekdays.contains(weekday), hour >= r.startHour, hour < r.endHour else { continue }
            if let last = r.lastFired, now.timeIntervalSince(last) < Double(r.everyMinutes) * 60 { continue }
            state.config.reminders[i].lastFired = now
            let id = "reminder:\(r.id.uuidString)"
            state.dismiss(id)          // replace an older, uncleared copy
            state.forget(id)
            state.offer([BuddyItem(id: id, source: .reminder, accountID: nil, accountLabel: nil,
                                   title: "\(r.emoji) \(r.title)", from: nil,
                                   detail: r.note.isEmpty ? "Every \(r.everyMinutes) min" : r.note,
                                   date: now, url: nil)])
        }
    }
}

/// Counts and errors only (never message content), for troubleshooting.
enum StatusLog {
    static let url = Paths.supportDir.appendingPathComponent("status.log")
    static func write(_ line: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let entry = "\(stamp) \(line)\n"
        // Keep the log small: past 1 MB, the current file becomes status.old.log (replacing the previous one).
        if let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 1_000_000 {
            let old = Paths.supportDir.appendingPathComponent("status.old.log")
            try? FileManager.default.removeItem(at: old)
            try? FileManager.default.moveItem(at: url, to: old)
        }
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(Data(entry.utf8)); try? h.close()
        } else {
            try? Data(entry.utf8).write(to: url)
        }
    }
}
