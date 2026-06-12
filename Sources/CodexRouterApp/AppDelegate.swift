import AppKit
import SwiftUI
import CodexRouterCore

public class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var appState: AppState?
    private var locObserver: NSObjectProtocol?

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        appState = AppState()

        setupMenuBar()
        observeLocalization()

        Task { @MainActor in
            await appState?.startServer()
            updateMenu()
        }
    }

    private func observeLocalization() {
        locObserver = NotificationCenter.default.addObserver(
            forName: .LocalizationServiceDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.rebuildMenu()
        }
    }

    private func rebuildMenu() {
        guard let statusItem = statusItem else { return }
        let menu = buildMenu()
        statusItem.menu = menu
        Task { @MainActor in updateMenu() }
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let statusItem = statusItem else { return }

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "network", accessibilityDescription: "CodexAdaptor")
            button.toolTip = "CodexAdaptor"
        }

        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let statusMenuItem = NSMenuItem(title: L10n.serverStarting, action: nil, keyEquivalent: "")
        statusMenuItem.tag = 1
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())

        let toggleItem = NSMenuItem(title: L10n.stopServer, action: #selector(toggleServer), keyEquivalent: "s")
        toggleItem.tag = 2
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        let configureItem = NSMenuItem(title: L10n.configure, action: #selector(openConfigure), keyEquivalent: ",")
        configureItem.target = self
        menu.addItem(configureItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: L10n.quit, action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @MainActor
    private func updateMenu() {
        guard let menu = statusItem?.menu, let appState = appState else { return }

        if let statusItem = menu.item(withTag: 1) {
            if appState.isRunning {
                statusItem.title = "\(L10n.serverRunning) \(String(appState.port)))"
            } else {
                statusItem.title = L10n.serverStopped
            }
        }

        if let toggleItem = menu.item(withTag: 2) {
            toggleItem.title = appState.isRunning ? L10n.stopServer : L10n.startServer
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

    @objc func openConfigure() {
        guard let appState = appState else { return }
        openWindow(id: "configure", title: "CodexAdaptor", size: NSSize(width: 780, height: 560)) {
            ConfigurationView(appState: appState)
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
