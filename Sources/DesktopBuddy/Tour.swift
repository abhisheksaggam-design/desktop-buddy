import SwiftUI
import AppKit

// MARK: - Coach marks (menu bar dropdown)

/// The controls the dropdown tour points at, in order.
enum CoachStep: Int, CaseIterable, Identifiable {
    case header, accounts, row, footer
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .header: return "Pause, Settings and more"
        case .accounts: return "Your accounts"
        case .row: return "Act on a notification"
        case .footer: return "Check or clear"
        }
    }

    var text: String {
        switch self {
        case .header: return "Pause everything with the moon. Settings is the gear. Updates, this tour and Quit are under •••."
        case .accounts: return "Switch an account off for a while. Nothing is lost; turn it on again any time."
        case .row: return "Click to open it. Hover for Open, Snooze and Done, or right-click."
        case .footer: return "Check every account now, or clear everything you've seen."
        }
    }

    /// Steps shown for the current state: no accounts strip means no accounts step.
    static func steps(hasAccounts: Bool) -> [CoachStep] {
        allCases.filter { hasAccounts || $0 != .accounts }
    }
}

extension AppState {
    /// First time the dropdown opens after the welcome tour (or after "Show Tour").
    func startCoachMarksIfNeeded() {
        guard coachStep == nil, config.tourSeen == true, config.popoverTourSeen != true,
              !config.accounts.isEmpty else { return }
        coachStep = CoachStep.steps(hasAccounts: true).first
    }

    func nextCoachStep() {
        let steps = CoachStep.steps(hasAccounts: !config.accounts.isEmpty)
        guard let s = coachStep, let i = steps.firstIndex(of: s), i + 1 < steps.count else { return finishCoachMarks() }
        coachStep = steps[i + 1]
    }

    func finishCoachMarks() {
        coachStep = nil
        config.popoverTourSeen = true
    }

    /// Plays the welcome tour again, and the dropdown tips the next time it opens.
    func replayTour() {
        config.popoverTourSeen = nil
        coachStep = nil
    }
}

private struct CoachKey: PreferenceKey {
    static var defaultValue: [CoachStep: Anchor<CGRect>] = [:]
    static func reduce(value: inout [CoachStep: Anchor<CGRect>], nextValue: () -> [CoachStep: Anchor<CGRect>]) {
        value.merge(nextValue()) { a, _ in a }
    }
}

extension View {
    /// Marks this view as what a coach-mark step points at.
    func coachTarget(_ step: CoachStep, when on: Bool = true) -> some View {
        anchorPreference(key: CoachKey.self, value: .bounds) { on ? [step: $0] : [:] }
    }

    /// Draws the current coach mark over this view: dim everywhere except the target, plus a bubble.
    func coachMarks() -> some View {
        overlayPreferenceValue(CoachKey.self) { anchors in
            GeometryReader { proxy in
                if let step = AppState.shared.coachStep, let anchor = anchors[step] {
                    CoachOverlay(step: step, target: proxy[anchor], size: proxy.size)
                }
            }
        }
    }
}

private struct CoachOverlay: View {
    let step: CoachStep
    let target: CGRect
    let size: CGSize
    @ObservedObject var state = AppState.shared

    var body: some View {
        let hole = target.insetBy(dx: 4, dy: 2)
        let steps = CoachStep.steps(hasAccounts: !state.config.accounts.isEmpty)
        let index = (steps.firstIndex(of: step) ?? 0) + 1
        let bubbleBelow = hole.midY < size.height / 2
        ZStack(alignment: .topLeading) {
            // Dim with a cut-out; clicks on the dim area are swallowed so the tour stays in charge.
            Path { p in
                p.addRect(CGRect(origin: .zero, size: size))
                p.addRoundedRect(in: hole, cornerSize: CGSize(width: 8, height: 8), style: .continuous)
            }
            .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
            .contentShape(Rectangle())
            .onTapGesture {}
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.accentColor, lineWidth: 2)
                .frame(width: hole.width, height: hole.height)
                .offset(x: hole.minX, y: hole.minY)
                .allowsHitTesting(false)

            CoachBubble(step: step, index: index, count: steps.count)
                .frame(width: size.width - 40)
                .fixedSize(horizontal: false, vertical: true)
                .alignmentGuide(.top) { d in
                    bubbleBelow ? -(hole.maxY + 10) : -(hole.minY - 10 - d.height)
                }
                .offset(x: 20)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .transition(.opacity)
        .animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .easeOut(duration: 0.18), value: step)
    }
}

