import SwiftUI
import CodexRouterCore

/// View for managing model providers.
public struct ProvidersView: View {
    @ObservedObject var appState: AppState
    @State private var providers: [CodexModelProvider] = []
    @State private var currentProviderId: String?
    @State private var currentModel: String?
    @State private var isLoading = true
    @State private var showingAddProvider = false
    @State private var providerToEdit: CodexModelProvider?
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingSuccess = false
    @State private var successMessage = ""

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "server.rack")
                    .font(.title2)
                    .foregroundColor(.blue)
                Text("Providers")
                    .font(.headline)
                Spacer()
                Button(action: { loadConfig() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
            }
            .padding()

            Divider()

            if isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if providers.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No providers configured")
                        .foregroundColor(.secondary)
                    Button("Add Provider") {
                        showingAddProvider = true
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Current provider info
                if let currentId = currentProviderId,
                   let current = providers.first(where: { $0.id == currentId }) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Current Provider")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text(current.name)
                                .fontWeight(.medium)
                            Spacer()
                            if let model = currentModel {
                                Text("Model: \(model)")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .padding([.horizontal, .top])
                }

                // Provider list
                List {
                    ForEach(providers) { provider in
                        ProviderRowView(
                            provider: provider,
                            isCurrent: provider.id == currentProviderId,
                            onSelect: {
                                switchToProvider(provider)
                            },
                            onEdit: {
                                providerToEdit = provider
                            },
                            onDelete: {
                                deleteProvider(provider)
                            }
                        )
                    }
                }
            }

            Divider()

            // Footer
            HStack {
                Button("Add Provider") {
                    showingAddProvider = true
                }
                Spacer()
                Button("Done") {
                    NSApplication.shared.keyWindow?.close()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 500, height: 450)
        .onAppear {
            loadConfig()
        }
        .sheet(isPresented: $showingAddProvider) {
            ProviderFormView(
                appState: appState,
                provider: nil,
                onSave: { provider in
                    saveProvider(provider)
                }
            )
        }
        .sheet(item: $providerToEdit) { provider in
            ProviderFormView(
                appState: appState,
                provider: provider,
                onSave: { updatedProvider in
                    saveProvider(updatedProvider)
                }
            )
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .alert("Success", isPresented: $showingSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(successMessage)
        }
    }

    private func loadConfig() {
        isLoading = true
        defer { isLoading = false }

        do {
            providers = try CodexConfigService.shared.getModelProviders()
            if let current = try CodexConfigService.shared.getCurrentProvider() {
                currentProviderId = current.id
            }
            currentModel = try CodexConfigService.shared.getCurrentModel()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func switchToProvider(_ provider: CodexModelProvider) {
        do {
            try CodexConfigService.shared.switchProvider(to: provider.id)
            currentProviderId = provider.id
            successMessage = "Switched to \(provider.name)"
            showingSuccess = true
            loadConfig()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func saveProvider(_ provider: CodexModelProvider) {
        do {
            try CodexConfigService.shared.saveProvider(provider)
            successMessage = "Provider saved"
            showingSuccess = true
            loadConfig()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func deleteProvider(_ provider: CodexModelProvider) {
        do {
            try CodexConfigService.shared.deleteProvider(id: provider.id)
            successMessage = "Provider deleted"
            showingSuccess = true
            loadConfig()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}

/// Row view for a Codex provider.
private struct ProviderRowView: View {
    let provider: CodexModelProvider
    let isCurrent: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Selection indicator
            Circle()
                .fill(isCurrent ? Color.green : Color.clear)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(provider.name)
                        .font(.body)
                    if provider.isUsingProxy {
                        Image(systemName: "arrow.forward.circle")
                            .foregroundColor(.blue)
                            .help("Using proxy")
                    }
                }

                Text(provider.baseURL)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Text("wire_api: \(provider.wireAPI)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Actions
            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
            .disabled(isCurrent)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isCurrent {
                onSelect()
            }
        }
    }
}

/// Form for adding/editing a Codex provider.
public struct ProviderFormView: View {
    @ObservedObject var appState: AppState
    let provider: CodexModelProvider?
    let onSave: (CodexModelProvider) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var id: String = ""
    @State private var name: String = ""
    @State private var baseURL: String = ""
    @State private var upstreamWireAPI: String = "chat"
    @State private var apiKey: String = ""
    @State private var bearerToken: String = ""
    @State private var modelCatalog: ModelCatalog = ModelCatalog(models: [])
    @State private var showAddModel: Bool = false
    @State private var newModelSlug: String = ""
    @State private var newModelDisplayName: String = ""
    @State private var newModelContextWindow: String = "128000"
    @State private var showReasoningConfig = false
    @State private var supportsThinking = false
    @State private var supportsEffort = false
    @State private var thinkingParam = "thinking"
    @State private var effortValueMode = "standard"
    @State private var reasoningOutputFormat = "reasoning_content"

    private var isEditing: Bool {
        provider != nil
    }

    public init(appState: AppState, provider: CodexModelProvider?, onSave: @escaping (CodexModelProvider) -> Void) {
        self.appState = appState
        self.provider = provider
        self.onSave = onSave
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
                Section("Provider ID") {
                    TextField("ID (e.g., openai, anthropic)", text: $id)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isEditing)
                }

                Section("Basic") {
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)

                    TextField("Base URL", text: $baseURL)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                }

                Section("API Configuration") {
                    Picker("Upstream Wire API", selection: $upstreamWireAPI) {
                        Text("Chat Completions").tag("chat")
                        Text("Responses API").tag("responses")
                    }

                    SecureField("API Key (optional)", text: $apiKey)
                        .textFieldStyle(.roundedBorder)

                    SecureField("Bearer Token (optional)", text: $bearerToken)
                        .textFieldStyle(.roundedBorder)
                }

                Section {
                    Toggle("Show Advanced Reasoning Config", isOn: $showReasoningConfig)

                    if showReasoningConfig {
                        Toggle("Supports Thinking (Reasoning)", isOn: $supportsThinking)

                        if supportsThinking {
                            Picker("Thinking Parameter", selection: $thinkingParam) {
                                Text("thinking").tag("thinking")
                                Text("enable_thinking").tag("enable_thinking")
                                Text("reasoning").tag("reasoning")
                            }

                            Picker("Effort Value Mode", selection: $effortValueMode) {
                                Text("Standard (reasoning_effort)").tag("standard")
                                Text("DeepSeek (thinking + reasoning_effort)").tag("deepseek")
                                Text("OpenRouter (reasoning.effort)").tag("openrouter")
                            }

                            Picker("Reasoning Output Format", selection: $reasoningOutputFormat) {
                                Text("reasoning_content").tag("reasoning_content")
                                Text("reasoning_details").tag("reasoning_details")
                                Text("think_tags").tag("think_tags")
                            }

                            Toggle("Supports Effort Levels", isOn: $supportsEffort)
                        }
                    }
                } header: {
                    Text("Reasoning Configuration")
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Model Catalog")
                                .font(.headline)
                            Spacer()
                            Button(action: { showAddModel = true }) {
                                Image(systemName: "plus.circle")
                            }
                            .buttonStyle(.borderless)
                        }

                        if modelCatalog.models.isEmpty {
                            Text("No models added")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        } else {
                            ForEach(modelCatalog.models) { model in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(model.displayName ?? model.model)
                                            .fontWeight(.medium)
                                        Text("ID: \(model.model)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        if let ctx = model.contextWindow {
                                            Text("Context: \(ctx / 1000)K tokens")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Button(action: {
                                        withAnimation {
                                            modelCatalog.models.removeAll { $0.id == model.id }
                                        }
                                    }) {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.borderless)
                                }
                                .padding(.vertical, 4)
                                Divider()
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Custom Models")
                } footer: {
                    Text("Add custom models to appear in Codex model selector")
                }
            }
            .formStyle(.grouped)

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Save") {
                    let reasoningConfig = showReasoningConfig && supportsThinking
                        ? ReasoningConfig(
                            supportsThinking: true,
                            supportsEffort: supportsEffort ? true : nil,
                            thinkingParam: thinkingParam,
                            effortParam: nil,
                            effortValueMode: effortValueMode,
                            outputFormat: reasoningOutputFormat
                        )
                        : nil
                    let newProvider = CodexModelProvider(
                        id: id.lowercased().replacingOccurrences(of: " ", with: "-"),
                        name: name.isEmpty ? id : name,
                        baseURL: baseURL,
                        wireAPI: "responses",
                        upstreamWireAPI: upstreamWireAPI,
                        apiKey: apiKey.isEmpty ? nil : apiKey,
                        bearerToken: bearerToken.isEmpty ? nil : bearerToken,
                        modelCatalog: modelCatalog.models.isEmpty ? nil : modelCatalog,
                        reasoningConfig: reasoningConfig
                    )
                    onSave(newProvider)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(id.isEmpty || baseURL.isEmpty)
            }
            .padding()
        }
        .frame(width: 500, height: 550)
        .onAppear {
            if let provider = provider {
                id = provider.id
                name = provider.name
                baseURL = provider.baseURL
                upstreamWireAPI = provider.upstreamWireAPI
                apiKey = provider.apiKey ?? ""
                bearerToken = provider.bearerToken ?? ""
                modelCatalog = provider.modelCatalog ?? ModelCatalog(models: [])
                if let rc = provider.reasoningConfig {
                    supportsThinking = rc.supportsThinking ?? false
                    supportsEffort = rc.supportsEffort ?? false
                    thinkingParam = rc.thinkingParam ?? "thinking"
                    effortValueMode = rc.effortValueMode ?? "standard"
                    reasoningOutputFormat = rc.outputFormat ?? "reasoning_content"
                    showReasoningConfig = true
                }
            }
        }
        .alert("Add Model", isPresented: $showAddModel) {
            TextField("Model ID (slug)", text: $newModelSlug)
            TextField("Display Name", text: $newModelDisplayName)
            TextField("Context Window", text: $newModelContextWindow)
            Button("Cancel", role: .cancel) {
                newModelSlug = ""
                newModelDisplayName = ""
                newModelContextWindow = "128000"
            }
            Button("Add") {
                if !newModelSlug.isEmpty {
                    let entry = ModelCatalogEntry(
                        model: newModelSlug,
                        displayName: newModelDisplayName.isEmpty ? nil : newModelDisplayName,
                        contextWindow: UInt64(newModelContextWindow)
                    )
                    modelCatalog.models.append(entry)
                }
                newModelSlug = ""
                newModelDisplayName = ""
                newModelContextWindow = "128000"
            }
        } message: {
            Text("Enter model details")
        }
    }
}
