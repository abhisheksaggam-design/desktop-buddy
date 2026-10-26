import Foundation

/// Minimal authorized JSON GET against Google / Microsoft Graph REST APIs.
struct APIClient {
    let account: AccountConfig

    func get(_ base: String, _ query: [String: String] = [:], headers: [String: String] = [:]) async throws -> [String: Any] {
        var comps = URLComponents(string: base)!
        if !query.isEmpty {
            comps.queryItems = (comps.queryItems ?? []) + query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(try await OAuth.shared.accessToken(for: account))", forHTTPHeaderField: "Authorization")
        headers.forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        req.timeoutInterval = 30
        let (data, resp) = try await URLSession.shared.data(for: req)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let err = json["error"] as? [String: Any]
            let msg = (err?["message"] as? String) ?? (err?["code"] as? String) ?? "HTTP \(http.statusCode)"
            throw APIError(status: http.statusCode, host: comps.host ?? "", message: msg)
        }
        return json
    }
}

struct APIError: LocalizedError {
    var status: Int
    var host: String
    var message: String
    var errorDescription: String? { message }
    /// A console link if the provider told us how to fix it (e.g. "enable the API").
    var fixURL: URL? {
        guard let r = message.range(of: #"https://[^\s]+"#, options: .regularExpression) else { return nil }
        return URL(string: String(message[r]).trimmingCharacters(in: CharacterSet(charactersIn: ".,)")))
    }
}

let iso: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()
let isoPlain = ISO8601DateFormatter()
func parseDate(_ s: String?) -> Date? {
    guard let s else { return nil }
    return iso.date(from: s) ?? isoPlain.date(from: s)
}

/// A fetch returns the items to offer plus the full set of IDs that are still
/// "live" upstream, so items read/completed elsewhere disappear from the buddy.
struct FetchResult {
    var source: ItemSource
    var items: [BuddyItem]
    var liveIDs: Set<String>
}

// MARK: - Gmail

enum GmailSource {
    static func fetch(_ api: APIClient) async throws -> FetchResult {
        let acc = api.account
        let list = try await api.get("https://gmail.googleapis.com/gmail/v1/users/me/messages",
                                     ["q": "in:inbox is:unread newer_than:2d", "maxResults": "25"])
        let ids = (list["messages"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
        let live = Set(ids.map { "mail:\(acc.id):\($0)" })

        var items: [BuddyItem] = []
        let existing = await MainActor.run { Set(AppState.shared.items.map(\.id)) }
        for id in ids where !existing.contains("mail:\(acc.id):\(id)") {
            let msg = try await api.get("https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)?format=metadata&metadataHeaders=From&metadataHeaders=Subject")
            let rawFrom = header(msg, "From") ?? ""
            let from = rawFrom.isEmpty ? "Unknown sender" : cleanSender(rawFrom)
            let subject = header(msg, "Subject") ?? "(no subject)"
            let snippet = (msg["snippet"] as? String).map(decodeEntities)
            let ms = Double(msg["internalDate"] as? String ?? "") ?? Date().timeIntervalSince1970 * 1000
            items.append(BuddyItem(
                id: "mail:\(acc.id):\(id)", source: .mail, accountID: acc.id, accountLabel: acc.label,
                title: subject, from: from, detail: snippet,
                date: Date(timeIntervalSince1970: ms / 1000),
                url: URL(string: "https://mail.google.com/mail/u/?authuser=\(acc.email)#all/\(msg["threadId"] as? String ?? id)"),
                fromAddress: senderAddress(rawFrom)))
        }
        return FetchResult(source: .mail, items: items, liveIDs: live)
    }

    /// "Priya <priya@x.com>" -> "priya@x.com"
    static func senderAddress(_ raw: String) -> String {
        if let lt = raw.firstIndex(of: "<"), let gt = raw.lastIndex(of: ">"), lt < gt {
            return String(raw[raw.index(after: lt)..<gt]).lowercased()
        }
        return raw.trimmingCharacters(in: .whitespaces).lowercased()
    }

    private static func header(_ msg: [String: Any], _ name: String) -> String? {
        let headers = (msg["payload"] as? [String: Any])?["headers"] as? [[String: Any]] ?? []
        return headers.first { ($0["name"] as? String)?.caseInsensitiveCompare(name) == .orderedSame }?["value"] as? String
    }

    /// "Priya Shah <priya@x.com>" -> "Priya Shah"
    private static func cleanSender(_ raw: String) -> String {
        if let lt = raw.firstIndex(of: "<") {
            let name = raw[..<lt].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if !name.isEmpty { return name }
            return String(raw[raw.index(after: lt)...].dropLast())
        }
        return raw
    }

    private static func decodeEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}

// MARK: - Google Chat

actor ChatSource {
    static let shared = ChatSource()
    private var names: [String: String] = [:]      // "users/123" -> "Priya Shah"
    private var me: [String: String] = [:]         // account id -> "users/123"
    private var since: [String: Date] = [:]        // account id -> last check

    func fetch(_ api: APIClient) async throws -> FetchResult {
        let acc = api.account
        let now = Date()
        // First run looks back 2 hours so you see what you just missed.
        let from = since[acc.id] ?? now.addingTimeInterval(-2 * 3600)
        let myID = try await myUserName(api)

        var spaces: [[String: Any]] = []
        var token: String?
        repeat {
            var q = ["pageSize": "200"]
            if let token { q["pageToken"] = token }
            let page = try await api.get("https://chat.googleapis.com/v1/spaces", q)
            spaces += page["spaces"] as? [[String: Any]] ?? []
            token = page["nextPageToken"] as? String
        } while token != nil

        var items: [BuddyItem] = []
        for space in spaces {
            guard let spaceName = space["name"] as? String,
                  let active = parseDate(space["lastActiveTime"] as? String), active > from else { continue }
            let filter = "createTime > \"\(isoPlain.string(from: from))\""
            let page = try await api.get("https://chat.googleapis.com/v1/\(spaceName)/messages",
                                         ["filter": filter, "pageSize": "20", "orderBy": "createTime desc"])
            for msg in page["messages"] as? [[String: Any]] ?? [] {
                guard let name = msg["name"] as? String else { continue }
                let sender = msg["sender"] as? [String: Any] ?? [:]
                let senderID = sender["name"] as? String ?? ""
                if senderID == myID { continue }
                let who = await displayName(senderID, fallback: sender["displayName"] as? String, api: api)
                let spaceTitle = (space["spaceType"] as? String) == "DIRECT_MESSAGE"
                    ? "Direct message" : (space["displayName"] as? String ?? "Chat")
                let text = (msg["text"] as? String) ?? (msg["formattedText"] as? String) ?? "(attachment)"
                let spaceID = spaceName.replacingOccurrences(of: "spaces/", with: "")
                items.append(BuddyItem(
                    id: "chat:\(acc.id):\(name)", source: .chat, accountID: acc.id, accountLabel: acc.label,
                    title: spaceTitle, from: who, detail: text,
                    date: parseDate(msg["createTime"] as? String) ?? now,
                    url: URL(string: "https://mail.google.com/chat/u/?authuser=\(acc.email)#chat/space/\(spaceID)"),
                    chatRef: spaceName))
            }
        }
        since[acc.id] = now
        // Chat has no "unread" flag in the API, so chat items stay until you clear them.
        let current = await MainActor.run {
            Set(AppState.shared.items.filter { $0.source == .chat && $0.accountID == acc.id }.map(\.id))
        }
        return FetchResult(source: .chat, items: items, liveIDs: current.union(items.map(\.id)))
    }

    private func myUserName(_ api: APIClient) async throws -> String {
        if let id = me[api.account.id] { return id }
        // The OpenID "sub" is the same numeric ID Chat uses in "users/{id}"; no People API needed.
        let info = try await api.get("https://openidconnect.googleapis.com/v1/userinfo")
        let id = "users/" + (info["sub"] as? String ?? "")
        me[api.account.id] = id
        return id
    }

    private func displayName(_ userID: String, fallback: String?, api: APIClient) async -> String {
        if let fallback, !fallback.isEmpty { return fallback }
        if let cached = names[userID] { return cached }
        let personID = userID.replacingOccurrences(of: "users/", with: "people/")
        let person = try? await api.get("https://people.googleapis.com/v1/\(personID)",
                                        ["personFields": "names,emailAddresses",
                                         "sources": "DIRECTORY_SOURCE_TYPE_DOMAIN_PROFILE"])
        let name = ((person?["names"] as? [[String: Any]])?.first?["displayName"] as? String)
            ?? ((person?["emailAddresses"] as? [[String: Any]])?.first?["value"] as? String)
            ?? "Someone (enable People API for names)"
        names[userID] = name
        return name
    }
}

// MARK: - Calendar (meetings about to start)

enum CalendarSource {
    static func fetch(_ api: APIClient, leadMinutes: Int) async throws -> FetchResult {
        let acc = api.account
        let now = Date()
        let json = try await api.get("https://www.googleapis.com/calendar/v3/calendars/primary/events", [
            "timeMin": isoPlain.string(from: now.addingTimeInterval(-10 * 60)),
            "timeMax": isoPlain.string(from: now.addingTimeInterval(Double(leadMinutes) * 60)),
            "singleEvents": "true", "orderBy": "startTime", "maxResults": "20",
        ])
        var items: [BuddyItem] = []
        for ev in json["items"] as? [[String: Any]] ?? [] {
            guard let id = ev["id"] as? String,
                  let startStr = (ev["start"] as? [String: Any])?["dateTime"] as? String,   // skip all-day events
                  let start = parseDate(startStr) else { continue }
            let attendees = ev["attendees"] as? [[String: Any]] ?? []
            if attendees.contains(where: { ($0["self"] as? Bool) == true && ($0["responseStatus"] as? String) == "declined" }) { continue }
            // Started more than 10 min ago -> no longer relevant.
            if start < now.addingTimeInterval(-10 * 60) { continue }

            let meet = (ev["hangoutLink"] as? String).flatMap(URL.init(string:))
            let link = meet ?? (ev["htmlLink"] as? String).flatMap(URL.init(string:))
            let mins = Int(start.timeIntervalSince(now) / 60)
            let when = mins > 0 ? "Starts in \(mins) min" : (mins == 0 ? "Starting now" : "Started \(-mins) min ago")
            let organizer = (ev["organizer"] as? [String: Any]).flatMap { ($0["displayName"] as? String) ?? ($0["email"] as? String) }
            items.append(BuddyItem(
                id: "meet:\(acc.id):\(id):\(startStr)", source: .meeting, accountID: acc.id, accountLabel: acc.label,
                title: ev["summary"] as? String ?? "Meeting", from: organizer,
                detail: when + (meet != nil ? " · Google Meet" : ""), date: start, url: link))
        }
        return FetchResult(source: .meeting, items: items, liveIDs: Set(items.map(\.id)))
    }
}

// MARK: - Google Tasks (due today or overdue)

enum TasksSource {
    static func fetch(_ api: APIClient) async throws -> FetchResult {
        let acc = api.account
        let cal = Calendar.current
        let endOfToday = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))!
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"

        let lists = try await api.get("https://tasks.googleapis.com/tasks/v1/users/@me/lists", ["maxResults": "100"])
        var items: [BuddyItem] = []
        for list in lists["items"] as? [[String: Any]] ?? [] {
            guard let listID = list["id"] as? String else { continue }
            let tasks = try await api.get("https://tasks.googleapis.com/tasks/v1/lists/\(listID)/tasks", [
                "showCompleted": "false", "dueMax": isoPlain.string(from: endOfToday), "maxResults": "100",
            ])
            for t in tasks["items"] as? [[String: Any]] ?? [] {
                guard let id = t["id"] as? String, let title = t["title"] as? String, !title.isEmpty,
                      let due = parseDate(t["due"] as? String) else { continue }
                let overdue = cal.startOfDay(for: due) < cal.startOfDay(for: Date())
                let detail = [overdue ? "Overdue (was due \(day.string(from: due)))" : "Due today",
                              t["notes"] as? String].compactMap { $0 }.joined(separator: " · ")
                // One reminder per task per day.
                items.append(BuddyItem(
                    id: "task:\(acc.id):\(id):\(day.string(from: Date()))", source: .task, accountID: acc.id, accountLabel: acc.label,
                    title: title, from: list["title"] as? String, detail: detail, date: Date(),
                    url: URL(string: "https://tasks.google.com/")))
            }
        }
        return FetchResult(source: .task, items: items, liveIDs: Set(items.map(\.id)))
    }
}
