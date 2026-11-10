import SwiftUI
import AppKit

/// Kept out of screen sharing (and, by macOS, screenshots) unless turned off or briefly allowed.
enum OverlayPlacement {
    static func sharingHidden(protection: Bool, allowedUntil: Date?, now: Date = Date()) -> Bool {
        protection && !(allowedUntil.map { $0 > now } ?? false)
    }
}

@MainActor
func ownerColor(_ owner: String) -> Color { AppState.shared.ownerTint(owner).color }

/// Apple-style motion: critically damped spring, or a simple fade when Reduce Motion is on.
var buddySpring: Animation {
    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        ? .easeInOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 1)
}

// MARK: - Notification content (shared by banner and list)

extension BuddyItem {
    /// The service name shown on the card, e.g. "Gmail", "Teams", "Calendar".
    @MainActor var serviceName: String {
        let p = accountID.flatMap { AppState.shared.account($0)?.provider }
        switch source {
        case .mail: return p == .microsoft ? "Outlook" : "Gmail"
        case .chat: return p == .microsoft ? "Teams" : "Google Chat"
        case .meeting: return "Calendar"
        case .task: return p == .microsoft ? "To Do" : "Tasks"
        case .reminder: return "Reminder"
        }
    }
    /// Tooltip for Done everywhere, so nobody thinks it marks the mail as read.
    @MainActor var doneHelp: String { "Remove from Desktop Buddy. Nothing changes in \(serviceName)." }

    /// Bold first line: who it's from (mail/chat) or what it is.
    var headline: String {
        switch source {
        case .mail, .chat: return from ?? title
        default: return title
        }
    }
    /// Second line: subject / chat space / organiser / task list.
    var subhead: String? {
        switch source {
        case .mail: return title
        case .chat: return title == "Direct message" ? nil : title
        case .meeting, .task: return from
        case .reminder: return nil
        }
    }
}

/// Owner logo with the service glyph badged in the corner, like a notification's app icon.
struct CardIcon: View {
    let item: BuddyItem
    var size: CGFloat = 34
    var body: some View {
        OwnerBuddy(owner: item.owner, excited: false, size: size)
            .shadow(color: .clear, radius: 0)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: item.source.symbol)
                    .font(.system(size: size * 0.24, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: size * 0.48, height: size * 0.48)
                    .background(Circle().fill(item.source.tint.gradient))
                    .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
                    .offset(x: size * 0.14, y: size * 0.14)
            }
    }
}

/// Text block of a notification: caption line, headline, subhead, body.
struct CardText: View {
    let item: BuddyItem
    var showOwner: Bool
    var bodyLines = 2
    @ObservedObject var state = AppState.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(showOwner ? "\(item.serviceName) · \(state.ownerName(item.owner))" : item.serviceName)
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 6)
                Text(shortAgo(item.date)).font(.system(size: 11)).foregroundStyle(.tertiary).monospacedDigit()
            }
            Text(item.headline).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            if let sub = item.subhead, !sub.isEmpty {
                Text(sub).font(.system(size: 13)).lineLimit(1)
            }
            if let d = item.detail, !d.isEmpty {
                Text(d).font(.system(size: 12.5)).foregroundStyle(.secondary).lineLimit(bodyLines)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SourceIcon: View {
    let source: ItemSource
    var color: Color {
        switch source {
        case .mail: return .red
        case .chat: return .green
        case .meeting: return .blue
        case .task: return .orange
        case .reminder: return .teal
        }
    }
    var body: some View {
        Image(systemName: source.symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(Circle().fill(color))
    }
}

struct AccountPill: View {
    let item: BuddyItem
    var body: some View {
        Text(AppState.shared.account(item.owner)?.label ?? item.accountLabel ?? "")
            .font(.system(size: 10, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Capsule().fill(.quaternary))
            .foregroundStyle(.secondary)
    }
}
