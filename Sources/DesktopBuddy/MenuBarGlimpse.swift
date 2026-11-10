import SwiftUI
import AppKit
import Combine

// MARK: - Menu bar pop-up ("island")

/// When something new arrives, a small black island drops from the top centre of the screen, opens into a
/// card with who it's from and what it says, and tucks itself back in after 10 seconds.
/// Hovering pauses the timer so you can read; clicking opens the notification; "View more" opens the list.
@MainActor
final class GlimpseController {
    static let shared = GlimpseController()
    static let showSeconds: TimeInterval = 10

    /// Opens the menu bar dropdown (set by the app delegate).
    var viewMore: () -> Void = {}

    private let panel: NSPanel
    private let model = GlimpseModel()
    private var bag = Set<AnyCancellable>()
    private let state = AppState.shared
    private var knownIDs: Set<String>
    private var hideWork: DispatchWorkItem?
    /// Time left before it tucks away; frozen while the pointer is over it.
    private var remaining = GlimpseController.showSeconds
    private var deadline: Date?

    private init() {
        knownIDs = Set(AppState.shared.items.map(\.id))
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: GlimpsePlacement.canvas),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        let host = GlimpseHostingView(rootView: GlimpseView(model: model, actions: GlimpseActions(
            open: { [weak self] in self?.openCurrent() },
            done: { [weak self] in self?.doneCurrent() },
            close: { [weak self] in self?.hide() },
            viewMore: { [weak self] in self?.hide(); self?.viewMore() })))
        // An AppKit tracking area sees the pointer even while another app is in front.
        host.onHover = { [weak self] on in self?.hovering(on) }
        panel.contentView = host

        state.$items
            .receive(on: RunLoop.main)
            .sink { [weak self] items in self?.itemsChanged(items) }
            .store(in: &bag)
        state.$screenshotsAllowedUntil.combineLatest(state.$config.map(\.hidesFromSharing).removeDuplicates())
            .receive(on: RunLoop.main)
            .sink { [weak self] until, protect in
                self?.panel.sharingType = OverlayPlacement.sharingHidden(protection: protect, allowedUntil: until) ? .none : .readOnly
            }
            .store(in: &bag)
    }

    private func itemsChanged(_ items: [BuddyItem]) {
        let ids = Set(items.map(\.id))
        let arrived = GlimpsePlacement.arrivals(previous: knownIDs, now: items)
        knownIDs = ids
        // The one on show was cleared (read elsewhere, Done in the dropdown): tuck away.
        if let shown = model.item, !ids.contains(shown.id) {
            if let next = items.first(where: { arrived.contains($0) }) { model.item = next } else { hide(); return }
        }
        guard !arrived.isEmpty, GlimpsePlacement.shouldShow(paused: state.config.paused, quiet: state.isQuietNow) else { return }
        show(arrived)
    }

    /// Newest arrival on top; "N more" counts the rest that came while it was open.
    func show(_ arrived: [BuddyItem]) {
        guard let newest = arrived.max(by: { $0.date < $1.date }) else { return }
        let wasOpen = model.phase != .hidden
        model.more = (wasOpen ? model.more + (model.item == nil ? 0 : 1) : 0) + arrived.count - 1
        model.item = newest
        // VoiceOver users hear it arrive.
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
            .announcement: "\(newest.serviceName), \(newest.headline)" + (newest.subhead.map { ": \($0)" } ?? ""),
            .priority: NSAccessibilityPriorityLevel.medium.rawValue,
        ])
        place()
        if !panel.isVisible { panel.orderFrontRegardless() }
        if !wasOpen {
            model.phase = .pill
            let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            DispatchQueue.main.asyncAfter(deadline: .now() + (reduce ? 0 : 0.18)) { [weak self] in
                guard let self, self.model.phase == .pill else { return }
                self.model.phase = .open
            }
        }
        remaining = Self.showSeconds
        if model.hovering { model.setProgress(1, over: nil) } else { startTimer() }
    }

    func hide() {
        hideWork?.cancel()
        deadline = nil
        guard model.phase != .hidden else { return }
        model.phase = .pill
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            guard let self, self.model.phase == .pill else { return }
            self.model.phase = .hidden
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self, self.model.phase == .hidden else { return }
                self.panel.orderOut(nil)
                self.model.item = nil
                self.model.more = 0
            }
        }
    }

    /// Counts down whatever time is left.
    private func startTimer() {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        deadline = Date().addingTimeInterval(remaining)
        model.setProgress(remaining / Self.showSeconds, over: nil)
        model.setProgress(0, over: remaining)
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining, execute: work)
    }

    /// Pointer over the pop-up: stop the clock so it can be read. Pointer off: carry on from there.
    private func hovering(_ on: Bool) {
        guard model.phase != .hidden || !on else { return }
        model.hovering = on
        if on {
            hideWork?.cancel()
            if let deadline { remaining = GlimpsePlacement.timeLeft(deadline: deadline, now: Date()) }
            deadline = nil
            model.setProgress(remaining / Self.showSeconds, over: nil)
        } else if model.phase != .hidden {
            remaining = max(remaining, GlimpsePlacement.minimumAfterHover)
            startTimer()
        }
    }

    private func openCurrent() {
        guard let item = model.item else { return hide() }
        state.open(item)
        hide()
    }

    private func doneCurrent() {
        guard let item = model.item else { return hide() }
        state.done(item.id)
        hide()
    }

    /// Top centre of the main display, just under the menu bar, where your eyes go first.
    private func place() {
        guard let screen = NSScreen.screens.first else { return }
        let frame = GlimpsePlacement.frame(screen: screen.frame, visible: screen.visibleFrame)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }

    /// Test hook output.
    func printStatus() {
        print("glimpse \(model.phase) visible \(panel.isVisible) frame \(panel.frame) item \(model.item?.title ?? "-") more \(model.more) hovering \(model.hovering) left \(deadline.map { String(format: "%.1f", $0.timeIntervalSinceNow) } ?? "paused")")
        fflush(stdout)
    }
}

