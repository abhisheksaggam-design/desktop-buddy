import SwiftUI
import AppKit
import Combine

// MARK: - On-screen dock

/// Where the dock can sit: the corners of the main display, along the bottom or up a side.
/// (The middle of each edge is left free: that's where bars like Wispr Flow's sit.)
enum DockSpot: String, Codable, CaseIterable, Identifiable {
    case bottomLeft, bottomRight
    case leftTop, leftBottom
    case rightTop, rightBottom
    var id: String { rawValue }

    static let standard: DockSpot = .bottomRight

    /// Reads a saved place; places that no longer exist move to the nearest corner.
    static func saved(_ raw: String?) -> DockSpot {
        guard let raw else { return standard }
        if let s = DockSpot(rawValue: raw) { return s }
        switch raw {
        case "leftMiddle": return .leftBottom
        case "rightMiddle": return .rightBottom
        default: return standard
        }
    }

    enum Edge { case bottom, left, right }
    var edge: Edge {
        switch self {
        case .bottomLeft, .bottomRight: return .bottom
        case .leftTop, .leftBottom: return .left
        case .rightTop, .rightBottom: return .right
        }
    }
    var vertical: Bool { edge != .bottom }

    var name: String {
        switch self {
        case .bottomLeft: return "Bottom, left corner"
        case .bottomRight: return "Bottom, right corner"
        case .leftTop: return "Left side, top"
        case .leftBottom: return "Left side, bottom"
        case .rightTop: return "Right side, top"
        case .rightBottom: return "Right side, bottom"
        }
    }

    /// Which corner of the dock is pinned to the place's anchor point (0 = left/bottom, 1 = right/top).
    var align: CGPoint {
        switch self {
        case .bottomLeft, .leftBottom: return CGPoint(x: 0, y: 0)
        case .bottomRight, .rightBottom: return CGPoint(x: 1, y: 0)
        case .leftTop: return CGPoint(x: 0, y: 1)
        case .rightTop: return CGPoint(x: 1, y: 1)
        }
    }

    /// The same pinning for SwiftUI (whose y runs downwards).
    var alignment: Alignment {
        switch self {
        case .bottomLeft, .leftBottom: return .bottomLeading
        case .bottomRight, .rightBottom: return .bottomTrailing
        case .leftTop: return .topLeading
        case .rightTop: return .topTrailing
        }
    }

    /// Chevron points into the screen, where the list opens.
    var chevron: String {
        switch edge {
        case .bottom: return "chevron.up"
        case .left: return "chevron.right"
        case .right: return "chevron.left"
        }
    }
}

/// Placement maths, kept apart so it can be tested.
enum DockPlacement {
    static let edgeInset: CGFloat = 10        // from the screen edge (the bar has 6pt of room around it)
    static let cornerInset: CGFloat = 96      // keeps a corner's two places apart
    static let sideTopInset: CGFloat = 24
    static let item: CGFloat = 30
    static let listSize = NSSize(width: 380, height: 500)   // about four notifications, then it scrolls
    static let listGap: CGFloat = 10
    /// Fixed canvas (never resized while things animate), with room for the hover label.
    static func canvasSize(vertical: Bool) -> NSSize { vertical ? NSSize(width: 420, height: 720) : NSSize(width: 820, height: 150) }
    /// The size setting (Appearance → On Screen) scales the logos.
    static let scaleRange: ClosedRange<Double> = 0.8...1.6
    static func item(scale: Double) -> CGFloat { (item * CGFloat(min(max(scale, scaleRange.lowerBound), scaleRange.upperBound))).rounded() }
    static func zoneSize(vertical: Bool) -> NSSize { vertical ? NSSize(width: 64, height: 160) : NSSize(width: 160, height: 64) }

