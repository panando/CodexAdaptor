import SwiftUI

public struct MenuBarView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 200)
    }
}
