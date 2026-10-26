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