    /// The point each place pins its dock to.
    static func anchor(_ spot: DockSpot, in vf: NSRect) -> NSPoint {
        switch spot {
        case .bottomLeft: return NSPoint(x: vf.minX + cornerInset, y: vf.minY + edgeInset)
        case .bottomRight: return NSPoint(x: vf.maxX - cornerInset, y: vf.minY + edgeInset)
        case .leftTop: return NSPoint(x: vf.minX + edgeInset, y: vf.maxY - sideTopInset)
        case .leftBottom: return NSPoint(x: vf.minX + edgeInset, y: vf.minY + cornerInset)
        case .rightTop: return NSPoint(x: vf.maxX - edgeInset, y: vf.maxY - sideTopInset)
        case .rightBottom: return NSPoint(x: vf.maxX - edgeInset, y: vf.minY + cornerInset)
        }
    }

    /// A box of `size` pinned to the place's anchor.
    static func pinned(_ size: NSSize, _ spot: DockSpot, in vf: NSRect) -> NSRect {
        let p = anchor(spot, in: vf)
        return NSRect(x: p.x - spot.align.x * size.width, y: p.y - spot.align.y * size.height,
                      width: size.width, height: size.height)
    }

    static func canvas(_ spot: DockSpot, in vf: NSRect) -> NSRect { pinned(canvasSize(vertical: spot.vertical), spot, in: vf) }

    /// The light-up target drawn while dragging.
    static func zone(_ spot: DockSpot, in vf: NSRect) -> NSRect { pinned(zoneSize(vertical: spot.vertical), spot, in: vf) }

    /// The place closest to where the dock is being dragged.
    static func nearest(to point: NSPoint, in vf: NSRect) -> DockSpot {
        DockSpot.allCases.min { a, b in
            let za = zone(a, in: vf), zb = zone(b, in: vf)
            return hypot(za.midX - point.x, za.midY - point.y) < hypot(zb.midX - point.x, zb.midY - point.y)
        }!
    }

    /// The list opens next to the dock, into the screen, and stays on it.
    static func list(beside dock: NSRect, _ spot: DockSpot, in vf: NSRect) -> NSRect {
        let s = listSize
        var r = NSRect(origin: .zero, size: s)
        switch spot.edge {
        case .bottom:
            r.origin.y = dock.maxY + listGap
            r.origin.x = spot.align.x == 0 ? dock.minX : dock.maxX - s.width
        case .left, .right:
            r.origin.x = spot.edge == .left ? dock.maxX + listGap : dock.minX - listGap - s.width
            r.origin.y = spot.align.y == 1 ? dock.maxY - s.height : dock.minY
        }
        r.origin.x = min(max(r.origin.x, vf.minX + 8), vf.maxX - 8 - s.width)
        r.origin.y = min(max(r.origin.y, vf.minY + 8), vf.maxY - 8 - s.height)
        return r
    }
}

@MainActor
final class DockModel: ObservableObject {
    @Published var dragging = false
    @Published var target: DockSpot?          // place lit up while dragging
}

/// The logos' panel. It's a tall, mostly invisible box, and macOS normally stops a window sliding up under
/// the menu bar; that kept the logos from being dragged from a bottom place to a top one. Let it move freely.
final class FreePanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// The list's panel: it can take the keyboard (without bringing Desktop Buddy to the front), and Esc closes it.
final class KeyPanel: NSPanel {
    var onCancel: () -> Void = {}
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel() }
}

/// Owns the three on-screen panels: the dock, its list, and the places shown while dragging.
@MainActor
final class DockController {
    static let shared = DockController()

    private let dockPanel: NSPanel
    private let listPanel: NSPanel
    private let zonesPanel: NSPanel
    private let model = DockModel()
    private let state = AppState.shared
    private var bag = Set<AnyCancellable>()
    private var dockSize: CGSize = .zero
    private var dragStart: (mouse: NSPoint, origin: NSPoint)?

