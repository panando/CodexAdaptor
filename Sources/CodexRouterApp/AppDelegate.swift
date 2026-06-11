import AppKit
import SwiftUI

public class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var appState: AppState!

    public func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            appState = try AppState()
        } catch {
            print("Failed to initialize: \(error)")
            NSApplication.shared.terminate(nil)
            return
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "network", accessibilityDescription: "CodexRouter")
        }

        let menuBarView = MenuBarView(appState: appState)
        let hostingView = NSHostingView(rootView: menuBarView)

        let menu = NSMenu()
        let menuItem = NSMenuItem()
        menuItem.view = hostingView
        menu.addItem(menuItem)

        statusItem?.menu = menu

        // Auto-start server
        Task {
            await appState.startServer()
        }
    }
}
