import AppKit
import ApplicationServices
import ServiceManagement

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    private static let enabledKey = "enabled"

    private let controller = CutController()
    private var statusItem: NSStatusItem!
    private var permissionPoller: Timer?

    private let statusMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let enabledMenuItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
    private let loginMenuItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private let permissionMenuItem = NSMenuItem(title: "Grant Accessibility Access…", action: #selector(openAccessibilitySettings), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [Self.enabledKey: true])
        controller.isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        controller.onStateChange = { [weak self] _ in self?.refreshUI() }

        setUpStatusItem()

        if !startIfTrusted(prompt: true) {
            // Wait for the user to flip the switch in System Settings.
            permissionPoller = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                guard let self, self.startIfTrusted(prompt: false) else { return }
                self.permissionPoller?.invalidate()
                self.permissionPoller = nil
            }
        }
        refreshUI()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }

    @discardableResult
    private func startIfTrusted(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options), controller.start() else { return false }
        refreshUI()
        return true
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        let menu = NSMenu()
        menu.delegate = self
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())
        enabledMenuItem.target = self
        menu.addItem(enabledMenuItem)
        loginMenuItem.target = self
        menu.addItem(loginMenuItem)
        permissionMenuItem.target = self
        menu.addItem(permissionMenuItem)
        menu.addItem(.separator())

        let help = NSMenuItem(title: "How to Use", action: #selector(showHelp), keyEquivalent: "")
        help.target = self
        menu.addItem(help)
        menu.addItem(NSMenuItem(title: "Quit FinderCut", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshUI()
    }

    private func refreshUI() {
        guard let button = statusItem?.button else { return }

        let symbol: String
        switch controller.state {
        case .idle: symbol = "scissors"
        case .cutPending: symbol = "scissors.circle.fill"
        }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "FinderCut")
        button.appearsDisabled = !controller.isEnabled || !controller.isRunning

        if !controller.isRunning {
            statusMenuItem.title = "Needs Accessibility access"
        } else if !controller.isEnabled {
            statusMenuItem.title = "Paused"
        } else if case .cutPending(let count) = controller.state {
            statusMenuItem.title = count == 1 ? "1 item ready to move" : "\(count) items ready to move"
        } else {
            statusMenuItem.title = "Ready — ⌘X / ⌘V in Finder"
        }

        enabledMenuItem.state = controller.isEnabled ? .on : .off
        loginMenuItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        permissionMenuItem.isHidden = controller.isRunning
    }

    // MARK: - Actions

    @objc private func toggleEnabled() {
        controller.isEnabled.toggle()
        UserDefaults.standard.set(controller.isEnabled, forKey: Self.enabledKey)
        refreshUI()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.informativeText = "Make sure FinderCut is in /Applications and try again."
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
        refreshUI()
    }

    @objc private func openAccessibilitySettings() {
        startIfTrusted(prompt: true)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func showHelp() {
        let alert = NSAlert()
        alert.messageText = "FinderCut"
        alert.informativeText = """
        Cut and paste files in Finder:

        1. Select files and press ⌘X.
        2. Go to the destination folder and press ⌘V — the files are moved.

        ⌘C, Esc, or copying anything else cancels a pending cut. \
        Renaming files and typing in text fields work as usual.
        """
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