    private static func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        style(p)
        return p
    }

    private static func style(_ p: NSPanel) {
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
    }

    private init() {
        let dock = FreePanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        Self.style(dock)
        dockPanel = dock
        let list = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        Self.style(list)
        list.onCancel = { AppState.shared.expanded = false }
        listPanel = list
        zonesPanel = Self.makePanel()
        zonesPanel.ignoresMouseEvents = true
        dockPanel.acceptsMouseMovedEvents = true

        dockPanel.contentView = NSHostingView(rootView: DockView(
            model: model,
            onDragChanged: { [weak self] in self?.dragChanged() },
            onDragEnded: { [weak self] in self?.dragEnded() },
            onSize: { [weak self] size in
                guard let self, self.dockSize != size else { return }
                self.dockSize = size
                self.update()
            }))
        listPanel.contentView = NSHostingView(rootView: DockListView())
        zonesPanel.contentView = NSHostingView(rootView: DockZonesView(model: model))

        // Clicks pass through the empty part of the canvas: the panel only takes the mouse over the bar.
        let track: (NSEvent) -> Void = { [weak self] _ in self?.updateMousePassThrough() }
        NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: track)
        NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { track($0); return $0 }
        // Rows only show keyboard selection once Tab or the arrow keys are used, not on open.
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .mouseMoved]) { e in
            let keys: Set<UInt16> = [48, 123, 124, 125, 126]      // Tab and arrows
            let k = e.type == .keyDown ? keys.contains(e.keyCode) : false
            if k != AppState.shared.usingKeyboard && (k || e.type != .keyDown) { AppState.shared.usingKeyboard = k }
            return e
        }
        // Clicking anywhere else closes the list.
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.clickedOutside() }

        Publishers.CombineLatest3(state.$items, state.$expanded, state.$config)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _ in DispatchQueue.main.async { self?.update() } }
            .store(in: &bag)
        state.$screenshotsAllowedUntil
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.update() }
            .store(in: &bag)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.update() }
            .store(in: &bag)
    }

    private var spot: DockSpot { state.config.dockSpot }
    private var screen: NSRect { NSScreen.screens.first?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900) }

    /// Where the bar itself is on screen.
    private var dockRect: NSRect {
        let c = dockPanel.frame, a = spot.align
        let w = dockSize.width, h = dockSize.height
        return NSRect(x: c.minX + a.x * (c.width - w), y: c.minY + a.y * (c.height - h), width: w, height: h)
    }

    func update() {
        let hidden = OverlayPlacement.sharingHidden(protection: state.config.hidesFromSharing,
                                                    allowedUntil: state.screenshotsAllowedUntil)
        for p in [dockPanel, listPanel, zonesPanel] { p.sharingType = hidden ? .none : .readOnly }
        let undoShowing = state.undo != nil && state.expanded
        guard !state.items.isEmpty || undoShowing, !state.config.paused else {
            dockPanel.orderOut(nil); listPanel.orderOut(nil)
            if state.expanded { state.expanded = false }
            return
        }
        if !model.dragging {
            let canvas = DockPlacement.canvas(spot, in: screen)
            if dockPanel.frame != canvas { dockPanel.setFrame(canvas, display: true) }
        }
        if !dockPanel.isVisible { dockPanel.orderFrontRegardless() }
        if state.expanded && !model.dragging {
            listPanel.setFrame(DockPlacement.list(beside: dockRect, spot, in: screen), display: true)
            if !listPanel.isVisible {
                listPanel.orderFrontRegardless()
                listPanel.makeKey()        // so Esc closes it and Tab reaches the rows
            }
        } else {
            listPanel.orderOut(nil)
        }
        updateMousePassThrough()
    }

    private func updateMousePassThrough() {
        guard dockPanel.isVisible, !model.dragging else { return }
        let inside = dockRect.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation)
        if dockPanel.ignoresMouseEvents == inside { dockPanel.ignoresMouseEvents = !inside }
    }

    private func clickedOutside() {
        guard state.expanded else { return }
        let m = NSEvent.mouseLocation
        if !listPanel.frame.contains(m) && !dockRect.contains(m) { state.expanded = false }
    }

    // MARK: Dragging

    private func dragChanged() {
        let mouse = NSEvent.mouseLocation
        if dragStart == nil {
            dragStart = (mouse, dockPanel.frame.origin)
            model.dragging = true
            state.expanded = false
            listPanel.orderOut(nil)
            zonesPanel.setFrame(screen, display: true)
            zonesPanel.orderFrontRegardless()
            dockPanel.orderFrontRegardless()
        }
        guard let start = dragStart else { return }
        dockPanel.setFrameOrigin(NSPoint(x: start.origin.x + mouse.x - start.mouse.x, y: start.origin.y + mouse.y - start.mouse.y))
        // The place nearest the pointer lights up: that's where you're aiming.
        let t = DockPlacement.nearest(to: mouse, in: screen)
        if model.target != t { model.target = t }
    }

    private func dragEnded() {
        guard dragStart != nil else { return }
        let spot = DockPlacement.nearest(to: NSEvent.mouseLocation, in: screen)
        dragStart = nil
        model.dragging = false
        model.target = nil
        zonesPanel.orderOut(nil)
        let target = DockPlacement.canvas(spot, in: screen)
        if spot.vertical == state.config.dockSpot.vertical && spot.align == state.config.dockSpot.align {
            // Same shape and pinning: glide into place.
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.22
                dockPanel.animator().setFrame(target, display: true)
            }
        }
        state.config.dockSpot = spot
        update()
    }

    // MARK: Screenshots

    /// macOS uses one switch for screen sharing and screenshots, so open it briefly for a screenshot.
    func allowScreenshots(for seconds: TimeInterval = 60) {
        let until = Date().addingTimeInterval(seconds)
        state.screenshotsAllowedUntil = until
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds + 0.1) { [weak self] in
            guard let self, self.state.screenshotsAllowedUntil == until else { return }
            self.state.screenshotsAllowedUntil = nil
        }
    }

    /// Test hook output.
    func printStatus() {
        print("dock \(spot.rawValue) visible \(dockPanel.isVisible) bar \(dockRect) list \(listPanel.isVisible ? "\(listPanel.frame)" : "closed") passThrough \(dockPanel.ignoresMouseEvents)")
        fflush(stdout)
    }
}

