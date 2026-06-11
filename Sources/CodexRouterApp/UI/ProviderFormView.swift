import SwiftUI
import CodexRouterCore
import CodexRouterDB

/// View for adding or editing a provider.
public struct ProviderFormView: View {
    @ObservedObject var appState: AppState
    let provider: Provider?

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var baseURL: String = ""
    @State private var apiKey: String = ""
    @State private var apiFormat: String = "chat"
    @State private var customUserAgent: String = ""

    @State private var showingError = false
    @State private var errorMessage = ""

    private var isEditing: Bool {
        provider != nil
    }

    public init(appState: AppState, provider: Provider?) {
        self.appState = appState
        self.provider = provider
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isEditing ? "Edit Provider" : "Add Provider")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
            }
            .padding()

            Divider()

            // Form
            Form {
                Section("Basic") {
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)

                    TextField("Base URL", text: $baseURL)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()

                    SecureField("API Key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                }

                Section("Advanced") {
                    Picker("API Format", selection: $apiFormat) {
                        Text("Chat Completions").tag("chat")
                        Text("Responses API").tag("responses")
                    }

                    TextField("Custom User Agent (optional)", text: $customUserAgent)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                }
            }
            .formStyle(.grouped)

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Save") {
                    saveProvider()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || baseURL.isEmpty)
            }
            .padding()
        }
        .frame(width: 450, height: 400)
        .onAppear {
            loadProviderData()
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func loadProviderData() {
        guard let provider = provider else { return }

        name = provider.name
        baseURL = provider.baseURL ?? ""
        apiFormat = provider.meta?.apiFormat ?? "chat"
        customUserAgent = provider.meta?.customUserAgent ?? ""

        // Load API key from keychain
        if let key = try? KeychainService.shared.getAPIKey(for: provider.id) {
            apiKey = key
        }
    }

    private func saveProvider() {
        let id = provider?.id ?? UUID().uuidString

        // Build settings config
        var settingsConfig: [String: AnyCodable] = [:]
        settingsConfig["base_url"] = AnyCodable(baseURL)

        // Build meta
        let meta = ProviderMeta(
            apiFormat: apiFormat,
            customUserAgent: customUserAgent.isEmpty ? nil : customUserAgent
        )

        let newProvider = Provider(
            id: id,
            name: name,
            settingsConfig: settingsConfig,
            meta: meta
        )

        do {
            // Save provider
            let dao = ProviderDAO(appState.database)
            try dao.save(newProvider)

            // Save API key to keychain
            if !apiKey.isEmpty {
                try KeychainService.shared.storeAPIKey(apiKey, for: id)
            }

            appState.loadProviders()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}
