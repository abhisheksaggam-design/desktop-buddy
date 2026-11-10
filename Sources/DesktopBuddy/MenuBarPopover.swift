import SwiftUI
import AppKit

/// What you see when you click the menu bar icon: quick controls + everything waiting, grouped by account.
struct MenuBarPopover: View {
    @ObservedObject var state = AppState.shared
    var openSettings: () -> Void
    var showTour: () -> Void = {}
    var checkForUpdates: () -> Void = {}
    var reportBug: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            header
            UpdateBanner()
            Divider()
            if !state.config.accounts.isEmpty {
                accountsStrip
                Divider()
            }
            content
            Divider()
            footer
        }
        .frame(width: 360)
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
                if FeedbackSender.isSetUp {
                    Button("Report a Bug or Idea…", action: reportBug)
                }
                if state.config.hidesFromSharing {
                    Button("Allow Screenshots for 1 Minute") { DockController.shared.allowScreenshots() }
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

    private var allAccountsOff: Bool { !state.config.accounts.isEmpty && !state.config.accounts.contains { $0.enabled } }

    private var subtitle: String {
        if state.config.paused { return "Paused" }
        if state.isQuietNow { return "Quiet hours" }
        if allAccountsOff { return "All accounts off" }
        let n = state.items.count
        return n == 0 ? "Nothing waiting" : "\(n) waiting"
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
                    Toggle("Notifications from \(a.label)", isOn: Binding(get: { a.enabled },
                                                  set: { var x = a; x.enabled = $0; state.update(x) }))
                        .toggleStyle(.switch).labelsHidden().controlSize(.mini)
                        .help(a.enabled ? "Stop notifications from \(a.label)" : "Get notifications from \(a.label)")
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
        } else if state.items.isEmpty {
            VStack(spacing: 6) {
                if state.config.paused {
                    Image(systemName: "moon.fill").font(.system(size: 26)).foregroundStyle(.indigo)
                    Text("Paused").font(.headline)
                    Text("Nothing will arrive until you resume.").font(.callout).foregroundStyle(.secondary)
                } else if allAccountsOff {
                    Image(systemName: "power").font(.system(size: 26)).foregroundStyle(.secondary)
                    Text("Your accounts are switched off").font(.headline)
                    Text("Turn one on above to get notifications.").font(.callout).foregroundStyle(.secondary)
                } else {
                    Image(systemName: "checkmark.circle").font(.system(size: 28)).foregroundStyle(.green)
                    Text("All caught up").font(.headline)
                    Text("Nothing needs you right now.").font(.callout).foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
            .padding(26)
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(state.activeOwners, id: \.self) { owner in
                        let mine = state.items.filter { $0.owner == owner }
                        Section {
                            ForEach(mine) { item in
                                PopoverRow(item: item, sample: false)
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
                                .help("Remove these from Desktop Buddy. Nothing changes in your mail or chats.")
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
            if let undo = state.undo {
                UndoPill(undo: undo)
            } else if !state.items.isEmpty {
                Button { withAnimation(buddySpring) { state.clearAll() } } label: {
                    Label("Clear All", systemImage: "checkmark.circle")
                }
                .help("Remove these from Desktop Buddy. Nothing changes in your mail or chats.")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

private struct PopoverRow: View {
    let item: BuddyItem
    var sample: Bool
    @ObservedObject var state = AppState.shared
    @Local private var hover = false
    @FocusState private var focused: Bool

    var body: some View {
        // Same layout as the on-screen list and the pop-up: logo with service badge, then
        // service, headline, subhead and preview. Keyboard: Tab to a row, Return opens, Delete is Done.
        let keyFocused = focused && state.usingKeyboard
        let showActions = hover || keyFocused
        HStack(alignment: .top, spacing: 10) {
            CardIcon(item: item, size: 30).padding(.top, 2)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(item.serviceName).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 6)
                    if showActions {
                        HStack(spacing: 4) {
                            if item.url != nil || sample {
                                RowActionButton(symbol: "arrow.up.forward", label: "Open") { if !sample { state.open(item) } }
                            }
                            RowActionButton(symbol: "checkmark", label: "Done") {
                                if !sample { withAnimation(buddySpring) { state.done(item.id) } }
                            }
                            .help(item.doneHelp)
                        }
                        .transition(.opacity)
                    } else {
                        Text(shortAgo(item.date)).font(.subheadline).foregroundStyle(.tertiary).monospacedDigit()
                    }
                }
                .frame(height: 24)
                Text(item.headline).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                if let sub = item.subhead, !sub.isEmpty {
                    Text(sub).font(.system(size: 13)).lineLimit(1)
                }
                if let d = item.detail, !d.isEmpty {
                    Text(d).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(showActions ? Color.primary.opacity(0.06) : .clear)
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.accentColor, lineWidth: keyFocused ? 2 : 0))
            .padding(.horizontal, 6))
        .contentShape(Rectangle())
        .focusable(!sample)
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.return) { if !sample { state.open(item) }; return .handled }
        .onKeyPress(.delete) { if !sample { withAnimation(buddySpring) { state.done(item.id) } }; return .handled }
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
        .onTapGesture { if !sample { state.open(item) } }
        .contextMenu {
            if !sample {
                if item.url != nil { Button("Open in \(item.serviceName)") { state.open(item) } }
                Divider()
                Button("Done") { state.done(item.id) }
                Button("Clear All from \(state.ownerName(item.owner))") { state.clearAll(owner: item.owner) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Open") { state.open(item) }
        .accessibilityAction(named: "Done") { state.done(item.id) }
    }
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

/// Circular quick action on a notification row (Open, Done).
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

/// "3 removed · Undo", shown for a few seconds after Done or Clear.
struct UndoPill: View {
    let undo: UndoClear
    var dark = false
    @ObservedObject var state = AppState.shared
    var body: some View {
        HStack(spacing: 8) {
            Text(undo.label).font(.system(size: 12)).foregroundStyle(dark ? Color.white.opacity(0.7) : Color.secondary)
            Button { withAnimation(buddySpring) { state.undoLast() } } label: {
                Label("Undo", systemImage: "arrow.uturn.backward").font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10).frame(height: 26)
            }
            .modifier(UndoButtonLook(dark: dark))
            .keyboardShortcut("z", modifiers: .command)
            .help("Put back what you just removed (⌘Z)")
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
        .accessibilityElement(children: .contain)
    }
}

private struct UndoButtonLook: ViewModifier {
    let dark: Bool
    func body(content: Content) -> some View {
        if dark {
            content.buttonStyle(DarkCapsuleStyle(fill: 1, hoverFill: 0.85)).foregroundStyle(.black)
        } else {
            content.buttonStyle(.bordered).controlSize(.small)
        }
    }
}

/// Capsule button for the dark surfaces (pop-up, on-screen list): a white wash that brightens on hover,
/// plus the same press feedback as `PressableStyle`.
struct DarkCapsuleStyle: ButtonStyle {
    var fill: Double = 0.14
    var hoverFill: Double = 0.22
    func makeBody(configuration: Configuration) -> some View {
        DarkCapsuleBody(configuration: configuration, fill: fill, hoverFill: hoverFill)
    }
}

private struct DarkCapsuleBody: View {
    let configuration: ButtonStyleConfiguration
    let fill: Double
    let hoverFill: Double
    @Local private var hover = false
    var body: some View {
        configuration.label
            .background(Capsule().fill(Color.white.opacity(hover ? hoverFill : fill)))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Instant press feedback (scale on mouse-down), per Apple's "respond on press" guidance.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
