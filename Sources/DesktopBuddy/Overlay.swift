import SwiftUI
import AppKit
import Combine

/// Transparent, always-on-top panel that holds the character. It sits in the
/// bottom-right corner (draggable) and only exists while there is something to show.
@MainActor
final class OverlayController {
    static let shared = OverlayController()

    private let panel: NSPanel
    private let host: NSHostingView<OverlayView>
    private var bag = Set<AnyCancellable>()
    private let state = AppState.shared
    /// Bottom-right corner of the panel in screen coordinates; persisted.
    private var anchor: NSPoint {
        get {
            let d = UserDefaults.standard
            if d.object(forKey: "anchorX") != nil {
                return NSPoint(x: d.double(forKey: "anchorX"), y: d.double(forKey: "anchorY"))
            }
            let vf = NSScreen.main?.visibleFrame ?? .init(x: 0, y: 0, width: 1440, height: 900)
            return NSPoint(x: vf.maxX - 24, y: vf.minY + 24)
        }
        set {
            UserDefaults.standard.set(newValue.x, forKey: "anchorX")
            UserDefaults.standard.set(newValue.y, forKey: "anchorY")
        }
    }

    private init() {
        host = NSHostingView(rootView: OverlayView())
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 200),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = host
        host.rootView = OverlayView(onDrag: { [weak self] delta in self?.drag(by: delta) },
                                    onDragEnd: { [weak self] in self?.saveAnchor() })

        Publishers.CombineLatest4(state.$items, state.$expanded, state.$lastArrival, state.$config)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.update() }
            }
            .store(in: &bag)
    }

    func update() {
        let shouldShow = !state.items.isEmpty && !state.config.paused
        guard shouldShow else { panel.orderOut(nil); return }
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        let a = anchor
        panel.setFrame(NSRect(x: a.x - size.width, y: a.y, width: size.width, height: size.height), display: true)
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func resetPosition() {
        UserDefaults.standard.removeObject(forKey: "anchorX")
        UserDefaults.standard.removeObject(forKey: "anchorY")
        update()
    }

    private func drag(by delta: CGSize) {
        var f = panel.frame
        f.origin.x += delta.width
        f.origin.y += delta.height
        panel.setFrameOrigin(f.origin)
    }

    private func saveAnchor() {
        anchor = NSPoint(x: panel.frame.maxX, y: panel.frame.minY)
    }
}

struct OverlayView: View {
    @ObservedObject var state = AppState.shared
    var onDrag: (CGSize) -> Void = { _ in }
    var onDragEnd: () -> Void = {}

