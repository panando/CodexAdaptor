import SwiftUI
import CodexRouterCore

/// View for proxy settings.
public struct SettingsView: View {
    @ObservedObject var appState: AppState

    @State private var port: String = "15721"
    @State private var showingSaveConfirmation = false

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.headline)
            }
            .padding()

            Divider()

            // Form
            Form {
                Section("Server") {
                    HStack {
                        Text("Port")
                        Spacer()
                        TextField("", text: $port)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                    }
                }

                Section {
                    Text("Provider configuration is managed via ~/.codex/config.toml")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Note")
                }
            }
            .formStyle(.grouped)

            Divider()

            // Footer
            HStack {
                Spacer()

                Button("Save") {
                    saveSettings()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 450, height: 300)
        .onAppear {
            port = String(appState.port)
        }
        .alert("Settings Saved", isPresented: $showingSaveConfirmation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Port change requires a server restart to take effect.")
        }
    }

    private func saveSettings() {
        if let portValue = Int(port) {
            appState.port = portValue
        }
        showingSaveConfirmation = true
    }
}