// MARK: - Dock view

private struct DockSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let n = nextValue()
        value = CGSize(width: max(value.width, n.width), height: max(value.height, n.height))
    }
}

/// One frosted-glass pill per account or client with what's waiting. Hovering a pill reveals its
/// dropdown arrow; clicking the logo or the arrow opens that account's list.
struct DockView: View {
    @ObservedObject var model: DockModel
    @ObservedObject var state = AppState.shared
    var onDragChanged: () -> Void = {}
    var onDragEnded: () -> Void = {}
    var onSize: (CGSize) -> Void = { _ in }
    var previewHover: String? = nil            // screenshots only: draw this pill as hovered
    @Local private var pointer: String? = nil
    private var hovered: String? { pointer ?? previewHover }

    private var spot: DockSpot { state.config.dockSpot }
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    /// Labels only while nothing else is open beside the pills, so they never cover the list.
    private var showsLabels: Bool { !model.dragging && !state.expanded }
    /// On the right edge the arrow sits on the logo's left, into the screen; everywhere else on its right.
    private var arrowLeading: Bool { spot.edge == .right }

    /// Width an arrow adds to its pill.
    static let arrowWidth: CGFloat = 3 + 22

    /// In the bottom-right corner the pills are pinned on their right, so a growing pill would push its
    /// logo left, out from under the pointer. Keeping one arrow's width spare on the right lets it grow
    /// rightwards instead: the hovered logo stays put and only the pills to its right slide over.
    private var rightSlack: CGFloat {
        guard spot == .bottomRight else { return 0 }
        let open = state.expanded ? state.filterOwner : nil
        let arrows = Set([hovered, open].compactMap { $0 }).count
        return arrows == 0 ? Self.arrowWidth : 0
    }