    @Local private var bubble: BuddyItem? = nil
    @Local private var excitedOwner: String? = nil
    @Local private var lastMouse: NSPoint? = nil

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if state.expanded {
                NotificationList()
                    .transition(.opacity)
            }
            // The banner sits above the row, so it never widens one logo's column.
            if !state.expanded, let b = bubble {
                SpeechBubble(item: b, more: state.items.filter { $0.owner == b.owner }.count - 1)
                    .onTapGesture { withAnimation(buddySpring) { state.toggleList(for: b.owner) } }
                    .transition(.opacity)
            }
            // One logo per owner: clients, accounts, and your own reminders.
            HStack(alignment: .top, spacing: 6) {
                ForEach(state.activeOwners, id: \.self) { owner in
                    buddy(for: owner)
                }
            }
        }
        .padding(12)
        .fixedSize()
        .onChange(of: state.lastArrival) { _, item in
            guard let item else { withAnimation { bubble = nil }; return }
            withAnimation(buddySpring) { bubble = item }
            excitedOwner = item.owner
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                if excitedOwner == item.owner { excitedOwner = nil }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
                if bubble?.id == item.id { withAnimation { bubble = nil } }
            }
        }
    }

    private var scale: CGFloat { CGFloat(state.config.characterScale) }

    @ViewBuilder
    private func buddy(for owner: String) -> some View {
        let count = state.items.filter { $0.owner == owner }.count
        VStack(spacing: 2) {
            ZStack(alignment: .topTrailing) {
                OwnerBuddy(owner: owner, excited: excitedOwner == owner, size: 72 * scale)
                    .padding(7)
                    .contentShape(Rectangle())
                // Dock-style badge: system red, SF Pro, no outline.
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).frame(minWidth: 20, minHeight: 20)
                        .background(Capsule().fill(Color(nsColor: .systemRed)))
                        .shadow(color: .black.opacity(0.2), radius: 1.5, y: 1)
                        .accessibilityLabel("\(count) waiting")
                }
            }
            OwnerTag(owner: owner)
        }
        .frame(minWidth: max(88, 72 * scale + 24))
        .contentShape(Rectangle())
        .help("\(state.ownerName(owner)): click to see notifications · drag to move")
        .gesture(DragGesture(minimumDistance: 3)
            .onChanged { _ in
                // Use screen coordinates: the view itself moves with the window.
                let m = NSEvent.mouseLocation
                if let last = lastMouse { onDrag(CGSize(width: m.x - last.x, height: m.y - last.y)) }
                lastMouse = m
            }
            .onEnded { _ in lastMouse = nil; onDragEnd() })
        .onTapGesture { withAnimation(buddySpring) { state.toggleList(for: owner) } }
    }
}

/// Name under each logo: SF Pro on a neutral glass capsule, readable on any wallpaper
/// (like macOS widget and Stage Manager labels). The logo carries the colour, not the label.
private struct OwnerTag: View {
    let owner: String
    var body: some View {
        Text(AppState.shared.ownerName(owner))
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(.primary)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.08)))
            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
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
private struct CardIcon: View {
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
private struct CardText: View {
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

// MARK: - Arrival banner ("glimpse")

private struct SpeechBubble: View {
    let item: BuddyItem
    let more: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                CardIcon(item: item, size: 34)
                CardText(item: item, showOwner: true)
            }
            if more > 0 {
                Text("\(more) more from \(AppState.shared.ownerName(item.owner))")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    .padding(.leading, 44)
            }
        }
        .padding(12)
        .frame(width: 320, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows all notifications")
    }
}

// MARK: - Notification list (Notification Center style)

private struct NotificationList: View {
    @ObservedObject var state = AppState.shared

