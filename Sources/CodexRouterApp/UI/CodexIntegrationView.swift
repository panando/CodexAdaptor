import SwiftUI
import CodexRouterCore
import CodexRouterDB

/// View for Codex integration settings.
public struct CodexIntegrationView: View {
    @ObservedObject var appState: AppState
    @State private var codexConfig: CodexProviderConfig?
    @State private var isLoading = false
    @State private var showingSuccess = false
    @State private var showingError = false
    @State private var errorMessage = ""

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "app.badge.checkmark")
                    .font(.title2)
                    .foregroundColor(.blue)
                Text("Codex Integration")
                    .font(.headline)
            }

            Divider()

            if isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity)
            } else if let config = codexConfig {
                // Current status
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Current Provider:")
                            .foregroundColor(.secondary)
                        Text(config.name)
                            .fontWeight(.medium)
                    }

                    HStack {
                        Text("Base URL:")
                            .foregroundColor(.secondary)
                        Text(config.baseURL)
                            .font(.system(.body, design: .monospaced))
                    }

                    HStack {
                        Text("Status:")
                            .foregroundColor(.secondary)

                        if config.isUsingProxy {
                            Label("Using Proxy", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Label("Direct Connection", systemImage: "arrow.forward")
                                .foregroundColor(.orange)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)

                // Actions
                VStack(spacing: 8) {
                    if config.isUsingProxy {
                        Button("Restore Original Config") {
                            restoreConfig()
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Button("Configure Codex to Use Proxy") {
                            configureProxy()
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                    }

                    Text("This will modify ~/.codex/config.toml to route requests through CodexRouter")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)

                    Text("Codex config not found")
                        .font(.headline)

                    Text("Make sure Codex is installed and configured")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
            }

            Spacer()
        }
        .padding()
        .frame(width: 400, height: 300)
        .onAppear {
            loadConfig()
        }
        .alert("Success", isPresented: $showingSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Codex configuration updated successfully. Restart Codex for changes to take effect.")
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func loadConfig() {
        isLoading = true
        defer { isLoading = false }

        do {
            codexConfig = try CodexConfigService.shared.getCurrentConfig()
        } catch {
            codexConfig = nil
        }
    }

    private func configureProxy() {
        isLoading = true
        defer { isLoading = false }

        do {
            try CodexConfigService.shared.setProxyURL("http://127.0.0.1:15721")
            loadConfig()
            showingSuccess = true
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func restoreConfig() {
        isLoading = true
        defer { isLoading = false }

        do {
            try CodexConfigService.shared.restoreOriginalConfig()
            loadConfig()
            showingSuccess = true
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}