private struct CoachBubble: View {
    let step: CoachStep
    let index: Int
    let count: Int
    @ObservedObject var state = AppState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(index) of \(count)").font(.caption2.weight(.semibold)).foregroundStyle(.secondary).monospacedDigit()
            Text(step.title).font(.headline)
            Text(step.text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Skip Tips") { state.finishCoachMarks() }.buttonStyle(.borderless).font(.callout)
                Spacer()
                Button(index == count ? "Got It" : "Next") { state.nextCoachStep() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.1)))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tip \(index) of \(count): \(step.title)")
    }
}

// MARK: - Welcome tour (window)

enum TourPage: Int, CaseIterable {
    case welcome, menuBar, logos, filters, sounds
}

@MainActor
final class TourController: NSObject, NSWindowDelegate {
    static let shared = TourController()
    private var window: NSWindow?
    /// Called when the tour closes, with true if the person asked to add an account.
    var onClose: (Bool) -> Void = { _ in }

    /// Once for everyone: new users on first launch, existing users on their first launch after updating.
    /// Accounts and sign-ins are untouched; existing users just close it with Done.
    static func shouldShowOnLaunch(_ config: AppConfig) -> Bool {
        config.tourSeen != true
    }

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: TourView(finish: { [weak self] addAccount in self?.close(addAccount: addAccount) }))
            let w = NSWindow(contentViewController: host)
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.title = "Welcome to Desktop Buddy"
            w.setContentSize(NSSize(width: 560, height: 470))
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private var addAccount = false

    func close(addAccount: Bool) {
        self.addAccount = addAccount
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        AppState.shared.config.tourSeen = true
        window = nil
        let add = addAccount
        addAccount = false
        DispatchQueue.main.async { self.onClose(add) }
    }
}

struct TourView: View {
    var finish: (_ addAccount: Bool) -> Void
    @Local private var page: TourPage
    @ObservedObject var state = AppState.shared

    init(start: TourPage = .welcome, finish: @escaping (_ addAccount: Bool) -> Void) {
        self.finish = finish
        _page = Local(wrappedValue: start)
    }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                pageView(page)
                    .id(page)
                    .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                                     removal: .move(edge: .leading).combined(with: .opacity)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            HStack {
                if page == .welcome {
                    Button("Skip Tour") { finish(false) }.buttonStyle(.borderless)
                } else {
                    Button("Back") { go(-1) }
                }
                Spacer()
                HStack(spacing: 7) {
                    ForEach(TourPage.allCases, id: \.self) { p in
                        Circle().fill(p == page ? Color.accentColor : Color.primary.opacity(0.18)).frame(width: 7, height: 7)
                    }
                }
                .accessibilityElement().accessibilityLabel("Page \(page.rawValue + 1) of \(TourPage.allCases.count)")
                Spacer()
                if page == .sounds {
                    Button(state.config.accounts.isEmpty ? "Add Your First Account" : "Done") {
                        finish(state.config.accounts.isEmpty)
                    }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                } else {
                    Button("Continue") { go(1) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                }
            }
            .controlSize(.large)
            .padding(.horizontal, 24).padding(.vertical, 18)
        }
        .frame(width: 560, height: 470)
        .background(Color(nsColor: .windowBackgroundColor))
        .onExitCommand { finish(false) }
    }

    private func go(_ delta: Int) {
        guard let next = TourPage(rawValue: page.rawValue + delta) else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.9)) { page = next }
    }

    @ViewBuilder
    private func pageView(_ p: TourPage) -> some View {
        switch p {
        case .welcome:
            TourPageLayout(title: state.config.accounts.isEmpty ? "Welcome to Desktop Buddy" : "What's new in Desktop Buddy",
                           text: state.config.accounts.isEmpty
                               ? "A quiet heads-up when something needs you in Google Workspace or Microsoft 365: new mail, chats, meetings about to start, and tasks due today."
                               : "A quick look at what's changed. Your accounts and settings are just as you left them.") {
                AppMark(size: 96)
            } footnote: {
                Label("Read-only. Desktop Buddy never sends, changes or deletes anything.", systemImage: "lock.fill")
            }
        case .menuBar:
            TourPageLayout(title: "It lives in your menu bar",
                           text: "The number shows what's waiting. Click it to see everything, check now, or pause for a while.") {
                MenuBarPreview()
            } footnote: {
                Label("Right-click it for quick options.", systemImage: "cursorarrow.click.2")
            }
        case .logos:
            TourPageLayout(title: "Logos on your screen",
                           text: "Each account or client gets its own logo in the corner of your screen. Click one to see what's waiting from them.") {
                HStack(spacing: -14) {
                    ForEach(Array(sampleOwners.enumerated()), id: \.offset) { i, o in
                        LogoTile(url: Logos.bundledURL(o.0), name: o.1, tint: o.2, size: 72)
                            .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
                            .zIndex(Double(sampleOwners.count - i))
                    }
                }
            } footnote: {
                Label("Drag a logo anywhere. It stays where you put it.", systemImage: "hand.draw")
            }
        case .filters:
            TourPageLayout(title: "Only what matters", text: "Tell Desktop Buddy what to call out and what to ignore, in Settings.") {
                VStack(alignment: .leading, spacing: 14) {
                    TourFeature(symbol: "person.2.fill", tint: .green, title: "Clients",
                                text: "Group a client's mail and chats under their logo.")
                    TourFeature(symbol: "speaker.slash.fill", tint: .gray, title: "Mute",
                                text: "Never hear about newsletters or noisy senders again.")
                    TourFeature(symbol: "tag.fill", tint: .orange, title: "Labels",
                                text: "Only get mail your Gmail labels or Outlook categories pick out.")
                }
                .frame(width: 380)
            } footnote: { EmptyView() }
        case .sounds:
            TourPageLayout(title: "A sound for each kind",
                           text: "Know what arrived without looking. Pick a sound for mail, chats, meetings, tasks and reminders. Try one:") {
                VStack(spacing: 10) {
                    SoundRow(source: .mail)
                    Divider()
                    SoundRow(source: .meeting)
                }
                .padding(14)
                .frame(width: 340)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
            } footnote: {
                Label("Change them any time in Settings → General.", systemImage: "gearshape")
            }
        }
    }

    private var sampleOwners: [(String, String, Color)] {
        [("dynamatix", "Dynamatix", .blue), ("gatehouse", "Gatehouse", .green), ("riskhawk", "RiskHawk", .orange)]
    }
}