    var body: some View {
        let layout = spot.vertical
            ? AnyLayout(VStackLayout(alignment: spot.edge == .left ? .leading : .trailing, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .bottom, spacing: 8))
        layout {
            ForEach(state.activeOwners, id: \.self) { owner in
                pill(owner)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .fixedSize()
        .padding(.trailing, rightSlack)
        .padding(6)                     // room for the count badges at the screen edge
        .scaleEffect(model.dragging && !reduceMotion ? 1.04 : 1)
        .animation(reduceMotion ? nil : buddySpring, value: state.activeOwners)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.28, dampingFraction: 0.85), value: hovered)
        .animation(.easeOut(duration: 0.15), value: model.dragging)
        .background(GeometryReader { g in Color.clear.preference(key: DockSizeKey.self, value: g.size) })
        .onPreferenceChange(DockSizeKey.self) { onSize($0) }
        .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { _ in onDragChanged() }
            .onEnded { _ in onDragEnded() })
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: spot.alignment)
        .environment(\.colorScheme, .dark)
    }

    private func pill(_ owner: String) -> some View {
        let count = state.items.filter { $0.owner == owner }.count
        let open = state.expanded && state.filterOwner == owner
        let showArrow = hovered == owner || open
        return HStack(spacing: 3) {
            if arrowLeading && showArrow { arrow(open: open, owner: owner) }
            logo(owner, count: count)
            if !arrowLeading && showArrow { arrow(open: open, owner: owner) }
        }
        .padding(4)
        .background(FrostedGlass().clipShape(Capsule()))
        .overlay(Capsule().stroke(Color.white.opacity(open ? 0.6 : 0.22), lineWidth: open ? 1 : 0.5))
        .contentShape(Capsule())
        .overlay(alignment: labelAlignment) {
            if hovered == owner && showsLabels {
                label(Text(state.ownerName(owner)).fontWeight(.semibold) + Text("  \(count) waiting").foregroundColor(.white.opacity(0.65)))
            }
        }
        .onHover { h in pointer = h ? owner : (pointer == owner ? nil : pointer) }
        .onTapGesture { toggle(owner) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(state.ownerName(owner)), \(count) waiting")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { toggle(owner) }
    }

    private func toggle(_ owner: String) {
        if state.expanded && state.filterOwner == owner { state.expanded = false }
        else { state.filterOwner = owner; state.expanded = true }
    }

    private func logo(_ owner: String, count: Int) -> some View {
        OwnerMark(owner: owner, size: item)
            .clipShape(Circle())
            .overlay(alignment: .topTrailing) {
                Text("\(count)")
                    .font(.system(size: 9, weight: .bold)).monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4).frame(minWidth: 15, minHeight: 15)
                    .background(Capsule().fill(Color.red))
                    .offset(x: 5, y: -4)
                    .animation(.snappy, value: count)
            }
    }

    /// The dropdown arrow, pointing to where the list opens; flips while it's open.
    private func arrow(open: Bool, owner: String) -> some View {
        Image(systemName: spot.chevron)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .rotationEffect(.degrees(open ? 180 : 0))
            .frame(width: 22, height: item)
            .transition(.scale(scale: 0.4, anchor: arrowLeading ? .trailing : .leading).combined(with: .opacity))
            .accessibilityHidden(true)
    }

    /// Labels sit beside the pill, into the screen, lined up with its inner side so they stay on screen.
    private var labelAlignment: Alignment {
        switch spot {
        case .bottomLeft: return .bottomLeading
        case .bottomRight: return .bottomTrailing
        case .leftTop, .leftBottom: return .leading
        case .rightTop, .rightBottom: return .trailing
        }
    }

    /// A pill's size with its arrow showing (padding, logo, gap, arrow, padding).
    private var hoveredPill: CGSize { CGSize(width: 4 + item + 3 + 22 + 4, height: 4 + item + 4) }
    private var item: CGFloat { DockPlacement.item(scale: state.config.dockScale) }

    private func label(_ text: Text) -> some View {
        text
            .font(.system(size: 13))
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 12).frame(height: 30)
            .background(Capsule().fill(Color.black))
            .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
            // Hang it off the hovered pill (logo + arrow): above it on the bottom edge, beside it on the sides.
            .offset(x: spot.edge == .left ? hoveredPill.width + 10 : (spot.edge == .right ? -(hoveredPill.width + 10) : 0),
                    y: spot.edge == .bottom ? -(hoveredPill.height + 10) : 0)
            .allowsHitTesting(false)
            .transition(.opacity)
    }
}

/// Dark frosted glass that blurs whatever is behind the bar, even while another app is in front.
struct FrostedGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        v.appearance = NSAppearance(named: .darkAqua)
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

