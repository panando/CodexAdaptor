import SwiftUI
import CodexRouterCore
import CodexRouterDB

/// View for proxy settings.
public struct SettingsView: View {
    @ObservedObject var appState: AppState

    @State private var port: String = "15721"
    @State private var maxRetries: String = "3"
    @State private var failureThreshold: String = "5"
    @State private var successThreshold: String = "3"
    @State private var timeoutSeconds: String = "60"
    @State private var streamingFirstByteTimeout: String = "60"
    @State private var streamingIdleTimeout: String = "120"

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

                Section("Retry") {
                    HStack {
                        Text("Max Retries")
                        Spacer()
                        TextField("", text: $maxRetries)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                    }
                }

                Section("Circuit Breaker") {
                    HStack {
                        Text("Failure Threshold")
                        Spacer()
                        TextField("", text: $failureThreshold)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                    }

                    HStack {
                        Text("Success Threshold")
                        Spacer()
                        TextField("", text: $successThreshold)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                    }

                    HStack {
                        Text("Timeout (seconds)")
                        Spacer()
                        TextField("", text: $timeoutSeconds)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                    }
                }

                Section("Streaming Timeouts") {
                    HStack {
                        Text("First Byte (seconds)")
                        Spacer()
                        TextField("", text: $streamingFirstByteTimeout)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                    }

                    HStack {
                        Text("Idle (seconds)")
                        Spacer()
                        TextField("", text: $streamingIdleTimeout)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            // Footer
            HStack {
                Button("Reset to Defaults") {
                    resetToDefaults()
                }

                Spacer()

                Button("Save") {
                    saveSettings()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 450, height: 500)
        .onAppear {
            loadSettings()
        }
        .alert("Settings Saved", isPresented: $showingSaveConfirmation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Some settings require a server restart to take effect.")
        }
    }

    private func loadSettings() {
        let configDAO = ProxyConfigDAO(appState.database)
        guard let config = try? configDAO.get() else { return }

        port = String(appState.port)
        maxRetries = String(config.maxRetries)
        failureThreshold = String(config.circuitBreaker.failureThreshold)
        successThreshold = String(config.circuitBreaker.successThreshold)
        timeoutSeconds = String(config.circuitBreaker.timeoutSeconds)
        streamingFirstByteTimeout = String(config.streamingFirstByteTimeout)
        streamingIdleTimeout = String(config.streamingIdleTimeout)
    }

    private func saveSettings() {
        let configDAO = ProxyConfigDAO(appState.database)

        let config = ProxyConfig(
            appType: "codex",
            enabled: true,
            autoFailoverEnabled: (try? configDAO.get().autoFailoverEnabled) ?? false,
            maxRetries: UInt(maxRetries) ?? 3,
            streamingFirstByteTimeout: UInt(streamingFirstByteTimeout) ?? 60,
            streamingIdleTimeout: UInt(streamingIdleTimeout) ?? 120,
            circuitBreaker: CircuitBreakerConfig(
                failureThreshold: UInt(failureThreshold) ?? 5,
                successThreshold: UInt(successThreshold) ?? 3,
                timeoutSeconds: UInt(timeoutSeconds) ?? 60
            )
        )

        try? configDAO.save(config)

        // Update port
        if let portValue = Int(port) {
            appState.port = portValue
        }

        showingSaveConfirmation = true
    }

    private func resetToDefaults() {
        port = "15721"
        maxRetries = "3"
        failureThreshold = "5"
        successThreshold = "3"
        timeoutSeconds = "60"
        streamingFirstByteTimeout = "60"
        streamingIdleTimeout = "120"
    }
}
