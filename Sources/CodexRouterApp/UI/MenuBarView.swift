import SwiftUI

public struct MenuBarView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var loc = LocalizationService.shared

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(appState.isRunning ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(appState.isRunning ? L10n.running : L10n.stopped)
            }

            if appState.isRunning {
                Text("Port: \(appState.port)")
                    .font(.caption).foregroundColor(.secondary)
                if let provider = appState.currentProvider {
                    Text("Provider: \(provider)")
                        .font(.caption).foregroundColor(.secondary)
                }
            }

            Divider()

            Button(appState.isRunning ? L10n.stopServer : L10n.startServer) {
                Task {
                    if appState.isRunning { await appState.stopServer() }
                    else { await appState.startServer() }
                }
            }

            Divider()

            Button(L10n.configure) { openWindow(id: "configure", title: "CodexAdaptor", width: 780, height: 560) {
                ConfigurationView(appState: appState)
            }}

            Divider()

            Button(L10n.quitShort) { NSApplication.shared.terminate(nil) }
        }
        .padding(12).frame(width: 200)
    }

    private func openWindow(id: String, title: String, width: CGFloat, height: CGFloat, content: () -> some View) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let w = NSApplication.shared.windows.first(where: { $0.identifier?.rawValue == id }) {
            w.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false
        )
        window.title = title
        window.identifier = NSUserInterfaceItemIdentifier(id)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content())
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}
