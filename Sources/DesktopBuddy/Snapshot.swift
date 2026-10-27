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
        }
        render(AddAccountSheet(provider: .microsoft).background(Color(nsColor: .windowBackgroundColor)),
               size: NSSize(width: 520, height: 520), to: out.appendingPathComponent("add-account.png"))
        AppState.shared.expanded = true
        AppState.shared.filterOwner = nil
        render(OverlayView().background(Color(red: 0.35, green: 0.5, blue: 0.65)),
               size: NSSize(width: 420, height: 720), to: out.appendingPathComponent("overlay-list.png"))
        AppState.shared.filterOwner = AppState.shared.activeOwners.first
        render(OverlayView().background(Color(red: 0.35, green: 0.5, blue: 0.65)),
               size: NSSize(width: 420, height: 720), to: out.appendingPathComponent("overlay-list-filtered.png"))
        AppState.shared.expanded = false
        AppState.shared.filterOwner = nil
        for (name, look) in [("overlay-row-dark", NSAppearance.Name.darkAqua), ("overlay-row-light", .aqua)] {
            NSApp.appearance = NSAppearance(named: look)
            let wall = look == .darkAqua ? Color(white: 0.11) : Color(red: 0.86, green: 0.9, blue: 0.95)
            render(OverlayView().background(wall), size: NSSize(width: 560, height: 150),
                   to: out.appendingPathComponent("\(name).png"))
        }
        NSApp.appearance = nil
        render(MenuBarPopover(openSettings: {}).background(Color(nsColor: .windowBackgroundColor)),
               size: NSSize(width: 360, height: 520), to: out.appendingPathComponent("popover.png"))
        for (name, look) in [("popover-dark", NSAppearance.Name.darkAqua), ("popover-light", .aqua)] {
            NSApp.appearance = NSAppearance(named: look)
            render(MenuBarPopover(openSettings: {}).background(Color(nsColor: .windowBackgroundColor)),
                   size: NSSize(width: 360, height: 560), to: out.appendingPathComponent("\(name).png"))
        }
        NSApp.appearance = nil
        // Dropdown tips, one picture per step.
        for step in CoachStep.steps(hasAccounts: !AppState.shared.config.accounts.isEmpty) {
            AppState.shared.coachStep = step
            render(MenuBarPopover(openSettings: {}).background(Color(nsColor: .windowBackgroundColor)),
                   size: NSSize(width: 360, height: 560), to: out.appendingPathComponent("popover-tip-\(step.rawValue + 1).png"))
        }
        AppState.shared.coachStep = nil
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