private struct TourPageLayout<Art: View, Foot: View>: View {
    let title: String
    let text: String
    @ViewBuilder var art: Art
    @ViewBuilder var footnote: Foot

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 24)
            art.frame(height: 150)
            VStack(spacing: 8) {
                Text(title).font(.system(size: 24, weight: .bold))
                Text(text).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .frame(maxWidth: 420).fixedSize(horizontal: false, vertical: true)
            }
            footnote.font(.callout).foregroundStyle(.secondary)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 32)
    }
}

private struct TourFeature: View {
    let symbol: String
    let tint: Color
    let title: String
    let text: String
    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(symbol: symbol, tint: tint, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline)
                Text(text).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

/// A slice of a menu bar with the Desktop Buddy mark and a count.
private struct MenuBarPreview: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "wifi").opacity(0.6)
            Image(systemName: "battery.75percent").opacity(0.6)
            HStack(spacing: 3) {
                Image(nsImage: MenuBarMark.image(paused: false))
                Text("3").font(.system(size: 13, weight: .semibold)).monospacedDigit()
            }
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.12)))
            Text("Mon 9:41").opacity(0.6)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 18).frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.bar))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.1)))
        .scaleEffect(1.6)
    }
}

// MARK: - Menu bar mark

/// The Desktop Buddy mark as a monochrome template image, so the menu bar tints it for light and dark.
enum MenuBarMark {
    private static var cache: [Bool: NSImage] = [:]

    static func image(paused: Bool) -> NSImage {
        if let img = cache[paused] { return img }
        let size = NSSize(width: 18, height: 18)
        let source = Logos.bundledURL("dynamatix").flatMap(NSImage.init(contentsOf:))
        let img = NSImage(size: size, flipped: false) { rect in
            if let source {
                // Fit the logo's silhouette (its alpha) into the square.
                let s = source.size
                let scale = min(rect.width / s.width, rect.height / s.height)
                let w = s.width * scale, h = s.height * scale
                let r = NSRect(x: (rect.width - w) / 2, y: (rect.height - h) / 2, width: w, height: h)
                source.draw(in: r, from: .zero, operation: .sourceOver, fraction: paused ? 0.4 : 1)
            } else {
                NSImage(systemSymbolName: "bell", accessibilityDescription: nil)?.draw(in: rect)
            }
            if paused {
                // A slash, like bell.slash.
                let p = NSBezierPath()
                p.move(to: NSPoint(x: 2, y: 16)); p.line(to: NSPoint(x: 16, y: 2))
                p.lineWidth = 2; p.lineCapStyle = .round
                NSColor.black.setStroke(); p.stroke()
            }
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "Desktop Buddy"
        cache[paused] = img
        return img
    }

    /// The number next to the mark: what's waiting, or nothing when paused or empty.
    static func title(count: Int, paused: Bool) -> String {
        count > 0 && !paused ? "\(count)" : ""
    }
}