    private var shown: [BuddyItem] {
        guard let f = state.filterOwner else { return state.items }
        return state.items.filter { $0.owner == f }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if state.activeOwners.count > 1 { filterBar }
            ScrollView {
                VStack(spacing: 14) {
                    if state.filterOwner == nil && state.activeOwners.count > 1 {
                        ForEach(state.activeOwners, id: \.self) { owner in
                            group(owner, state.items.filter { $0.owner == owner }, titled: true)
                        }
                    } else {
                        group(state.filterOwner ?? state.activeOwners.first ?? "", shown, titled: false)
                    }
                }
                .padding(.horizontal, 10).padding(.bottom, 10).padding(.top, 2)
            }
            .frame(maxHeight: 460)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 360)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.regularMaterial))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.2), radius: 18, y: 8)
        .onExitCommand { state.expanded = false }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if let f = state.filterOwner {
                OwnerBuddy(owner: f, excited: false, size: 22).shadow(radius: 0)
                Text(state.ownerName(f)).font(.system(size: 15, weight: .semibold))
            } else {
                Text("Notifications").font(.system(size: 15, weight: .semibold))
            }
            Spacer()
            Button(state.filterOwner == nil ? "Clear All" : "Clear") {
                withAnimation(buddySpring) { shown.forEach { state.dismiss($0.id) } }
            }
            .buttonStyle(.borderless).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            Button { state.expanded = false } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 16)).symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.borderless).foregroundStyle(.secondary)
            .keyboardShortcut(.cancelAction)
            .help("Close").accessibilityLabel("Close")
        }
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)
    }

    /// Logos as filters, each with its count, "All" first.
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                filterButton(nil)
                ForEach(state.activeOwners, id: \.self) { filterButton($0) }
            }
            .padding(.horizontal, 12)
        }
        .padding(.bottom, 10)
    }

    private func filterButton(_ owner: String?) -> some View {
        let selected = state.filterOwner == owner
        let count = owner.map { o in state.items.filter { $0.owner == o }.count } ?? state.items.count
        return Button { withAnimation(.easeOut(duration: 0.15)) { state.filterOwner = owner } } label: {
            HStack(spacing: 5) {
                if let owner {
                    OwnerBuddy(owner: owner, excited: false, size: 16).shadow(radius: 0)
                } else {
                    Text("All").font(.system(size: 12, weight: .semibold))
                }
                Text("\(count)").font(.system(size: 12, weight: .medium)).monospacedDigit()
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
            }
            .padding(.horizontal, 9).frame(height: 26)
            .background(Capsule().fill(selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06)))
            .overlay(Capsule().stroke(selected ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(owner.map { state.ownerName($0) } ?? "All notifications")
        .accessibilityLabel("\(owner.map { state.ownerName($0) } ?? "All"), \(count)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func group(_ owner: String, _ items: [BuddyItem], titled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if titled {
                HStack(spacing: 6) {
                    Text(state.ownerName(owner)).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") { withAnimation(buddySpring) { state.clearAll(owner: owner) } }
                        .buttonStyle(.borderless).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
            }
            ForEach(items) { NotificationCard(item: $0, showOwner: false) }
        }
    }
}

/// One notification: tap to open, hover for ✕ and quick actions, right-click for more.
private struct NotificationCard: View {
    let item: BuddyItem
    var showOwner: Bool
    @ObservedObject var state = AppState.shared
    @Local private var hover = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            CardIcon(item: item, size: 34)
            CardText(item: item, showOwner: showOwner)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.primary.opacity(hover ? 0.1 : 0.06)))
        .overlay(alignment: .topLeading) {
            if hover {
                Button { withAnimation(buddySpring) { state.dismiss(item.id) } } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(.regularMaterial))
                        .overlay(Circle().stroke(Color.primary.opacity(0.15), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .offset(x: -6, y: -6)
                .help("Done")
                .accessibilityLabel("Done")
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if hover {
                HStack(spacing: 4) {
                    snoozeMenu
                    if item.url != nil {
                        Button { state.open(item) } label: { Image(systemName: "arrow.up.forward") }
                            .help("Open in \(item.serviceName)").accessibilityLabel("Open")
                    }
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 8).frame(height: 22)
                .background(Capsule().fill(.regularMaterial))
                .padding(6)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
        .onTapGesture { state.open(item) }
        .contextMenu {
            if item.url != nil { Button("Open in \(item.serviceName)") { state.open(item) } }
            Menu("Snooze") { snoozeOptions }
            Divider()
            Button("Mark as Done") { state.dismiss(item.id) }
            Button("Clear All from \(state.ownerName(item.owner))") { state.clearAll(owner: item.owner) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Open") { state.open(item) }
        .accessibilityAction(named: "Done") { state.dismiss(item.id) }
    }

    private var snoozeMenu: some View {
        Menu { snoozeOptions } label: { Image(systemName: "clock") }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Snooze")
            .accessibilityLabel("Snooze")
    }

    @ViewBuilder private var snoozeOptions: some View {
        Button("For 10 Minutes") { state.snooze(item, minutes: 10) }
        Button("For 1 Hour") { state.snooze(item, minutes: 60) }
        Button("Until Tomorrow Morning") { state.snooze(item, minutes: minutesUntilTomorrow9()) }
    }

    private func minutesUntilTomorrow9() -> Int {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))!
        let nine = cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)!
        return max(1, Int(nine.timeIntervalSinceNow / 60))
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
