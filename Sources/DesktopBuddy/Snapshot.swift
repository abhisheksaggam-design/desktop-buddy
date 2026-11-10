import SwiftUI
import AppKit

/// `DesktopBuddy --snapshot <dir>` renders the main screens to PNGs
/// (for docs and design review) and exits. Uses real AppKit windows rendered offscreen.
@MainActor
enum Snapshot {
    static func run(to dir: String) {
        Keychain.disabled = true
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let out = URL(fileURLWithPath: dir)
        // Docs show accounts as connected (the Keychain is off in this mode).
        AppState.shared.signedIn = Set(AppState.shared.config.accounts.map(\.id))

        let router = SettingsRouter.shared
        let firstAccount = AppState.shared.config.accounts.first?.id
        let panes: [(String, SettingsPane?)] = [
            ("settings-account", firstAccount.map { .account($0) }),
            ("settings-general", .general),
            ("settings-client", AppState.shared.config.clients.first.map { .client($0.id) }),
            ("settings-client-last", AppState.shared.config.clients.last.map { .client($0.id) }),
            ("settings-appearance", .appearance),
            ("settings-reminders", .reminders),
            ("settings-team", .team),
        ]
        for (name, pane) in panes {
            router.selection = pane
            renderWindow(AppDelegate.makeSettingsWindow(), to: out.appendingPathComponent("\(name).png"))
        }
        if let a = AppState.shared.config.accounts.first {
            let account = Binding(get: { AppState.shared.account(a.id) ?? a }, set: { AppState.shared.update($0) })
            render(Form { MailFilterSections(account: account) }.formStyle(.grouped)
                    .background(Color(nsColor: .windowBackgroundColor)),
                   size: NSSize(width: 580, height: 620), to: out.appendingPathComponent("settings-account-mail.png"))
            var muted = AppState.shared.account(a.id) ?? a
            muted.mutedChats = [ChatRef(accountID: a.id, chatID: "spaces/A", name: "All hands", kind: .space),
                                ChatRef(accountID: a.id, chatID: "spaces/B", name: "Social", kind: .space),
                                ChatRef(accountID: a.id, chatID: "spaces/C", name: "Sam Patel", kind: .direct)]
            muted.mutedSenders = ["news.example.com"]
            muted.mutedKeywords = ["standup", "newsletter"]
            AppState.shared.update(muted)
            render(Form { MuteSection(account: account) }.formStyle(.grouped)
                    .background(Color(nsColor: .windowBackgroundColor)),
                   size: NSSize(width: 580, height: 520), to: out.appendingPathComponent("settings-account-mute.png"))
        }
        render(AddAccountSheet(provider: .microsoft).background(Color(nsColor: .windowBackgroundColor)),
               size: NSSize(width: 520, height: 520), to: out.appendingPathComponent("add-account.png"))
        // On-screen dock: along the bottom and on a side, its list, and the places shown while dragging.
        let wall = LinearGradient(colors: [Color(red: 0.55, green: 0.68, blue: 0.85), Color(red: 0.85, green: 0.78, blue: 0.9)],
                                  startPoint: .top, endPoint: .bottom)
        let dockModel = DockModel()
        let accts = AppState.shared.config.accounts
        let a1 = accts.first?.id, a2 = accts.dropFirst().first?.id ?? accts.first?.id
        let now = Date()
        _ = AppState.shared.offer([
            BuddyItem(id: "s1", source: .mail, accountID: a1, title: "Contract ready to sign", from: "Jane Cooper",
                      detail: "Hi, the final version is attached. Could you sign by Friday?", date: now, url: URL(string: "https://example.com")),
            BuddyItem(id: "s2", source: .chat, accountID: a2, title: "Project Apollo", from: "Priya Shah",
                      detail: "Can you review the new pricing page before the 3pm call?", date: now - 120, url: nil),
            BuddyItem(id: "s3", source: .meeting, accountID: a1, title: "Design review", from: "Calendar",
                      detail: "Starts in 5 min · Google Meet", date: now - 300, url: nil),
            BuddyItem(id: "s4", source: .reminder, accountID: nil, title: "💧 Drink a glass of water", detail: "Stay hydrated!", date: now - 600, url: nil),
            BuddyItem(id: "s5", source: .mail, accountID: a2, title: "Invoice #4821", from: "Accounts team",
                      detail: "Please find this month's invoice attached.", date: now - 900, url: nil),
            BuddyItem(id: "s6", source: .task, accountID: a1, title: "Send onboarding copy to Sam", from: "My tasks",
                      detail: "Due today", date: now - 1800, url: nil),
        ])
        let saved = AppState.shared.config.dockSpot
        for spot in [DockSpot.bottomRight, .rightBottom] {
            AppState.shared.config.dockSpot = spot
            render(DockView(model: dockModel).background(wall), size: DockPlacement.canvasSize(vertical: spot.vertical),
                   to: out.appendingPathComponent("dock-\(spot.rawValue).png"))
            render(DockView(model: dockModel, previewHover: AppState.shared.activeOwners.dropFirst().first).background(wall),
                   size: DockPlacement.canvasSize(vertical: spot.vertical), to: out.appendingPathComponent("dock-\(spot.rawValue)-hover.png"))
        }
        AppState.shared.config.dockSpot = saved
        AppState.shared.filterOwner = nil
        render(DockListView().padding(20).background(wall), size: NSSize(width: DockPlacement.listSize.width + 40, height: DockPlacement.listSize.height + 40),
               to: out.appendingPathComponent("dock-list.png"))
        dockModel.dragging = true
        dockModel.target = .bottomRight
        render(DockZonesView(model: dockModel).background(wall), size: NSSize(width: 1440, height: 860),
               to: out.appendingPathComponent("dock-places.png"))
        render(MenuBarPopover(openSettings: {}).background(Color(nsColor: .windowBackgroundColor)),
               size: NSSize(width: 360, height: 620), to: out.appendingPathComponent("popover-rows.png"))
        AppState.shared.clearAll()
        render(DockListView().padding(20).background(wall), size: NSSize(width: DockPlacement.listSize.width + 40, height: 160),
               to: out.appendingPathComponent("dock-list-undo.png"))
        render(MenuBarPopover(openSettings: {}).background(Color(nsColor: .windowBackgroundColor)),
               size: NSSize(width: 360, height: 400), to: out.appendingPathComponent("popover-undo.png"))
        AppState.shared.undoLast(); AppState.shared.clearAll()
        render(FeedbackView(close: {}).background(Color(nsColor: .windowBackgroundColor)),
               size: NSSize(width: 460, height: 560), to: out.appendingPathComponent("report-bug.png"))
        render(FeedbackView(showingSent: true, close: {}).background(Color(nsColor: .windowBackgroundColor)),
               size: NSSize(width: 460, height: 300), to: out.appendingPathComponent("report-bug-sent.png"))
        render(MenuBarPopover(openSettings: {}).background(Color(nsColor: .windowBackgroundColor)),
               size: NSSize(width: 360, height: 520), to: out.appendingPathComponent("popover.png"))
        for (name, look) in [("popover-dark", NSAppearance.Name.darkAqua), ("popover-light", .aqua)] {
            NSApp.appearance = NSAppearance(named: look)
            render(MenuBarPopover(openSettings: {}).background(Color(nsColor: .windowBackgroundColor)),
                   size: NSSize(width: 360, height: 560), to: out.appendingPathComponent("\(name).png"))
        }
        NSApp.appearance = nil
        // Menu bar pop-up: closed pill, open, open with the pointer over it.
        let noActions = GlimpseActions(open: {}, done: {}, close: {}, viewMore: {})
        for (name, phase, hover) in [("glimpse-pill", GlimpsePhase.pill, false), ("glimpse-open", .open, false), ("glimpse-hover", .open, true)] {
            let m = GlimpseModel.sample
            m.phase = phase; m.hovering = hover
            render(GlimpseView(model: m, actions: noActions)
                    .background(LinearGradient(colors: [Color(red: 0.55, green: 0.68, blue: 0.85), Color(red: 0.85, green: 0.78, blue: 0.9)],
                                               startPoint: .top, endPoint: .bottom)),
                   size: GlimpsePlacement.canvas, to: out.appendingPathComponent("\(name).png"))
        }
        let short = GlimpseModel.sample
        short.item = BuddyItem(id: "sample:reminder", source: .reminder, accountID: nil, title: "💧 Drink a glass of water",
                               detail: "Stay hydrated!", date: Date(), url: nil)
        short.more = 0
        render(GlimpseView(model: short, actions: noActions)
                .background(LinearGradient(colors: [Color(red: 0.55, green: 0.68, blue: 0.85), Color(red: 0.85, green: 0.78, blue: 0.9)],
                                           startPoint: .top, endPoint: .bottom)),
               size: GlimpsePlacement.canvas, to: out.appendingPathComponent("glimpse-short.png"))
        for page in TourPage.allCases {
            render(TourView(start: page, finish: { _ in }), size: NSSize(width: 560, height: 470),
                   to: out.appendingPathComponent("tour-\(page.rawValue + 1).png"))
        }
        for (name, look) in [("menubar-dark", NSAppearance.Name.darkAqua), ("menubar-light", .aqua)] {
            NSApp.appearance = NSAppearance(named: look)
            let bar = HStack(spacing: 24) {
                ForEach(0..<3, id: \.self) { i in let (count, paused) = [(0, false), (3, false), (0, true)][i]
                    HStack(spacing: 3) {
                        Image(nsImage: MenuBarMark.image(paused: paused)).renderingMode(.template)
                        let t = MenuBarMark.title(count: count, paused: paused)
                        if !t.isEmpty { Text(t).font(.system(size: 13, weight: .semibold)).monospacedDigit() }
                    }
                }
            }
            .foregroundStyle(.primary).padding(.horizontal, 20)
            .frame(width: 220, height: 30).background(.bar)
            render(bar.scaleEffect(3).frame(width: 660, height: 90), size: NSSize(width: 660, height: 90),
                   to: out.appendingPathComponent("\(name).png"))
        }
        NSApp.appearance = nil
    }

    private static func render<V: View>(_ view: V, size: NSSize, to url: URL) {
        let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: size.width, height: size.height),
                              styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.contentViewController = NSHostingController(rootView: view)
        window.setContentSize(size)
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(1.2))     // let SwiftUI lay out and settle
        guard let content = window.contentView,
              let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return }
        content.cacheDisplay(in: content.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: url) }
        window.orderOut(nil)
    }

    /// Renders a real window including its titlebar/toolbar (the theme frame).
    private static func renderWindow(_ window: NSWindow, to url: URL) {
        window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        guard let frame = window.contentView?.superview,
              let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { return }
        frame.cacheDisplay(in: frame.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: url) }
        window.orderOut(nil)
    }

    private static func write(_ img: NSImage, _ url: URL) {
        if let tiff = img.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
        }
    }
}
