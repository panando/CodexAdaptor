import AppKit
import SwiftUI
import CodexRouterCore
import CodexRouterDB

public class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var appState: AppState?

    public override init() {
        super.init()
        NSLog("[CodexRouter] AppDelegate init called")
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[CodexRouter] applicationDidFinishLaunching called")

        // Set activation policy for menu bar app
        NSApplication.shared.setActivationPolicy(.accessory)

        do {
            appState = try AppState()
        } catch {
            NSLog("[CodexRouter] Failed to initialize: \(error)")
            NSApplication.shared.terminate(nil)
            return
        }

        setupMenuBar()

        // Auto-start server
        Task { @MainActor in
            await appState?.startServer()
            updateStatusItem()
        }
    }

    private func setupMenuBar() {
        NSLog("[CodexRouter] setupMenuBar called")

        // Create status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        guard let statusItem = statusItem else {
            NSLog("[CodexRouter] Failed to create status item")
            return
        }

        NSLog("[CodexRouter] Status item created successfully")

        // Set the button image
        if let button = statusItem.button {
            // 使用文本而不是图标，更容易看到
            button.title = "CR"
            button.image = nil
            button.toolTip = "CodexRouter - Click to manage"
            NSLog("[CodexRouter] Button configured with text 'CR'")
        } else {
            NSLog("[CodexRouter] No button found!")
        }

        // Create menu
        let menu = NSMenu()

        // Status menu item
        let statusMenuItem = NSMenuItem(title: "Server: Starting...", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        statusMenuItem.tag = 0
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Toggle server
        let toggleMenuItem = NSMenuItem(
            title: "Stop Server",
            action: #selector(toggleServer(_:)),
            keyEquivalent: "s"
        )
        toggleMenuItem.target = self
        toggleMenuItem.tag = 100
        menu.addItem(toggleMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Manage Providers
        let providersMenuItem = NSMenuItem(
            title: "Manage Providers...",
            action: #selector(openProviders(_:)),
            keyEquivalent: "p"
        )
        providersMenuItem.target = self
        menu.addItem(providersMenuItem)

        // Failover Config
        let failoverMenuItem = NSMenuItem(
            title: "Failover Config...",
            action: #selector(openFailover(_:)),
            keyEquivalent: "f"
        )
        failoverMenuItem.target = self
        menu.addItem(failoverMenuItem)

        // Settings
        let settingsMenuItem = NSMenuItem(
            title: "Settings...",
            action: #selector(openSettings(_:)),
            keyEquivalent: ","
        )
        settingsMenuItem.target = self
        menu.addItem(settingsMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitMenuItem = NSMenuItem(
            title: "Quit CodexRouter",
            action: #selector(quit(_:)),
            keyEquivalent: "q"
        )
        quitMenuItem.target = self
        menu.addItem(quitMenuItem)

        statusItem.menu = menu
        NSLog("[CodexRouter] Menu set, items count: \(menu.items.count)")
    }

    @MainActor
    private func updateStatusItem() {
        guard let statusItem = statusItem,
              let menu = statusItem.menu,
              let appState = appState else { return }

        // Update status text
        if let statusItem = menu.item(withTag: 0) {
            statusItem.title = appState.isRunning ? "Server: Running (port \(appState.port))" : "Server: Stopped"
        }

        // Update toggle button text
        if let toggleItem = menu.item(withTag: 100) {
            toggleItem.title = appState.isRunning ? "Stop Server" : "Start Server"
        }
    }

    // MARK: - Actions

    @objc private func toggleServer(_ sender: NSMenuItem) {
        Task { @MainActor in
            if appState?.isRunning == true {
                await appState?.stopServer()
            } else {
                await appState?.startServer()
            }
            updateStatusItem()
        }
    }

    @objc private func openProviders(_ sender: NSMenuItem) {
        guard let appState = appState else { return }
        openWindow(
            id: "providers",
            title: "Providers",
            size: NSSize(width: 500, height: 400),
            view: ProviderListView(appState: appState)
        )
    }

    @objc private func openFailover(_ sender: NSMenuItem) {
        guard let appState = appState else { return }
        openWindow(
            id: "failover",
            title: "Failover Configuration",
            size: NSSize(width: 450, height: 500),
            view: FailoverConfigView(appState: appState)
        )
    }

    @objc private func openSettings(_ sender: NSMenuItem) {
        guard let appState = appState else { return }
        openWindow(
            id: "settings",
            title: "Settings",
            size: NSSize(width: 450, height: 500),
            view: SettingsView(appState: appState)
        )
    }

    @objc private func quit(_ sender: NSMenuItem) {
        NSApplication.shared.terminate(nil)
    }

    private func openWindow(id: String, title: String, size: NSSize, view: some View) {
        NSApplication.shared.activate(ignoringOtherApps: true)

        // Check for existing window
        if let existingWindow = NSApplication.shared.windows.first(where: { $0.identifier?.rawValue == id }) {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        // Create new window
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.identifier = NSUserInterfaceItemIdentifier(id)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}
