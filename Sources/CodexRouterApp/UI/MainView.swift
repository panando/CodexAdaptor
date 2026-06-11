import SwiftUI
import CodexRouterCore
import CodexRouterDB

/// Main window view showing server status and quick actions.
public struct MainView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Server Status Section
            VStack(spacing: 8) {
                HStack {
                    Circle()
                        .fill(appState.isRunning ? Color.green : Color.red)
                        .frame(width: 12, height: 12)
                    Text(appState.isRunning ? "Server Running" : "Server Stopped")
                        .font(.headline)
                }

                if appState.isRunning {
                    VStack(spacing: 4) {
                        Text("Proxy: http://127.0.0.1:\(appState.port)")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)

                        if let provider = appState.currentProvider {
                            HStack(spacing: 4) {
                                Text("Provider:")
                                    .foregroundColor(.secondary)
                                Text(provider)
                                    .fontWeight(.medium)
                            }
                            .font(.caption)
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)

            // Quick Actions
            VStack(spacing: 8) {
                Button(action: {
                    Task {
                        if appState.isRunning {
                            await appState.stopServer()
                        } else {
                            await appState.startServer()
                        }
                    }
                }) {
                    HStack {
                        Image(systemName: appState.isRunning ? "stop.fill" : "play.fill")
                        Text(appState.isRunning ? "Stop Server" : "Start Server")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                HStack(spacing: 12) {
                    Button("Providers") {
                        openWindow(id: "providers", title: "Providers", size: NSSize(width: 500, height: 400)) {
                            ProviderListView(appState: appState)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Button("Failover") {
                        openWindow(id: "failover", title: "Failover", size: NSSize(width: 450, height: 500)) {
                            FailoverConfigView(appState: appState)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                HStack(spacing: 12) {
                    Button("Settings") {
                        openWindow(id: "settings", title: "Settings", size: NSSize(width: 450, height: 500)) {
                            SettingsView(appState: appState)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Button("Logs") {
                        openWindow(id: "logs", title: "Logs", size: NSSize(width: 600, height: 400)) {
                            LogViewerView()
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            Divider()

            // Provider count
            HStack {
                Text("\(appState.providers.count) provider\(appState.providers.count == 1 ? "" : "s") configured")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("v1.0.0")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .frame(width: 280)
    }

    private func openWindow(id: String, title: String, size: NSSize, content: () -> some View) {
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
