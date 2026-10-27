import AppKit
import SwiftUI
import Combine

@main
enum Main {
    static func main() {
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            MainActor.assumeIsolated { Snapshot.run(to: CommandLine.arguments[i + 1]) }
            return
        }
        if CommandLine.arguments.contains("--selftest") {
            Task { @MainActor in exit(await SelfTest.run()) }
            dispatchMain()
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)     // menu bar app; becomes a regular app while Settings is open
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private(set) var settingsWindow: NSWindow?
    private var bag = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.mainMenu = Self.makeMainMenu(target: self)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: MenuBarPopover(
            openSettings: { [weak self] in
                self?.popover.performClose(nil)
                self?.openSettings()
            },
            showTour: { [weak self] in
                self?.popover.performClose(nil)
                self?.showTour()
            },
            checkForUpdates: { [weak self] in
                self?.popover.performClose(nil)
                self?.checkForUpdates()
            }))
        popover.delegate = self
        TourController.shared.onClose = { [weak self] addAccount in
            if addAccount || AppState.shared.config.accounts.isEmpty {
                self?.openSettings()
                if addAccount { SettingsRouter.shared.showingProviderPicker = true }
            } else if self?.settingsWindow?.isVisible != true {
                NSApp.setActivationPolicy(.accessory)
            }
        }

        AppState.shared.$items
            .combineLatest(AppState.shared.$config.map(\.paused).removeDuplicates())
            .receive(on: RunLoop.main)
            .sink { [weak self] items, paused in self?.updateIcon(count: items.count, paused: paused) }
            .store(in: &bag)

        _ = OverlayController.shared
        OverlayController.shared.update()
        Poller.shared.start()
        UpdateChecker.shared.start()

        // Test hook: check the feed (DESKTOPBUDDY_UPDATE_FEED) and install straight away.
        if CommandLine.arguments.contains("--install-update") {
            Task { @MainActor in
                await UpdateChecker.shared.check()
                await UpdateChecker.shared.installAndRestart()
                print("Update result: \(UpdateChecker.shared.phase)")
            }
        }
        if CommandLine.arguments.contains("--demo") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { Self.sendTestItems() }
            return
        }
        AppState.shared.purgeDemoItems()
        // First launch: the welcome tour, which ends in Settings to add an account.
        if TourController.shouldShowOnLaunch(AppState.shared.config) {
            showTour()
        } else if AppState.shared.config.accounts.isEmpty {
            SettingsRouter.shared.selection = nil
            openSettings()
        }
    }

    private func updateIcon(count: Int, paused: Bool) {
        guard let button = statusItem.button else { return }
        button.image = MenuBarMark.image(paused: paused)
        let title = MenuBarMark.title(count: count, paused: paused)
        button.attributedTitle = NSAttributedString(string: title.isEmpty ? "" : " " + title, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .semibold),
            .baselineOffset: 0.5,
        ])
        button.imagePosition = .imageLeading
        button.setAccessibilityLabel(paused ? "Desktop Buddy, paused" : "Desktop Buddy, \(count) waiting")
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: AppState.shared.config.paused ? "Resume Notifications" : "Pause Notifications",
                         action: #selector(togglePause), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
            menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Show Tour", action: #selector(showTour), keyEquivalent: "").target = self
            if AppState.shared.config.hidesFromSharing {
                menu.addItem(withTitle: "Allow Screenshots for 1 Minute", action: #selector(allowScreenshots), keyEquivalent: "").target = self
            }
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit Desktop Buddy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
            return
        }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    @objc private func togglePause() { AppState.shared.config.paused.toggle() }

    @objc func allowScreenshots() { OverlayController.shared.allowScreenshots() }

    /// Welcome tour window; the dropdown tips play again the next time it opens.
    @objc func showTour() {
        AppState.shared.replayTour()
        TourController.shared.show()
    }

    func popoverDidClose(_ notification: Notification) {
        // Closing the dropdown mid-tips counts as seen, so they don't come back every time.
        if AppState.shared.coachStep != nil { AppState.shared.finishCoachMarks() }
    }

    /// Checks now and says what it found: a new version (Download / Later), up to date, or offline.
    @objc func checkForUpdates() {
        Task { @MainActor in
            let updates = UpdateChecker.shared
            await updates.check()
            let alert = NSAlert()
            if let r = updates.available {
                alert.messageText = "Desktop Buddy \(r.version) Is Available"
                alert.informativeText = updates.canInstallInPlace
                    ? "You have \(updates.currentVersion). Desktop Buddy downloads it, checks it and restarts. Your accounts and settings stay as they are."
                    : "You have \(updates.currentVersion). Download it, open it and drag Desktop Buddy into Applications. Your accounts and settings stay as they are."
                alert.addButton(withTitle: updates.canInstallInPlace ? "Update and Restart" : "Download")
                alert.addButton(withTitle: "Later")
            } else if let e = updates.lastError {
                alert.messageText = "Couldn't Check for Updates"
                alert.informativeText = e
                alert.addButton(withTitle: "OK")
            } else {
                alert.messageText = "You're Up to Date"
                alert.informativeText = "Desktop Buddy \(updates.currentVersion) is the latest version."
                alert.addButton(withTitle: "OK")
            }
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn, updates.available != nil else { return }
            if updates.canInstallInPlace {
                await updates.installAndRestart()
                if case .failed(let message) = updates.phase {
                    let fail = NSAlert()
                    fail.messageText = "Couldn't Update"
                    fail.informativeText = message
                    fail.addButton(withTitle: "Download Manually")
                    fail.addButton(withTitle: "Cancel")
                    if fail.runModal() == .alertFirstButtonReturn { updates.download() }
                }
            } else {
                updates.download()
            }
        }
    }

    @objc func openSettings() {
        if NSEvent.modifierFlags.contains(.option) { SettingsRouter.shared.adminRequested = true }
        if settingsWindow == nil {
            let w = Self.makeSettingsWindow()
            w.minSize = NSSize(width: 760, height: 540)
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.setFrameAutosaveName("DesktopBuddyV2Settings")
            if w.frame.origin == .zero { w.center() }
            settingsWindow = w
        }
        // Show in the Dock and app switcher while Settings is open, like other menu bar apps.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// System Settings–style window. SwiftUI owns the toolbar and title (scene bridging), so the
    /// sidebar runs full height under the traffic lights with no seam between titlebar and content.
    static func makeSettingsWindow() -> NSWindow {
        let host = NSHostingController(rootView: SettingsRoot())
        host.sceneBridgingOptions = []
        let w = NSWindow(contentViewController: host)
        w.title = "Desktop Buddy"
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true       // content runs to the top edge; no titlebar band or hairline
        w.titleVisibility = .hidden
        w.titlebarSeparatorStyle = .none
        w.isMovableByWindowBackground = true
        w.setContentSize(NSSize(width: 840, height: 620))
        return w
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === settingsWindow else { return }
        SettingsRouter.shared.adminRequested = false
        if SettingsRouter.shared.selection == .team { SettingsRouter.shared.selection = .general }
        NSApp.setActivationPolicy(.accessory)
    }

    /// Google sign-in returns here through the app's own URL scheme (no-secret clients).
    func application(_ application: NSApplication, open urls: [URL]) {
        // Bring the sign-in sheet back in front of the browser once it took the redirect.
        if urls.contains(where: { SchemeReceiver.deliver($0) }) { openSettings() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }

    /// Standard menus so ⌘C/⌘V/⌘W/⌘, work in Settings.
    private static func makeMainMenu(target: AppDelegate) -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let app = NSMenu()
        app.addItem(withTitle: "About Desktop Buddy", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(withTitle: "Check for Updates…", action: #selector(AppDelegate.checkForUpdates), keyEquivalent: "").target = target
        app.addItem(.separator())
        app.addItem(withTitle: "Settings…", action: #selector(AppDelegate.openSettings), keyEquivalent: ",").target = target
        app.addItem(.separator())
        app.addItem(withTitle: "Hide Desktop Buddy", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "Quit Desktop Buddy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = app

        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit

        let windowItem = NSMenuItem(); main.addItem(windowItem)
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = window
        NSApp.windowsMenu = window
        return main
    }

    static func sendTestItems() {
        let now = Date()
        let stamp = Int(now.timeIntervalSince1970)
        let accts = AppState.shared.config.accounts
        let a1 = accts.first, a2 = accts.dropFirst().first ?? accts.first
        AppState.shared.offer([
            BuddyItem(id: "test:mail:\(stamp)", source: .mail, accountID: a1?.id, accountLabel: a1?.label,
                      title: "Sample: Q4 invoice approval", from: "Sample sender",
                      detail: "This is a sample notification so you can preview the design.", date: now, url: nil),
            BuddyItem(id: "test:meet:\(stamp)", source: .meeting, accountID: a2?.id, accountLabel: a2?.label,
                      title: "Sample: Daily stand-up", from: "Sample calendar",
                      detail: "Starts in 5 min", date: now.addingTimeInterval(-1), url: nil),
            BuddyItem(id: "test:reminder:\(stamp)", source: .reminder, accountID: nil, accountLabel: nil,
                      title: "💧 Drink a glass of water", from: nil, detail: "Stay hydrated!",
                      date: now.addingTimeInterval(-2), url: nil),
        ])
    }
}