/// An owner's logo: account or client logo, or the bell for your own reminders.
struct OwnerMark: View {
    let owner: String
    var size: CGFloat
    @ObservedObject var state = AppState.shared

    var body: some View {
        if owner == reminderOwner && state.config.reminderLogoPath == nil {
            ZStack {
                Rectangle().fill(Color.teal.gradient)
                Image(systemName: "bell.fill").font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(.white)
            }
            .frame(width: size, height: size)
        } else {
            LogoTile(url: state.ownerLogoURL(owner), name: state.ownerName(owner), tint: ownerColor(owner), size: size)
        }
    }
}

// MARK: - Places shown while dragging

struct DockZonesView: View {
    @ObservedObject var model: DockModel

    var body: some View {
        GeometryReader { g in
            let vf = NSRect(origin: .zero, size: g.size)
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.16)
                ForEach(DockSpot.allCases) { spot in
                    let z = DockPlacement.zone(spot, in: vf)
                    let lit = model.target == spot
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(lit ? 0.9 : 0.45))
                        .frame(width: z.width, height: z.height)
                        .scaleEffect(lit && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1.06 : 1)
                        // AppKit's y runs up, SwiftUI's down.
                        .position(x: z.midX, y: g.size.height - z.midY)
                        .animation(.easeOut(duration: 0.15), value: lit)
                }
            }
        }
        .opacity(model.dragging ? 1 : 0)
        .animation(.easeOut(duration: 0.15), value: model.dragging)
        .ignoresSafeArea()
    }
}

// MARK: - The list

/// Fixed-size card that opens from the chevron (or a logo): newest first, scrolls after about four.
/// Filter by account or client, and by kind (mail, chats, meetings…).
struct DockListView: View {
    @ObservedObject var state = AppState.shared
    @Local private var kind: ItemSource? = nil

    private var byOwner: [BuddyItem] { state.items.filter { state.filterOwner == nil || $0.owner == state.filterOwner } }
    private var items: [BuddyItem] { byOwner.filter { kind == nil || $0.source == kind }.sorted { $0.date > $1.date } }

