import Foundation
import SwiftUI

enum ItemSource: String, Codable, CaseIterable {
    case mail, chat, meeting, task, reminder

    var symbol: String {
        switch self {
        case .mail: return "envelope.fill"
        case .chat: return "bubble.left.and.bubble.right.fill"
        case .meeting: return "video.fill"
        case .task: return "checklist"
        case .reminder: return "bell.fill"
        }
    }

    var label: String {
        switch self {
        case .mail: return "Mail"
        case .chat: return "Chat"
        case .meeting: return "Meeting"
        case .task: return "Task"
        case .reminder: return "Reminder"
        }
    }

    var tint: Color {
        switch self {
        case .mail: return .blue
        case .chat: return .green
        case .meeting: return .indigo
        case .task: return .orange
        case .reminder: return .teal
        }
    }
}

/// One thing the character is telling you about.
struct BuddyItem: Identifiable, Codable, Equatable {
    var id: String              // stable key, e.g. "mail:<accountID>:<messageId>"
    var source: ItemSource
    var accountID: String?      // nil for local reminders
    var accountLabel: String?   // display name at the time it arrived
    var title: String           // subject / chat name / task / event / reminder
    var from: String?           // sender for mail & chat
    var detail: String?         // snippet / notes / time
    var date: Date
    var url: URL?               // where "Open" goes
    var fromAddress: String?    // mail sender address, for client rules
    var chatRef: String?        // Google Chat space name / Teams chat ID, for client rules
    var clientID: String?       // set when a client rule matched

    /// Who shows this item: a matched client first, then the account, else your reminders.
    var owner: String { clientID ?? accountID ?? reminderOwner }
}

let reminderOwner = "reminders"

// MARK: - Accounts

enum Provider: String, Codable, CaseIterable, Identifiable {
    case google, microsoft
    var id: String { rawValue }

    var name: String {
        switch self {
        case .google: return "Google Workspace"
        case .microsoft: return "Microsoft 365"
        }
    }

    var services: String {
        switch self {
        case .google: return "Gmail, Google Chat, Calendar and Tasks"
        case .microsoft: return "Outlook, Teams chats, Calendar and To Do"
        }
    }

    var chatName: String { self == .google ? "Google Chat" : "Teams chats" }
    var mailName: String { self == .google ? "Gmail" : "Outlook mail" }
    var tasksName: String { self == .google ? "Google Tasks" : "Microsoft To Do" }
}

/// Accent colours an account can use, mirroring macOS accent colours.
enum AccountTint: String, Codable, CaseIterable, Identifiable {
    case blue, purple, pink, red, orange, yellow, green, teal, graphite
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .blue: return Color(red: 0.0, green: 0.48, blue: 1.0)
        case .purple: return Color(red: 0.58, green: 0.32, blue: 0.86)
        case .pink: return Color(red: 0.97, green: 0.31, blue: 0.62)
        case .red: return Color(red: 0.93, green: 0.27, blue: 0.27)
        case .orange: return Color(red: 0.97, green: 0.53, blue: 0.13)
        case .yellow: return Color(red: 0.96, green: 0.76, blue: 0.1)
        case .green: return Color(red: 0.2, green: 0.72, blue: 0.33)
        case .teal: return Color(red: 0.12, green: 0.66, blue: 0.7)
        case .graphite: return Color(white: 0.55)
        }
    }
}

struct AccountConfig: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var providerChoice: Provider?              // nil = google (accounts made by v1)
    var label: String                          // e.g. "Dynamatix", "Acme client"
    var email: String
    var tintChoice: AccountTint?
    var logoPath: String?                      // custom logo; otherwise a bundled one matched by name
    var enabled: Bool = true
    var watchMail = true
    var watchChat = true
    var watchMeetings = true
    var watchTasks = true

    // Advanced: per-account OAuth client (otherwise the team default is used).
    var clientID: String = ""
    var redirectPort: Int = 8766
    var tenant: String?                        // Microsoft: "organizations", "common" or a tenant ID

    var provider: Provider {
        get { providerChoice ?? .google }
        set { providerChoice = newValue }
    }
    var tint: AccountTint {
        get { tintChoice ?? (provider == .microsoft ? .purple : .blue) }
        set { tintChoice = newValue }
    }
}

// MARK: - Clients

/// A chat picked for a client (Google Chat space or Teams chat).
struct ChatRef: Codable, Equatable, Hashable, Identifiable {
    enum Kind: String, Codable { case direct, group, space }
    var accountID: String
    var chatID: String          // "spaces/AAA…" or Teams chat ID
    var name: String
    var kind: Kind?
    var lastActive: Date?
    var id: String { accountID + "|" + chatID }

    // Identity is the chat itself; name/activity can change between lists.
    static func == (a: ChatRef, b: ChatRef) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

/// A client or workspace you want called out separately, even when they don't give you an account:
/// their mails (by sender or keyword) and chats show up under their own logo.
struct ClientConfig: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var logoPath: String?
    var tintChoice: AccountTint?
    var enabled = true
    var senders: [String] = []          // "gatehouse.co.uk" or "jane@client.com"
    var keywords: [String] = []         // matched in subject and preview of unread inbox mail
    var chats: [ChatRef] = []
    var matchChatNames = true           // also chats whose name contains the client name
    var accountIDs: [String] = []       // where to look; empty = every account

    var tint: AccountTint {
        get { tintChoice ?? .green }
        set { tintChoice = newValue }
    }
    var hasRules: Bool { !senders.isEmpty || !keywords.isEmpty || !chats.isEmpty || matchChatNames }
}

struct Reminder: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var emoji: String = "💧"
    var note: String = ""
    var everyMinutes: Int = 30
    var startHour: Int = 9
    var endHour: Int = 18
    var weekdays: Set<Int> = [2, 3, 4, 5, 6]   // Calendar weekday: 1 = Sunday
    var enabled = true
    var lastFired: Date?
}

struct AppConfig: Codable, Equatable {
    var accounts: [AccountConfig] = []
    var reminders: [Reminder] = [
        Reminder(title: "Drink a glass of water", emoji: "💧", note: "Stay hydrated!", everyMinutes: 30)
    ]
    var clientsList: [ClientConfig]?
    var clients: [ClientConfig] {
        get { clientsList ?? [] }
        set { clientsList = newValue }
    }
    var reminderLogoPath: String?
    var seededClients: Bool?
    var characterScaleChoice: Double?               // on-screen logo size, 0.5 ... 1.2
    var characterScale: Double {
        get { characterScaleChoice ?? 0.7 }
        set { characterScaleChoice = newValue }
    }
    var pollSeconds: Int = 60
    var meetingLeadMinutes: Int = 10
    var quietStartHour: Int?        // e.g. 22
    var quietEndHour: Int?          // e.g. 8
    var playSound = true
    var paused = false
    var autoUpdateCheck: Bool?                      // nil = on
    var checkForUpdates: Bool {
        get { autoUpdateCheck ?? true }
        set { autoUpdateCheck = newValue }
    }
}