/// Placement and timing rules, kept apart so they can be tested.
enum GlimpsePlacement {
    /// The panel never resizes (resizing makes content jump); the card animates inside it.
    static let card = NSSize(width: 372, height: 120)       // the tallest it gets; shorter messages are shorter
    static let viewMore = NSSize(width: 104, height: 24)
    static let spacing: CGFloat = 6           // between the card and "View more"
    static let margin: CGFloat = 2
    static var canvas: NSSize {
        NSSize(width: card.width + margin * 2, height: card.height + spacing + viewMore.height + margin * 2)
    }
    static let gap: CGFloat = 6               // between the menu bar and the island

    static func frame(screen: NSRect, visible: NSRect) -> NSRect {
        let size = canvas
        let top = visible.maxY - gap + margin        // card's top edge sits `gap` below the menu bar
        return NSRect(x: screen.midX - size.width / 2, y: top - size.height, width: size.width, height: size.height)
    }

    /// Items that weren't there before, newest first.
    static func arrivals(previous: Set<String>, now items: [BuddyItem]) -> [BuddyItem] {
        items.filter { !previous.contains($0.id) }
    }

    static func shouldShow(paused: Bool, quiet: Bool) -> Bool { !paused && !quiet }

    /// After reading, a moment to move away before it tucks itself in.
    static let minimumAfterHover: TimeInterval = 3

    static func timeLeft(deadline: Date, now: Date) -> TimeInterval { max(0, deadline.timeIntervalSince(now)) }
}

enum GlimpsePhase { case hidden, pill, open }

@MainActor
final class GlimpseModel: ObservableObject {
    @Published var phase: GlimpsePhase = .hidden
    @Published var item: BuddyItem?
    @Published var more = 0
    @Published var hovering = false
    /// Countdown bar along the bottom of the card, 1 → 0.
    @Published var progress: Double = 1

    func setProgress(_ value: Double, over seconds: TimeInterval?) {
        if let seconds {
            withAnimation(.linear(duration: seconds)) { progress = value }
        } else {
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { progress = value }
        }
    }

    /// An open island with a sample message, for the tour and screenshots.
    static var sample: GlimpseModel {
        let m = GlimpseModel()
        let a = AppState.shared.config.accounts.first
        m.item = BuddyItem(id: "sample:glimpse", source: .mail, accountID: a?.id, accountLabel: a?.label,
                           title: "Contract ready to sign", from: "Jane Cooper",
                           detail: "Hi, the final version is attached. Could you sign by Friday?", date: Date(), url: nil)
        m.more = 2
        m.phase = .open
        m.progress = 0.65
        return m
    }
}

struct GlimpseActions {
    var open: () -> Void
    var done: () -> Void
    var close: () -> Void
    var viewMore: () -> Void
}

/// Hosting view that reports the pointer entering and leaving, whichever app is in front.
final class GlimpseHostingView<Content: View>: NSHostingView<Content> {
    var onHover: (Bool) -> Void = { _ in }
    private var area: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let a = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(a)
        area = a
    }
    override func mouseEntered(with event: NSEvent) { super.mouseEntered(with: event); onHover(true) }
    override func mouseExited(with event: NSEvent) { super.mouseExited(with: event); onHover(false) }
}

private struct GlimpseHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct GlimpseView: View {
    @ObservedObject var model: GlimpseModel
    var actions: GlimpseActions
    @ObservedObject var state = AppState.shared
    /// The message's real height, so a short one doesn't leave an empty black area.
    @Local private var contentHeight: CGFloat = 0

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private var open: Bool { model.phase == .open }
    private var size: CGSize {
        switch model.phase {
        case .open:
            let h = contentHeight > 0 ? min(contentHeight, GlimpsePlacement.card.height) : GlimpsePlacement.card.height
            return CGSize(width: GlimpsePlacement.card.width, height: h)
        case .pill, .hidden: return CGSize(width: 64, height: 26)
        }
    }

