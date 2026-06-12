import SwiftUI
import CodexRouterCore

/// View for managing model providers.
public struct ProvidersView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var loc = LocalizationService.shared
    @State private var providers: [CodexModelProvider] = []
    @State private var currentProviderId: String?
    @State private var currentModel: String?
    @State private var isLoading = true
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingSuccess = false
    @State private var successMessage = ""
    @State private var providerToDelete: CodexModelProvider?

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 0) {
                HStack {
                    Label(L10n.providers, systemImage: "server.rack")
                        .font(.headline)
                    Spacer()
                    Button(action: { loadConfig() }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help(L10n.refresh)
                    Button(action: { openProviderForm() }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.accentColor)
                    .help(L10n.addProvider)
                }
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 10)
            }

            Divider()

            if isLoading {
                ProgressView(L10n.loading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if providers.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text(L10n.noProviders)
                        .font(.body)
                        .foregroundColor(.secondary)
                    Text(L10n.addProviderHint)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Provider list
                List {
                    ForEach(providers) { provider in
                        ProviderRowView(
                            provider: provider,
                            isCurrent: provider.id == currentProviderId,
                            onEdit: {
                                openProviderForm(provider: provider)
                            },
                            onDelete: {
                                providerToDelete = provider
                            }
                        )
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.inset)
            }

        }
        .onAppear {
            loadConfig()
        }
        .alert(L10n.error, isPresented: $showingError) {
            Button(L10n.ok, role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .alert(L10n.success, isPresented: $showingSuccess) {
            Button(L10n.ok, role: .cancel) {}
        } message: {
            Text(successMessage)
        }
        .confirmationDialog(
            L10n.deleteConfirmMsg(providerToDelete?.name ?? ""),
            isPresented: Binding(
                get: { providerToDelete != nil },
                set: { if !$0 { providerToDelete = nil } }
            )
        ) {
            Button(L10n.deleteBtn, role: .destructive) {
                if let provider = providerToDelete {
                    deleteProvider(provider)
                    providerToDelete = nil
                }
            }
            Button(L10n.cancel, role: .cancel) { providerToDelete = nil }
        } message: {
            Text(L10n.deleteCannotUndo)
        }
    }

    private func openProviderForm(provider: CodexModelProvider? = nil) {
        let w = provider != nil ? L10n.editProvider : L10n.addProvider
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 720),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false
        )
        window.title = w
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView:
            ProviderFormView(
                appState: appState,
                provider: provider,
                onSave: { [weak window] updatedProvider in
                    saveProvider(updatedProvider)
                    window?.close()
                },
                onDismiss: { [weak window] in
                    window?.close()
                }
            )
        )
        window.makeKeyAndOrderFront(nil)
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
            successMessage = "\(L10n.switchSuccess) \(provider.name)"
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
            successMessage = L10n.saved
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
            successMessage = L10n.deleted
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
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(isCurrent ? Color.green : Color.gray.opacity(0.35))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.name)
                    .font(.body)
                    .fontWeight(.medium)
                Text(provider.baseURL)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            HStack(spacing: 8) {
                Button(action: onEdit) {
                    Label(L10n.edit, systemImage: "pencil")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(L10n.editProviderTooltip)

                Button(action: onDelete) {
                    Label(L10n.deleteBtn, systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isCurrent)
                .help(isCurrent ? L10n.cannotDeleteActive : L10n.deleteProviderTooltip)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }
}


/// Form for adding/editing a Codex provider. Present in its own NSWindow.
public struct ProviderFormView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var loc = LocalizationService.shared
    let provider: CodexModelProvider?
    let onSave: (CodexModelProvider) -> Void
    let onDismiss: () -> Void

    @State private var id: String = ""
    @State private var name: String = ""
    @State private var baseURL: String = ""
    @State private var upstreamWireAPI: String = "chat"
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
    @State private var effortParam = "reasoning_effort"
    @State private var effortValueMode = "standard"
    @State private var reasoningOutputFormat = "reasoning_content"
    @State private var modelIndexToDelete: Int?

    private var isEditing: Bool { provider != nil }

    @ViewBuilder
    private var modelEditorForm: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.modelAlias)
                        .font(.caption).fontWeight(.medium).foregroundColor(.secondary)
                    TextField("", text: $newModelDisplayName)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                    Text(L10n.modelAliasDesc)
                        .font(.caption2).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.modelSlug)
                        .font(.caption).fontWeight(.medium).foregroundColor(.secondary)
                    TextField("", text: $newModelSlug)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.callout, design: .monospaced))
                        .multilineTextAlignment(.leading)
                        .autocorrectionDisabled()
                    Text(L10n.modelSlugDesc)
                        .font(.caption2).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.contextWindow)
                        .font(.caption).fontWeight(.medium).foregroundColor(.secondary)
                    TextField("", text: $newModelContextWindow)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                    Text(L10n.contextWindowExample)
                        .font(.caption2).foregroundColor(.secondary)
                }
                .frame(width: 100)

                // Spacer to match delete button column
                Spacer().frame(width: 24)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            HStack(spacing: 10) {
                Button(L10n.cancel) {
                    resetModelForm()
                    showAddModel = false
                }
                .controlSize(.small)
                Button(L10n.add) {
                    guard !newModelSlug.isEmpty else { return }
                    let entry = ModelCatalogEntry(
                        model: newModelSlug,
                        displayName: newModelDisplayName.isEmpty ? nil : newModelDisplayName,
                        contextWindow: UInt64(newModelContextWindow)
                    )
                    modelCatalog.models.append(entry)
                    resetModelForm()
                    showAddModel = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(newModelSlug.isEmpty)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private func resetModelForm() {
        newModelSlug = ""
        newModelDisplayName = ""
        newModelContextWindow = "128000"
    }

    public init(appState: AppState, provider: CodexModelProvider?, onSave: @escaping (CodexModelProvider) -> Void, onDismiss: @escaping () -> Void) {
        self.appState = appState
        self.provider = provider
        self.onSave = onSave
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: isEditing ? "pencil.circle.fill" : "plus.circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                Text(isEditing ? L10n.editProvider : L10n.addProvider)
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Button(L10n.cancel) { onDismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            // Scrollable form content
            ScrollView {
                Form {
                    Section {
                        TextField(L10n.providerName, text: $name, prompt: Text(L10n.providerNamePrompt))
                            .textFieldStyle(.roundedBorder)

                        TextField(L10n.baseURL, text: $baseURL, prompt: Text("https://api.deepseek.com"))
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                    } header: {
                        Label(L10n.basicInfo, systemImage: "info.circle")
                    }

                    Section {
                        Picker(L10n.wireProtocol, selection: $upstreamWireAPI) {
                            Text(L10n.chatCompletions).tag("chat")
                            Text(L10n.responsesAPI).tag("responses")
                        }
                        .pickerStyle(.radioGroup)

                        SecureField(L10n.apiKey, text: $bearerToken, prompt: Text(L10n.apiKeyPrompt))
                            .textFieldStyle(.roundedBorder)
                    } header: {
                        Label(L10n.apiConfig, systemImage: "key")
                    }

                    Section {
                        HStack {
                            Toggle(L10n.overrideReasoning, isOn: $showReasoningConfig)
                            Spacer()
                            Button(L10n.autoDetect) {
                                if !baseURL.isEmpty {
                                    let inferred = ReasoningConfig.infer(name: name, baseURL: baseURL, model: "")
                                    if let rc = inferred {
                                        supportsThinking = rc.supportsThinking ?? false
                                        supportsEffort = rc.supportsEffort ?? false
                                        thinkingParam = rc.thinkingParam ?? "thinking"
                                        effortParam = rc.effortParam ?? "reasoning_effort"
                                        effortValueMode = rc.effortValueMode ?? "standard"
                                        reasoningOutputFormat = rc.outputFormat ?? "reasoning_content"
                                        showReasoningConfig = true
                                    }
                                }
                            }
                            .disabled(baseURL.isEmpty)
                            .controlSize(.small)
                        }

                        if showReasoningConfig {
                            VStack(alignment: .leading, spacing: 10) {
                                // Thinking group
                                VStack(alignment: .leading, spacing: 6) {
                                    Toggle(L10n.enableThinking, isOn: $supportsThinking)
                                    Text(L10n.thinkingDesc)
                                        .font(.caption).foregroundColor(.secondary)

                                    if supportsThinking {
                                        Picker(L10n.parameterName, selection: $thinkingParam) {
                                            Text(L10n.thinkingDeepSeek).tag("thinking")
                                            Text(L10n.thinkingSiliconFlow).tag("enable_thinking")
                                            Text(L10n.thinkingMiniMax).tag("reasoning_split")
                                            Text(L10n.thinkingNone).tag("none")
                                        }
                                    }
                                }
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.secondary.opacity(0.06))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                                )

                                // Effort group
                                VStack(alignment: .leading, spacing: 6) {
                                    Toggle(L10n.enableEffort, isOn: $supportsEffort)
                                    Text(L10n.effortDesc)
                                        .font(.caption).foregroundColor(.secondary)

                                    if supportsEffort {
                                        Picker(L10n.effortParam, selection: $effortParam) {
                                            Text(L10n.reasoningEffort).tag("reasoning_effort")
                                            Text(L10n.reasoningEffortNested).tag("reasoning.effort")
                                        }

                                        Picker(L10n.valueMapping, selection: $effortValueMode) {
                                            Text(L10n.standardPassthrough).tag("standard")
                                            Text(L10n.deepseekClamp).tag("deepseek")
                                            Text(L10n.openrouterMap).tag("openrouter")
                                            Text(L10n.lowHighBinary).tag("low_high")
                                        }
                                    }
                                }
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.secondary.opacity(0.06))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                                )

                                // Output format group
                                VStack(alignment: .leading, spacing: 4) {
                                    Picker(L10n.outputFormat, selection: $reasoningOutputFormat) {
                                        Text(L10n.reasoningContent).tag("reasoning_content")
                                        Text(L10n.reasoningDetails).tag("reasoning_details")
                                        Text(L10n.reasoningGeneric).tag("reasoning")
                                        Text(L10n.auto).tag("auto")
                                    }
                                    Text(L10n.outputFormatDesc)
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.secondary.opacity(0.06))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                                )
                            }
                        }
                    } header: {
                        Label(L10n.reasoningConfig, systemImage: "brain.head.profile")
                    } footer: {
                        if !showReasoningConfig {
                            Text(L10n.reasoningAutoDetectFooter)
                        }
                    }

                }
                .formStyle(.grouped)
                .frame(minWidth: 600)

                // Custom Models — outside Form to avoid .formStyle(.grouped) alignment issues
                VStack(alignment: .leading, spacing: 0) {
                    // Section header
                    Label(L10n.customModels, systemImage: "cube.box")
                        .font(.footnote).fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)

                    // Content card
                    VStack(spacing: 0) {
                        // Column headers
                        HStack(spacing: 12) {
                            Text(L10n.modelAlias)
                                .font(.caption).fontWeight(.medium).foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(L10n.modelSlug)
                                .font(.caption).fontWeight(.medium).foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(L10n.contextWindow)
                                .font(.caption).fontWeight(.medium).foregroundColor(.secondary)
                                .frame(width: 100, alignment: .leading)
                            Spacer().frame(width: 24)
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                        .padding(.bottom, 4)

                        Divider().padding(.horizontal, 12)

                        // Editable model rows
                        ForEach(Array(modelCatalog.models.enumerated()), id: \.element.id) { index, _ in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    TextField("", text: Binding(
                                        get: { modelCatalog.models[index].displayName ?? "" },
                                        set: { modelCatalog.models[index].displayName = $0.isEmpty ? nil : $0 }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                    .multilineTextAlignment(.leading)
                                    Text(L10n.modelAliasDesc)
                                        .font(.caption2).foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)

                                VStack(alignment: .leading, spacing: 2) {
                                    TextField("", text: Binding(
                                        get: { modelCatalog.models[index].model },
                                        set: { modelCatalog.models[index].model = $0 }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.callout, design: .monospaced))
                                    .multilineTextAlignment(.leading)
                                    Text(L10n.modelSlugDesc)
                                        .font(.caption2).foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)

                                VStack(alignment: .leading, spacing: 2) {
                                    TextField("", text: Binding(
                                        get: { modelCatalog.models[index].contextWindow.map { String($0) } ?? "" },
                                        set: { modelCatalog.models[index].contextWindow = UInt64($0) }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                    .multilineTextAlignment(.leading)
                                    Text(L10n.contextWindowExample)
                                        .font(.caption2).foregroundColor(.secondary)
                                }
                                .frame(width: 100)

                                Button {
                                    modelIndexToDelete = index
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .controlSize(.small)
                                .help(L10n.removeModel)
                                .frame(width: 24)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)

                            if index < modelCatalog.models.count - 1 {
                                Divider().padding(.horizontal, 12)
                            }
                        }

                        if showAddModel {
                            Divider().padding(.horizontal, 12)
                            modelEditorForm
                        }

                        Divider().padding(.horizontal, 12)

                        if !showAddModel {
                            Button {
                                resetModelForm()
                                showAddModel = true
                            } label: {
                                Label(L10n.addModel, systemImage: "plus.circle")
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                    }
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                    )
                    .padding(.horizontal, 16)

                    // Footer
                    Text(L10n.modelFooter)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                }
                .padding(.vertical, 8)
            }

            Divider()

            // Footer
            HStack {
                Spacer()
                Button(L10n.cancel) { onDismiss() }
                Button(L10n.save) { doSave() }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.isEmpty || baseURL.isEmpty)
                    .keyboardShortcut(.return, modifiers: [.command])
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 640, minHeight: 640)
        .onAppear { populateFromProvider() }
        .confirmationDialog(
            L10n.removeModelConfirm(modelIndexToDelete.map { modelCatalog.models[$0].displayName ?? modelCatalog.models[$0].model } ?? ""),
            isPresented: Binding(
                get: { modelIndexToDelete != nil },
                set: { if !$0 { modelIndexToDelete = nil } }
            )
        ) {
            Button(L10n.remove, role: .destructive) {
                if let idx = modelIndexToDelete {
                    modelCatalog.models.remove(at: idx)
                    modelIndexToDelete = nil
                }
            }
            Button(L10n.cancel, role: .cancel) { modelIndexToDelete = nil }
        } message: {
            Text(L10n.removeModelDesc)
        }
    }

    private func populateFromProvider() {
        guard let provider = provider else { return }
        id = provider.id
        name = provider.name
        baseURL = provider.baseURL
        upstreamWireAPI = provider.upstreamWireAPI
        bearerToken = provider.bearerToken ?? ""
        modelCatalog = provider.modelCatalog ?? ModelCatalog(models: [])
        if let rc = provider.reasoningConfig {
            supportsThinking = rc.supportsThinking ?? false
            supportsEffort = rc.supportsEffort ?? false
            thinkingParam = rc.thinkingParam ?? "thinking"
            effortParam = rc.effortParam ?? "reasoning_effort"
            effortValueMode = rc.effortValueMode ?? "standard"
            reasoningOutputFormat = rc.outputFormat ?? "reasoning_content"
            showReasoningConfig = true
        }
    }

    private func doSave() {
        let providerId = isEditing ? id : name.lowercased().replacingOccurrences(of: " ", with: "-")
        let reasoningConfig = showReasoningConfig
            ? ReasoningConfig(
                supportsThinking: supportsThinking ? true : nil,
                supportsEffort: supportsEffort ? true : nil,
                thinkingParam: thinkingParam == "none" ? "none" : thinkingParam,
                effortParam: supportsEffort ? effortParam : "none",
                effortValueMode: supportsEffort ? effortValueMode : nil,
                outputFormat: reasoningOutputFormat
            )
            : nil
        let newProvider = CodexModelProvider(
            id: providerId,
            name: name.isEmpty ? providerId : name,
            baseURL: baseURL,
            upstreamWireAPI: upstreamWireAPI,
            bearerToken: bearerToken.isEmpty ? nil : bearerToken,
            modelCatalog: modelCatalog.models.isEmpty ? nil : modelCatalog,
            reasoningConfig: reasoningConfig
        )
        onSave(newProvider)
        onDismiss()
    }
}
