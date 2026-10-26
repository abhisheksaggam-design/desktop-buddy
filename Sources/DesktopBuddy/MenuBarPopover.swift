import SwiftUI
import AppKit

/// What you see when you click the menu bar icon: quick controls + everything waiting, grouped by account.
struct MenuBarPopover: View {
    @ObservedObject var state = AppState.shared
    var openSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
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
        HStack(alignment: .center, spacing: 10) {
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
                        Section {
                            ForEach(state.items.filter { $0.owner == owner }) { item in
                                PopoverRow(item: item)
                            }
                        } header: {
                            HStack(spacing: 6) {
                                OwnerBuddy(owner: owner, excited: false, size: 16).shadow(radius: 0)
                                Text(state.ownerName(owner)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                Spacer()
                                Button("Clear") { withAnimation(buddySpring) { state.clearAll(owner: owner) } }
                                    .buttonStyle(.borderless).font(.caption)
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
        HStack {
            Button("Check Now") {
                Task { await Poller.shared.pollAll(); Poller.shared.checkReminders() }
            }
            .disabled(state.config.paused || state.config.accounts.isEmpty)
            Spacer()
            if !state.items.isEmpty {
                Button("Clear All") { withAnimation(buddySpring) { state.clearAll() } }
            }
            Button("Quit") { NSApp.terminate(nil) }
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .padding(.horizontal, 14).padding(.vertical, 9)
    }
}

private struct PopoverRow: View {
    let item: BuddyItem
    @ObservedObject var state = AppState.shared
    @Local private var hover = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            SettingsIcon(symbol: item.source.symbol, tint: item.source.tint, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text(item.from ?? item.source.label).font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Text(shortAgo(item.date)).font(.caption2).foregroundStyle(.tertiary)
                }
                Text(item.title).font(.callout.weight(.medium)).lineLimit(1)
                if let d = item.detail, !d.isEmpty {
                    Text(d).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            if hover {
                HStack(spacing: 2) {
                    if item.url != nil {
                        Button { state.open(item) } label: { Image(systemName: "arrow.up.forward.app") }
                            .help("Open").accessibilityLabel("Open")
                    }
                    Button { state.snooze(item) } label: { Image(systemName: "clock") }
                        .help("Snooze 10 minutes").accessibilityLabel("Snooze 10 minutes")
                    Button { withAnimation(buddySpring) { state.dismiss(item.id) } } label: { Image(systemName: "checkmark") }
                        .help("Done").accessibilityLabel("Done")
                }
                .buttonStyle(.borderless)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(hover ? Color.primary.opacity(0.06) : .clear)
            .padding(.horizontal, 6))
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
        .onTapGesture { state.open(item) }
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

/// Round icon button like Control Center's: full-contrast glyph, soft circle on hover/press.
private struct HeaderIconButton: View {
    let symbol: String
    let tint: Color?
    let label: String
    let action: () -> Void
    @Local private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(tint ?? Color.primary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.primary.opacity(hover ? 0.1 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hover = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Instant press feedback (scale on mouse-down), per Apple's "respond on press" guidance.
private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
