import Foundation

// Microsoft 365 via Microsoft Graph (v1.0), delegated read-only permissions.
private let graph = "https://graph.microsoft.com/v1.0"

/// Graph returns UTC times without a "Z" when asked for UTC; normalise before parsing.
func graphDate(_ s: String?) -> Date? {
    guard var s else { return nil }
    if !s.hasSuffix("Z") && !s.contains("+") { s += "Z" }
    if let dot = s.firstIndex(of: "."), let z = s.lastIndex(of: "Z"), s.distance(from: dot, to: z) > 4 {
        s = String(s[..<s.index(dot, offsetBy: 4)]) + "Z"      // trim 7-digit fractions to milliseconds
    }
    return parseDate(s)
}

private func stripHTML(_ s: String) -> String {
    s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        .replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&amp;", with: "&")
        .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - Outlook mail (unread in Inbox)

enum OutlookMailSource {
    static func fetch(_ api: APIClient) async throws -> FetchResult {
        let acc = api.account
        var messages: [[String: Any]] = []
        for (path, query) in listQueries(acc, since: Date().addingTimeInterval(-2 * 86_400)) {
            messages += try await api.get(path, query)["value"] as? [[String: Any]] ?? []
        }
        var items: [BuddyItem] = []
        for m in messages {
            guard let id = m["id"] as? String, !items.contains(where: { $0.id == "mail:\(acc.id):\(id)" }) else { continue }
            let from = ((m["from"] as? [String: Any])?["emailAddress"] as? [String: Any])
            let name = (from?["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? from?["address"] as? String
            items.append(BuddyItem(
                id: "mail:\(acc.id):\(id)", source: .mail, accountID: acc.id, accountLabel: acc.label,
                title: (m["subject"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "(no subject)",
                from: name ?? "Unknown sender", detail: m["bodyPreview"] as? String,
                date: graphDate(m["receivedDateTime"] as? String) ?? Date(),
                url: (m["webLink"] as? String).flatMap(URL.init(string:)),
                fromAddress: (from?["address"] as? String)?.lowercased()))
        }
        items.sort { $0.date > $1.date }
        return FetchResult(source: .mail, items: items, liveIDs: Set(items.map(\.id)))
    }

    /// Unread inbox mail; or, with "only these categories", unread mail with each category in any folder.
    static func listQueries(_ acc: AccountConfig, since: Date) -> [(String, [String: String])] {
        let base = "receivedDateTime ge \(isoPlain.string(from: since)) and isRead eq false"
        let select = "id,subject,from,bodyPreview,receivedDateTime,webLink"
        guard acc.labelsOnly else {
            return [("\(graph)/me/mailFolders/inbox/messages",
                     ["$filter": base, "$orderby": "receivedDateTime desc", "$select": select, "$top": "25"])]
        }
        // Graph can't sort a category filter, so results are sorted after merging.
        return acc.onlyLabels.map { c in
            let name = c.name.replacingOccurrences(of: "'", with: "''")
            return ("\(graph)/me/messages",
                    ["$filter": "\(base) and categories/any(c:c eq '\(name)')", "$select": select, "$top": "25"])
        }
    }

    /// Categories used on your recent mail. (The full category list needs a permission Desktop Buddy doesn't ask for.)
    static func categories(_ api: APIClient) async throws -> [MailLabel] {
        let json = try await api.get("\(graph)/me/messages", ["$select": "categories", "$top": "200",
                                                               "$orderby": "receivedDateTime desc"])
        let names = Set((json["value"] as? [[String: Any]] ?? []).flatMap { $0["categories"] as? [String] ?? [] })
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { MailLabel(id: $0, name: $0) }
    }
}

// MARK: - Teams chats (unread last message per chat)

actor TeamsChatSource {
    static let shared = TeamsChatSource()
    private var me: [String: String] = [:]   // account id -> AAD user id

    func fetch(_ api: APIClient) async throws -> FetchResult {
        let acc = api.account
        let myID = try await myUserID(api)
        let json = try await api.get("\(graph)/me/chats", [
            "$expand": "lastMessagePreview",
            "$orderby": "lastMessagePreview/createdDateTime desc",
            "$top": "50",
        ])
        let cutoff = Date().addingTimeInterval(-2 * 86_400)
        var items: [BuddyItem] = []
        for chat in json["value"] as? [[String: Any]] ?? [] {
            guard let chatID = chat["id"] as? String,
                  let last = chat["lastMessagePreview"] as? [String: Any],
                  let msgID = last["id"] as? String,
                  let created = graphDate(last["createdDateTime"] as? String), created > cutoff,
                  (last["isDeleted"] as? Bool) != true else { continue }
            let sender = ((last["from"] as? [String: Any])?["user"] as? [String: Any])
            if (sender?["id"] as? String) == myID { continue }               // your own message
            // Teams knows what you've read: skip chats read since the last message.
            let viewpoint = chat["viewpoint"] as? [String: Any]
            if let read = graphDate(viewpoint?["lastMessageReadDateTime"] as? String), read >= created { continue }
            if (viewpoint?["isHidden"] as? Bool) == true { continue }

            let body = (last["body"] as? [String: Any])?["content"] as? String ?? ""
            let chatType = chat["chatType"] as? String ?? ""
            let topic = (chat["topic"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let title = topic ?? (chatType == "oneOnOne" ? "Direct message" : (chatType == "meeting" ? "Meeting chat" : "Group chat"))
            items.append(BuddyItem(
                id: "teams:\(acc.id):\(chatID):\(msgID)", source: .chat, accountID: acc.id, accountLabel: acc.label,
                title: title, from: sender?["displayName"] as? String ?? "Someone",
                detail: stripHTML(body).isEmpty ? "(attachment)" : stripHTML(body),
                date: created, url: (chat["webUrl"] as? String).flatMap(URL.init(string:)),
                chatRef: chatID))
        }
        // Unread state is reliable in Teams, so chats you've read elsewhere disappear here too.
        return FetchResult(source: .chat, items: items, liveIDs: Set(items.map(\.id)))
    }

    private func myUserID(_ api: APIClient) async throws -> String {
        if let id = me[api.account.id] { return id }
        let json = try await api.get("\(graph)/me", ["$select": "id"])
        let id = json["id"] as? String ?? ""
        me[api.account.id] = id
        return id
    }
}

// MARK: - Outlook calendar (meetings about to start, Teams join link)

enum OutlookCalendarSource {
    static func fetch(_ api: APIClient, leadMinutes: Int) async throws -> FetchResult {
        let acc = api.account
        let now = Date()
        let json = try await api.get("\(graph)/me/calendarView", [
            "startDateTime": isoPlain.string(from: now.addingTimeInterval(-10 * 60)),
            "endDateTime": isoPlain.string(from: now.addingTimeInterval(Double(leadMinutes) * 60)),
            "$select": "id,subject,start,isAllDay,isCancelled,organizer,onlineMeeting,webLink,responseStatus",
            "$orderby": "start/dateTime", "$top": "20",
        ], headers: ["Prefer": "outlook.timezone=\"UTC\""])
        var items: [BuddyItem] = []
        for ev in json["value"] as? [[String: Any]] ?? [] {
            guard let id = ev["id"] as? String,
                  (ev["isAllDay"] as? Bool) != true, (ev["isCancelled"] as? Bool) != true,
                  let startStr = (ev["start"] as? [String: Any])?["dateTime"] as? String,
                  let start = graphDate(startStr), start >= now.addingTimeInterval(-10 * 60) else { continue }
            if ((ev["responseStatus"] as? [String: Any])?["response"] as? String) == "declined" { continue }
            let join = ((ev["onlineMeeting"] as? [String: Any])?["joinUrl"] as? String).flatMap(URL.init(string:))
            let mins = Int(start.timeIntervalSince(now) / 60)
            let when = mins > 0 ? "Starts in \(mins) min" : (mins == 0 ? "Starting now" : "Started \(-mins) min ago")
            let organizer = ((ev["organizer"] as? [String: Any])?["emailAddress"] as? [String: Any])?["name"] as? String
            items.append(BuddyItem(
                id: "meet:\(acc.id):\(id):\(startStr)", source: .meeting, accountID: acc.id, accountLabel: acc.label,
                title: ev["subject"] as? String ?? "Meeting", from: organizer,
                detail: when + (join != nil ? " · Teams" : ""), date: start,
                url: join ?? (ev["webLink"] as? String).flatMap(URL.init(string:))))
        }
        return FetchResult(source: .meeting, items: items, liveIDs: Set(items.map(\.id)))
    }
}

// MARK: - Microsoft To Do (due today or overdue)

enum ToDoSource {
    static func fetch(_ api: APIClient) async throws -> FetchResult {
        let acc = api.account
        let cal = Calendar.current
        let endOfToday = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))!
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"

        let lists = try await api.get("\(graph)/me/todo/lists")
        var items: [BuddyItem] = []
        for list in lists["value"] as? [[String: Any]] ?? [] {
            guard let listID = list["id"] as? String else { continue }
            let tasks = try await api.get("\(graph)/me/todo/lists/\(listID)/tasks", [
                "$filter": "status ne 'completed'", "$top": "100",
            ])
            for t in tasks["value"] as? [[String: Any]] ?? [] {
                guard let id = t["id"] as? String, let title = t["title"] as? String, !title.isEmpty,
                      let due = graphDate((t["dueDateTime"] as? [String: Any])?["dateTime"] as? String),
                      due < endOfToday else { continue }
                let overdue = cal.startOfDay(for: due) < cal.startOfDay(for: Date())
                items.append(BuddyItem(
                    id: "task:\(acc.id):\(id):\(day.string(from: Date()))", source: .task,
                    accountID: acc.id, accountLabel: acc.label,
                    title: title, from: list["displayName"] as? String,
                    detail: overdue ? "Overdue (was due \(day.string(from: due)))" : "Due today",
                    date: Date(), url: URL(string: "https://to-do.office.com/tasks/")))
            }
        }
        return FetchResult(source: .task, items: items, liveIDs: Set(items.map(\.id)))
    }
}