    var body: some View {
        VStack(spacing: GlimpsePlacement.spacing) {
            island
                .scaleEffect(model.phase == .hidden && !reduceMotion ? 0.6 : 1, anchor: .top)
                .opacity(model.phase == .hidden ? 0 : 1)
            viewMoreButton
                .opacity(open ? 1 : 0)
                .offset(y: open || reduceMotion ? 0 : -8)
                .animation(open ? .easeOut(duration: 0.2).delay(0.12) : .easeIn(duration: 0.08), value: open)
        }
        .padding(GlimpsePlacement.margin)
        .frame(width: GlimpsePlacement.canvas.width, height: GlimpsePlacement.canvas.height, alignment: .top)
        .animation(reduceMotion ? .easeOut(duration: 0.15)
                   : (model.phase == .hidden ? .easeOut(duration: 0.18) : .spring(response: 0.38, dampingFraction: 0.88)),
                   value: model.phase)
        .environment(\.colorScheme, .dark)
    }

    private var island: some View {
        let shape = RoundedRectangle(cornerRadius: open ? 26 : 13, style: .continuous)
        // The text sits in an overlay so it never sizes the island: the island grows and the text is revealed.
        return shape.fill(Color.black)
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .topLeading) {
                if let item = model.item {
                    content(item)
                        .opacity(open ? 1 : 0)
                        .blur(radius: open || reduceMotion ? 0 : 6)
                        .animation(open ? .easeOut(duration: 0.2).delay(0.08) : .easeIn(duration: 0.1), value: open)
                        .id(item.id)
                        .transition(.opacity)
                }
            }
            .clipShape(shape)
        .overlay(shape.stroke(Color.white.opacity(0.08), lineWidth: 0.5))
        .contentShape(shape)
        .onTapGesture { actions.open() }
        .animation(.easeInOut(duration: 0.2), value: model.item?.id)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.item.map { "\($0.serviceName): \($0.headline)" } ?? "")
        .accessibilityAddTraits(.isButton)
    }

    /// Small ring that winds down over 10 seconds and stops while you hover.
    private var countdown: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.16), lineWidth: 2)
            Circle()
                .trim(from: 0, to: model.progress)
                .stroke(Color.white.opacity(model.hovering ? 0.9 : 0.6), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 13, height: 13)
        .help(model.hovering ? "Paused while you read" : "Closes in a few seconds")
        .accessibilityHidden(true)
    }

    private var viewMoreButton: some View {
        Button(action: actions.viewMore) {
            HStack(spacing: 4) {
                Text("View more").font(.system(size: 12, weight: .semibold))
                Image(systemName: "chevron.down").font(.system(size: 8.5, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(width: GlimpsePlacement.viewMore.width, height: GlimpsePlacement.viewMore.height)
            .background(Capsule().fill(Color.black))
            .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .help("See everything waiting")
        .accessibilityLabel("View more notifications")
    }

    private func content(_ item: BuddyItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            CardIcon(item: item, size: 40)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(item.source == .reminder ? item.serviceName : "\(item.serviceName) · \(state.ownerName(item.owner))")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                    Spacer(minLength: 6)
                    if model.hovering {
                        actionsRow
                    } else if model.more > 0 {
                        Text("+\(model.more) more")
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 7).padding(.vertical, 1)
                            .background(Capsule().fill(Color.white.opacity(0.16)))
                    } else {
                        Text(shortAgo(item.date)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).monospacedDigit()
                    }
                    countdown.alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                }
                .frame(height: 22)
                Text(item.headline).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                if let sub = item.subhead, !sub.isEmpty {
                    Text(sub).font(.system(size: 13)).foregroundStyle(.white.opacity(0.88)).lineLimit(1)
                }
                if let d = item.detail, !d.isEmpty {
                    Text(d).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                        .lineLimit(item.subhead?.isEmpty == false ? 1 : 2)
                }
            }
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 16)
        .frame(width: GlimpsePlacement.card.width, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { g in Color.clear.preference(key: GlimpseHeightKey.self, value: g.size.height) })
        .onPreferenceChange(GlimpseHeightKey.self) { h in if h > 0, h != contentHeight { contentHeight = h } }
    }

    private var actionsRow: some View {
        HStack(spacing: 6) {
            islandButton("Done", symbol: "checkmark", action: actions.done)
                .help(model.item?.doneHelp ?? "")
            islandButton(nil, symbol: "xmark", action: actions.close)
                .help("Hide for now. It stays in the menu bar dropdown.")
        }
    }

    private func islandButton(_ title: String?, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 9, weight: .bold))
                if let title { Text(title).font(.system(size: 12, weight: .semibold)) }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, title == nil ? 0 : 9)
            .frame(width: title == nil ? 22 : nil, height: 22)
        }
        .buttonStyle(DarkCapsuleStyle(fill: 0.18, hoverFill: 0.26))
        .accessibilityLabel(title ?? "Hide")
    }
}
