import SwiftUI
import AppKit

/// What you see when you click the menu bar icon: quick controls + everything waiting, grouped by account.
struct MenuBarPopover: View {
    @ObservedObject var state = AppState.shared
    var openSettings: () -> Void
    var showTour: () -> Void = {}
    var checkForUpdates: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            header.coachTarget(.header)
            UpdateBanner()
            Divider()
            if !state.config.accounts.isEmpty {
                accountsStrip.coachTarget(.accounts)
                Divider()
            }
            content
            Divider()
            footer.coachTarget(.footer)
        }
        .frame(width: 360)
        .coachMarks()
        .onAppear { state.startCoachMarksIfNeeded() }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Desktop Buddy").font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            HeaderIconButton(symbol: state.config.paused ? "moon.fill" : "moon",
                             tint: state.config.paused ? .indigo : nil,
                             label: state.config.paused ? "Resume notifications" : "Pause all notifications") {
                state.config.paused.toggle()
            }
            HeaderIconButton(symbol: "gearshape", tint: nil, label: "Settings", action: openSettings)
            Menu {
                Button("Check for Updates…", action: checkForUpdates)
                Button("Show Tour", action: showTour)
                if state.config.hidesFromSharing {
                    Button("Allow Screenshots for 1 Minute") { OverlayController.shared.allowScreenshots() }
                }
                Divider()
                Button("Quit Desktop Buddy") { NSApp.terminate(nil) }.keyboardShortcut("q")
            } label: {
                HeaderIconLabel(symbol: "ellipsis", tint: nil)
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
            .fixedSize()
            .help("More").accessibilityLabel("More")
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    private var subtitle: String {
        if state.config.paused { return "Paused" }
        if state.isQuietNow { return "Quiet hours" }
        let n = state.items.count
        return n == 0 ? "You're all caught up" : "\(n) waiting"
    }

    // MARK: Accounts (quick on/off)

    private var accountsStrip: some View {
        VStack(spacing: 2) {
            ForEach(state.config.accounts) { a in
                HStack(spacing: 8) {
                    AccountMark(account: a, size: 18)
                    Text(a.label).font(.callout).lineLimit(1)
                    if state.checking.contains(a.id) { ProgressView().controlSize(.mini) }
                    if state.needsSignIn(a.id) {
                        Button(state.expired.contains(a.id) ? "Sign In Again…" : "Sign In…") {
                            SettingsRouter.shared.selection = .account(a.id)
                            openSettings()
                        }
                        .buttonStyle(.borderless).font(.caption.weight(.semibold))
                        .foregroundStyle(state.expired.contains(a.id) ? Color.orange : Color.accentColor)
                    } else if a.enabled && state.errorCount(for: a.id) > 0 {
                        Image(systemName: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                            .help("A service needs attention. Open Settings for details.")
                    }
                    Spacer()
                    Toggle(a.label, isOn: Binding(get: { a.enabled },
                                                  set: { var x = a; x.enabled = $0; state.update(x) }))
                        .toggleStyle(.switch).labelsHidden().controlSize(.mini)
                }
                .padding(.vertical, 3)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    // MARK: Notifications

    @ViewBuilder
    private var content: some View {
        if state.config.accounts.isEmpty {
            VStack(spacing: 10) {
                AppMark(size: 56)
                Text("Add your first account").font(.headline)
                Text("Connect Google Workspace or Microsoft 365.").font(.callout).foregroundStyle(.secondary)
                Button("Add Account…") {
                    openSettings()
                    SettingsRouter.shared.showingProviderPicker = true
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        } else if state.items.isEmpty && state.coachStep == .row {
            // The tour needs a row to point at: show a sample one.
            PopoverRow(item: .coachSample, sample: true, pointedAt: true).coachTarget(.row).padding(.vertical, 6)
        } else if state.items.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "checkmark.circle").font(.system(size: 28)).foregroundStyle(.green)
                Text("All caught up").font(.headline)
                Text("Nothing needs you right now.").font(.callout).foregroundStyle(.secondary)
            }
            .padding(26)
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(state.activeOwners, id: \.self) { owner in
                        let mine = state.items.filter { $0.owner == owner }
                        Section {
                            ForEach(mine) { item in
                                let pointedAt = item.id == firstShownID
                                PopoverRow(item: item, sample: false, pointedAt: pointedAt)
                                    .coachTarget(.row, when: pointedAt)
                            }
                        } header: {
                            HStack(spacing: 6) {
                                OwnerBuddy(owner: owner, excited: false, size: 16).shadow(radius: 0)
                                Text(state.ownerName(owner)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                Text("\(mine.count)").font(.caption2.weight(.semibold)).monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 5).frame(minWidth: 16, minHeight: 16)
                                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                                Spacer()
                                PillButton(title: "Clear", symbol: "xmark", label: "Clear \(state.ownerName(owner))") {
                                    withAnimation(buddySpring) { state.clearAll(owner: owner) }
                                }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 5)
                            .background(.bar)
                        }
                    }
                }
            }
            .frame(maxHeight: 380)
        }
    }

    /// The first notification in the list, which the tour points at.
    private var firstShownID: String? {
        state.activeOwners.first.flatMap { o in state.items.first { $0.owner == o }?.id }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            let checking = !state.checking.isEmpty
            Button {
                Task { await Poller.shared.pollAll(); Poller.shared.checkReminders() }
            } label: {
                HStack(spacing: 5) {
                    if checking {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(checking ? "Checking…" : "Check Now")
                }
            }
            .disabled(state.config.paused || state.config.accounts.isEmpty || checking)
            .help("Check every account now")
            Spacer()
            if !state.items.isEmpty {
                Button { withAnimation(buddySpring) { state.clearAll() } } label: {
                    Label("Clear All", systemImage: "checkmark.circle")
                }
                .help("Mark everything here as done")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

private struct PopoverRow: View {
    let item: BuddyItem
    var sample: Bool
    var pointedAt = false
    @ObservedObject var state = AppState.shared
    @Local private var hover = false

    var body: some View {
        let showActions = hover || (pointedAt && state.coachStep == .row)
        HStack(alignment: .top, spacing: 10) {
            SettingsIcon(symbol: item.source.symbol, tint: item.source.tint, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text(item.from ?? item.source.label).font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    if !showActions {
                        Text(shortAgo(item.date)).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                Text(item.title).font(.callout.weight(.medium)).lineLimit(1)
                if let d = item.detail, !d.isEmpty {
                    Text(d).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            if showActions {
                HStack(spacing: 4) {
                    if item.url != nil || sample {
                        RowActionButton(symbol: "arrow.up.forward", label: "Open") { if !sample { state.open(item) } }
                    }
                    RowActionButton(symbol: "clock", label: "Snooze 10 minutes") { if !sample { state.snooze(item) } }
                    RowActionButton(symbol: "checkmark", label: "Done") {
                        if !sample { withAnimation(buddySpring) { state.dismiss(item.id) } }
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(showActions ? Color.primary.opacity(0.06) : .clear)
            .padding(.horizontal, 6))
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
        .onTapGesture { if !sample { state.open(item) } }
        .contextMenu {
            if !sample {
                if item.url != nil { Button("Open") { state.open(item) } }
                Button("Snooze 10 Minutes") { state.snooze(item) }
                Divider()
                Button("Done") { state.dismiss(item.id) }
                Button("Clear All from \(state.ownerName(item.owner))") { state.clearAll(owner: item.owner) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Open") { state.open(item) }
        .accessibilityAction(named: "Snooze") { state.snooze(item) }
        .accessibilityAction(named: "Done") { state.dismiss(item.id) }
    }
}

extension BuddyItem {
    /// Shown only while the tour points at a notification and nothing real is waiting.
    static let coachSample = BuddyItem(id: "coach:sample", source: .mail, accountID: nil, title: "Contract ready to sign",
                                       from: "Sample sender", detail: "This is an example notification.",
                                       date: Date(), url: URL(string: "https://example.com"))
}

/// "now", "4m", "2h", "3d" — compact like Notification Center.
func shortAgo(_ d: Date) -> String {
    let s = max(0, Int(Date().timeIntervalSince(d)))
    if s < 60 { return "now" }
    if s < 3600 { return "\(s / 60)m" }
    if s < 86_400 { return "\(s / 3600)h" }
    return "\(s / 86_400)d"
}

// MARK: - Button styles

/// Round icon in a soft circle that's always visible, so it reads as a button; stronger on hover.
private struct HeaderIconLabel: View {
    let symbol: String
    let tint: Color?
    var hover = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tint ?? Color.primary)
            .frame(width: 28, height: 28)
            .background(Circle().fill(Color.primary.opacity(hover ? 0.16 : 0.08)))
            .contentShape(Circle())
    }
}

/// Round header button like Control Center's.
private struct HeaderIconButton: View {
    let symbol: String
    let tint: Color?
    let label: String
    let action: () -> Void
    @Local private var hover = false

    var body: some View {
        Button(action: action) { HeaderIconLabel(symbol: symbol, tint: tint, hover: hover) }
            .buttonStyle(PressableStyle())
            .onHover { hover = $0 }
            .help(label)
            .accessibilityLabel(label)
    }
}

/// Small filled capsule button ("✕ Clear") for section headers.
struct PillButton: View {
    let title: String
    let symbol: String
    let label: String
    let action: () -> Void
    @Local private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 8, weight: .bold))
                Text(title).font(.caption.weight(.medium))
            }
            .foregroundStyle(Color.primary.opacity(0.85))
            .padding(.horizontal, 8).frame(height: 20)
            .background(Capsule().fill(Color.primary.opacity(hover ? 0.16 : 0.09)))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .onHover { hover = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Circular quick action on a notification row (Open, Snooze, Done).
private struct RowActionButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    @Local private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hover ? Color.white : Color.primary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(hover ? Color.accentColor : Color.primary.opacity(0.1)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hover = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Instant press feedback (scale on mouse-down), per Apple's "respond on press" guidance.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