    var body: some View {
        VStack(spacing: 0) {
            header
            ownerChips
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)
            if items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.circle").font(.system(size: 26)).foregroundStyle(.green)
                    Text(kind == nil ? "All caught up" : "Nothing in \(kind!.pluralName)").font(.headline).foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(items) { DockRow(item: $0) }
                    }
                    .padding(6)
                }
            }
        }
        .frame(width: DockPlacement.listSize.width, height: DockPlacement.listSize.height)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.black))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Notifications").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
            Text("\(items.count)").font(.system(size: 12, weight: .semibold)).monospacedDigit()
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
            if state.undo == nil { kindMenu }
            if let undo = state.undo {
                UndoPill(undo: undo, dark: true)
            } else if !items.isEmpty {
                Button {
                    withAnimation(buddySpring) {
                        if kind == nil { state.clearAll(owner: state.filterOwner) } else { state.done(items.map(\.id)) }
                    }
                } label: {
                    Label("Clear All", systemImage: "checkmark.circle").font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 10).frame(height: 26)
                }
                .buttonStyle(DarkCapsuleStyle()).foregroundStyle(.white)
                .help("Remove these from Desktop Buddy. Nothing changes in your mail or chats.")
            }
        }
        .padding(.horizontal, 14).frame(height: 48)
    }

    /// Kind filter: Mail, Chats, Meetings, Tasks, Reminders (only kinds that are waiting).
    private var kindMenu: some View {
        let kinds = ItemSource.allCases.filter { k in byOwner.contains { $0.source == k } }
        return Menu {
            Button { kind = nil } label: { Label("All kinds", systemImage: kind == nil ? "checkmark" : "") }
            Divider()
            ForEach(kinds, id: \.self) { k in
                Button { kind = k } label: {
                    Label("\(k.pluralName.capitalized) (\(byOwner.filter { $0.source == k }.count))", systemImage: kind == k ? "checkmark" : k.symbol)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: kind == nil ? "line.3.horizontal.decrease" : kind!.symbol).font(.system(size: 11, weight: .bold))
                Text(kind.map { $0.pluralName.capitalized } ?? "All kinds").font(.system(size: 12, weight: .semibold))
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).opacity(0.7)
            }
            .foregroundStyle(kind == nil ? Color.white : Color.black)
            .padding(.horizontal, 10).frame(height: 26)
            .background(Capsule().fill(kind == nil ? Color.white.opacity(0.14) : Color.white))
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Show only mail, chats, meetings…")
        .onChange(of: state.filterOwner) { _, _ in kind = nil }
    }

    /// One chip per account or client with something waiting, plus All.
    private var ownerChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(nil, title: "All", count: state.items.count)
                ForEach(state.activeOwners, id: \.self) { o in
                    chip(o, title: state.ownerName(o), count: state.items.filter { $0.owner == o }.count)
                }
            }
            .padding(.horizontal, 14)
        }
        .frame(height: 36)
        .padding(.bottom, 8)
    }

    private func chip(_ owner: String?, title: String, count: Int) -> some View {
        let on = state.filterOwner == owner
        return Button { withAnimation(.easeOut(duration: 0.15)) { state.filterOwner = owner } } label: {
            HStack(spacing: 5) {
                if let owner { OwnerMark(owner: owner, size: 18).clipShape(Circle()) }
                Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text("\(count)").font(.system(size: 11, weight: .semibold)).monospacedDigit().opacity(0.6)
            }
            .foregroundStyle(on ? Color.black : Color.white)
            .padding(.leading, owner == nil ? 11 : 4).padding(.trailing, 10).frame(height: 28)
        }
        .buttonStyle(DarkCapsuleStyle(fill: on ? 1 : 0.12, hoverFill: on ? 1 : 0.2))
        .accessibilityLabel("\(title), \(count)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

private struct DockRow: View {
    let item: BuddyItem
    @ObservedObject var state = AppState.shared
    @Local private var hover = false
    @FocusState private var focused: Bool
    private var keyFocused: Bool { focused && state.usingKeyboard }

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            CardIcon(item: item, size: 32).padding(.top, 2)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(item.source == .reminder ? item.serviceName : "\(item.serviceName) · \(state.ownerName(item.owner))")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                    Spacer(minLength: 6)
                    if hover || keyFocused {
                        HStack(spacing: 4) {
                            if item.url != nil { small("Open", "arrow.up.forward") { state.open(item) } }
                            small("Done", "checkmark") { withAnimation(buddySpring) { state.done(item.id) } }
                                .help(item.doneHelp)
                        }
                    } else {
                        Text(shortAgo(item.date)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).monospacedDigit()
                    }
                }
                .frame(height: 22)
                Text(item.headline).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                if let sub = item.subhead, !sub.isEmpty {
                    Text(sub).font(.system(size: 13)).foregroundStyle(.white.opacity(0.88)).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let d = item.detail, !d.isEmpty {
                    Text(d).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(hover || keyFocused ? 0.09 : 0))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.7), lineWidth: keyFocused ? 1.5 : 0)))
        .contentShape(Rectangle())
        // Keyboard: Tab to a row, Return opens it, Delete is Done.
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.return) { state.open(item); return .handled }
        .onKeyPress(.delete) { withAnimation(buddySpring) { state.done(item.id) }; return .handled }
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
        .onTapGesture { state.open(item) }
        .contextMenu {
            if item.url != nil { Button("Open in \(item.serviceName)") { state.open(item) } }
            Button("Done") { state.done(item.id) }
            Divider()
            Button("Clear All from \(state.ownerName(item.owner))") { state.clearAll(owner: item.owner) }
        }
        .help(item.detail ?? item.title)
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Open") { state.open(item) }
        .accessibilityAction(named: "Done") { state.done(item.id) }
    }

    private func small(_ title: String, _ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 9, weight: .bold))
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 9).frame(height: 22)
        }
        .buttonStyle(DarkCapsuleStyle(fill: 0.18, hoverFill: 0.26))
        .accessibilityLabel(title)
    }
}
