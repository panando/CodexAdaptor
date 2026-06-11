import AppKit
import SwiftUI
import CodexRouterCore
import CodexRouterDB

public class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var appState: AppState?
    private var popover: NSPopover?

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
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let statusItem = statusItem else {
            NSLog("[CodexRouter] Failed to create status item")
            return
        }

        NSLog("[CodexRouter] Status item created successfully")

        // Set the button
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "network", accessibilityDescription: "CodexRouter")
            button.imagePosition = .imageOnly
            button.toolTip = "CodexRouter - Click to manage"
            NSLog("[CodexRouter] Button configured")
        }

        // Create popover for main view
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 320)
        popover.behavior = .transient
        popover.animates = true
        self.popover = popover

        // Create menu for right-click
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

        // Open main window
        let openItem = NSMenuItem(
            title: "Open Dashboard...",
            action: #selector(openDashboard(_:)),
            keyEquivalent: "o"
        )
        openItem.target = self
        menu.addItem(openItem)

        // Codex Integration
        let codexItem = NSMenuItem(
            title: "Codex Integration...",
            action: #selector(openCodexIntegration(_:)),
            keyEquivalent: "c"
        )
        codexItem.target = self
        menu.addItem(codexItem)

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

        // Left click shows popover
        if let button = statusItem.button {
            button.action = #selector(statusBarButtonClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        NSLog("[CodexRouter] Menu set, items count: \(menu.items.count)")
    }

    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        guard let appState = appState else { return }

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 320)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: MainView(appState: appState))

        if let button = statusItem?.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
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

    @objc private func openDashboard(_ sender: NSMenuItem) {
        guard let appState = appState else { return }

        NSApplication.shared.activate(ignoringOtherApps: true)

        if let existingWindow = NSApplication.shared.windows.first(where: { $0.identifier?.rawValue == "dashboard" }) {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 360),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CodexRouter"
        window.identifier = NSUserInterfaceItemIdentifier("dashboard")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: MainView(appState: appState))
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func openCodexIntegration(_ sender: NSMenuItem) {
        guard let appState = appState else { return }

        NSApplication.shared.activate(ignoringOtherApps: true)

        if let existingWindow = NSApplication.shared.windows.first(where: { $0.identifier?.rawValue == "codex" }) {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Codex Integration"
        window.identifier = NSUserInterfaceItemIdentifier("codex")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: CodexIntegrationView(appState: appState))
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func quit(_ sender: NSMenuItem) {
        NSApplication.shared.terminate(nil)
    }
}
