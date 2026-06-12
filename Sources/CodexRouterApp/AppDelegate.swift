import AppKit
import SwiftUI
import CodexRouterCore

public class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var appState: AppState?

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Set activation policy for menu bar app
        NSApplication.shared.setActivationPolicy(.accessory)

        appState = AppState()

        setupMenuBar()

        // Auto-start server
        Task { @MainActor in
            await appState?.startServer()
            updateMenu()
        }
    }

    private func setupMenuBar() {
        // Create status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let statusItem = statusItem else { return }

        // Set the button
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "network", accessibilityDescription: "CodexRouter")
            button.toolTip = "CodexRouter"
        }

        // Create menu
        let menu = NSMenu()

        // Status
        let statusMenuItem = NSMenuItem(title: "Server: Starting...", action: nil, keyEquivalent: "")
        statusMenuItem.tag = 1
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Toggle server
        let toggleItem = NSMenuItem(title: "Stop Server", action: #selector(toggleServer), keyEquivalent: "s")
        toggleItem.tag = 2
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        // Dashboard
        let dashboardItem = NSMenuItem(title: "Dashboard...", action: #selector(openDashboard), keyEquivalent: "d")
        dashboardItem.target = self
        menu.addItem(dashboardItem)

        // Providers
        let providersItem = NSMenuItem(title: "Providers...", action: #selector(openProviders), keyEquivalent: "p")
        providersItem.target = self
        menu.addItem(providersItem)

        // Failover
        let failoverItem = NSMenuItem(title: "Failover Config...", action: #selector(openFailover), keyEquivalent: "f")
        failoverItem.target = self
        menu.addItem(failoverItem)

        // Settings
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        // Logs
        let logsItem = NSMenuItem(title: "View Logs...", action: #selector(openLogs), keyEquivalent: "l")
        logsItem.target = self
        menu.addItem(logsItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit CodexRouter", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @MainActor
    private func updateMenu() {
        guard let menu = statusItem?.menu, let appState = appState else { return }

        if let statusItem = menu.item(withTag: 1) {
            statusItem.title = appState.isRunning ? "Server: Running (port \(appState.port))" : "Server: Stopped"
        }

        if let toggleItem = menu.item(withTag: 2) {
            toggleItem.title = appState.isRunning ? "Stop Server" : "Start Server"
        }
    }

    // MARK: - Actions

    @objc func toggleServer() {
        Task { @MainActor in
            if appState?.isRunning == true {
                await appState?.stopServer()
            } else {
                await appState?.startServer()
            }
            updateMenu()
        }
    }

    @objc func openDashboard() {
        guard let appState = appState else { return }
        openWindow(id: "dashboard", title: "CodexRouter", size: NSSize(width: 300, height: 380)) {
            MainView(appState: appState)
        }
    }

    @objc func openProviders() {
        guard let appState = appState else { return }
        openWindow(id: "providers", title: "Providers", size: NSSize(width: 500, height: 400)) {
            ProvidersView(appState: appState)
        }
    }

    @objc func openFailover() {
        guard let appState = appState else { return }
        openWindow(id: "failover", title: "Failover Configuration", size: NSSize(width: 450, height: 500)) {
            FailoverConfigView(appState: appState)
        }
    }

    @objc func openSettings() {
        guard let appState = appState else { return }
        openWindow(id: "settings", title: "Settings", size: NSSize(width: 450, height: 500)) {
            SettingsView(appState: appState)
        }
    }

    @objc func openLogs() {
        openWindow(id: "logs", title: "Logs", size: NSSize(width: 600, height: 400)) {
            LogViewerView()
        }
    }

    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func openWindow(id: String, title: String, size: NSSize, content: @escaping () -> some View) {
        NSApplication.shared.activate(ignoringOtherApps: true)

        if let existingWindow = NSApplication.shared.windows.first(where: { $0.identifier?.rawValue == id }) {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.identifier = NSUserInterfaceItemIdentifier(id)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content())
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}
