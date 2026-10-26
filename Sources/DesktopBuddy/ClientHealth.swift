import SwiftUI

/// Problems that make a client rule silently not work, each with a one-click fix.
/// One place decides these so the client page, the chat rows, the account page and
/// the sidebar always agree.
struct ClientIssue: Identifiable, Equatable {
    enum Fix: Equatable {
        case turnOnClient
        case turnOnAccount(String)
        case turnOnService(String, ItemSource)
        case signIn(String)
        case addToLookIn(String)
        case removeChat(ChatRef)
        case addRule
    }
    var id: String
    var text: String
    var fix: Fix?
    var fixLabel: String?
    /// Set when the issue is about one picked chat (shown on that row too).
    var chat: ChatRef?
}

/// Very common words that would sweep in unrelated mail.
let genericKeywords: Set<String> = ["team", "the", "and", "update", "meeting", "hi", "hello", "re", "fw", "fwd",
                                    "please", "thanks", "urgent", "info", "request", "report", "project", "test"]

extension AppState {
    /// The accounts a client looks in (all, or the ones picked under "Look in").
    func lookIn(_ c: ClientConfig) -> [AccountConfig] {
        c.accountIDs.isEmpty ? config.accounts : config.accounts.filter { c.accountIDs.contains($0.id) }
    }

    /// Why a service on an account isn't being checked right now, or nil if it is.
    func blocker(_ a: AccountConfig, _ source: ItemSource) -> (String, ClientIssue.Fix, String)? {
        let svc = source == .chat ? a.provider.chatName : a.provider.mailName
        if !a.enabled { return ("\(a.label) is turned off", .turnOnAccount(a.id), "Turn On \(a.label)") }
        let on = source == .chat ? a.watchChat : a.watchMail
        if !on { return ("\(svc) is turned off for \(a.label)", .turnOnService(a.id, source), "Turn On \(svc)") }
        if expired.contains(a.id) { return ("\(a.label)'s sign-in has expired", .signIn(a.id), "Sign In Again…") }
        if needsSignIn(a.id) { return ("\(a.label) isn't signed in", .signIn(a.id), "Sign In…") }
        return nil
    }

    func clientIssues(_ c: ClientConfig) -> [ClientIssue] {
        if !c.enabled {
            return [ClientIssue(id: "off", text: "\(c.name) is turned off, so nothing is sorted under it.",
                                fix: .turnOnClient, fixLabel: "Turn On")]
        }
        var out: [ClientIssue] = []
        let accounts = lookIn(c)

        if c.senders.isEmpty && c.keywords.isEmpty && c.chats.isEmpty && !c.matchChatNames {
            out.append(ClientIssue(id: "norules", text: "\(c.name) has no rules yet, so it can't catch anything. Add a sender, keyword or chat below."))
        }

        // Email rules need at least one account with Mail being checked.
        if !c.senders.isEmpty || !c.keywords.isEmpty {
            let blocked = accounts.compactMap { a in blocker(a, .mail).map { (a, $0) } }
            if !accounts.isEmpty && blocked.count == accounts.count, let (_, b) = blocked.first {
                out.append(ClientIssue(id: "mail", text: "Email rules aren't being checked: \(b.0).", fix: b.1, fixLabel: b.2))
            }
            for k in c.keywords where genericKeywords.contains(k.lowercased()) || k.count < 3 {
                out.append(ClientIssue(id: "kw-\(k)",
                                       text: "“\(k)” is a very common word, so lots of unrelated mail will be sorted under \(c.name). Use something specific to this client."))
            }
        }

        // Each picked chat must be on an account that is in Look in and is checking chat.
        for chat in c.chats {
            guard let a = account(chat.accountID) else {
                out.append(ClientIssue(id: "chat-gone-\(chat.id)", text: "“\(chat.name)” belongs to an account that was removed.",
                                       fix: .removeChat(chat), fixLabel: "Remove", chat: chat))
                continue
            }
            if !c.accountIDs.isEmpty && !c.accountIDs.contains(a.id) {
                out.append(ClientIssue(id: "chat-scope-\(chat.id)",
                                       text: "“\(chat.name)” is in \(a.label), which isn't in Look in for this client.",
                                       fix: .addToLookIn(a.id), fixLabel: "Add \(a.label)", chat: chat))
            } else if let b = blocker(a, .chat) {
                out.append(ClientIssue(id: "chat-\(chat.id)", text: "“\(chat.name)” isn't being checked: \(b.0).",
                                       fix: b.1, fixLabel: b.2, chat: chat))
            }
        }

        // Name matching needs chat on at least one account (only worth saying if no chat issue already covers it).
        if c.matchChatNames && c.chats.isEmpty {
            let blocked = accounts.compactMap { blocker($0, .chat) }
            if !accounts.isEmpty && blocked.count == accounts.count, let b = blocked.first {
                out.append(ClientIssue(id: "names", text: "Chats named after \(c.name) can't be found: \(b.0).", fix: b.1, fixLabel: b.2))
            }
        }
        return out
    }

    /// Clients that stop working if this service is switched off (for the account page).
    func clientsUsing(_ a: AccountConfig, _ source: ItemSource) -> [ClientConfig] {
        config.clients.filter { c in
            guard c.enabled, c.accountIDs.isEmpty || c.accountIDs.contains(a.id) else { return false }
            switch source {
            case .mail: return !c.senders.isEmpty || !c.keywords.isEmpty
            case .chat: return c.chats.contains { $0.accountID == a.id } || c.matchChatNames
            default: return false
            }
        }
    }

    func apply(_ fix: ClientIssue.Fix, client id: String) {
        switch fix {
        case .turnOnClient:
            if var c = client(id) { c.enabled = true; updateClient(c) }
        case .turnOnAccount(let aid):
            if var a = account(aid) { a.enabled = true; update(a); Task { await Poller.shared.poll(a) } }
        case .turnOnService(let aid, let source):
            guard var a = account(aid) else { return }
            if source == .chat { a.watchChat = true } else { a.watchMail = true }
            update(a)
            Task { await Poller.shared.poll(a) }
        case .signIn(let aid):
            SettingsRouter.shared.selection = .account(aid)
        case .addToLookIn(let aid):
            if var c = client(id), !c.accountIDs.contains(aid) { c.accountIDs.append(aid); updateClient(c) }
        case .removeChat(let chat):
            if var c = client(id) { c.chats.removeAll { $0 == chat }; updateClient(c) }
        case .addRule:
            break
        }
    }
}

/// Orange callout listing what's wrong, each with its fix button.
struct IssueList: View {
    let issues: [ClientIssue]
    let clientID: String
    @ObservedObject var state = AppState.shared

    var body: some View {
        ForEach(issues) { issue in
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(issue.text).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let fix = issue.fix, let label = issue.fixLabel {
                    Button(label) { withAnimation(buddySpring) { state.apply(fix, client: clientID) } }
                        .controlSize(.small)
                }
            }
        }
    }
}
