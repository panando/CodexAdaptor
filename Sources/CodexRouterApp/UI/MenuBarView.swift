import SwiftUI

public struct MenuBarView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Status
            HStack {
                Circle()
                    .fill(appState.isRunning ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(appState.isRunning ? "Running" : "Stopped")
            }

            if appState.isRunning {
                Text("Port: \(appState.port)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let provider = appState.currentProvider {
                    Text("Provider: \(provider)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Server control
            Button(appState.isRunning ? "Stop Server" : "Start Server") {
                Task {
                    if appState.isRunning {
                        await appState.stopServer()
                    } else {
                        await appState.startServer()
                    }
                }
            }

            Divider()

            // Configuration windows
            Button("Manage Providers...") {
                openProviderWindow()
            }

            Button("Failover Config...") {
                openFailoverWindow()
            }

            Button("Settings...") {
                openSettingsWindow()
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 200)
    }

    private func openProviderWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)

        if let existingWindow = NSApplication.shared.windows.first(where: {
            $0.identifier?.rawValue == "providers-window"
        }) {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Providers"
        window.identifier = NSUserInterfaceItemIdentifier("providers-window")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ProvidersView(appState: appState))
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func openFailoverWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)

        if let existingWindow = NSApplication.shared.windows.first(where: {
            $0.identifier?.rawValue == "failover-window"
        }) {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Failover Configuration"
        window.identifier = NSUserInterfaceItemIdentifier("failover-window")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: FailoverConfigView(appState: appState))
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func openSettingsWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)

        if let existingWindow = NSApplication.shared.windows.first(where: {
            $0.identifier?.rawValue == "settings-window"
        }) {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.identifier = NSUserInterfaceItemIdentifier("settings-window")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView(appState: appState))
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}
