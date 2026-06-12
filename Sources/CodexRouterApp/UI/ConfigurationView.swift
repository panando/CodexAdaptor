import SwiftUI
import CodexRouterCore

/// Unified configuration window with sidebar navigation.
public struct ConfigurationView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var loc = LocalizationService.shared
    @State private var selectedTab: ConfigTab? = .server

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            List(selection: $selectedTab) {
                Section {
                    sidebarItem(tab: .server, icon: "network", title: L10n.server) {
                        Circle()
                            .fill(appState.isRunning ? Color.green : Color.red)
                            .frame(width: 7, height: 7)
                    }

                    sidebarItem(tab: .providers, icon: "server.rack", title: L10n.providers)

                }
                Section {
                    sidebarItem(tab: .help, icon: "questionmark.circle", title: L10n.help)
                    sidebarItem(tab: .logs, icon: "doc.text.magnifyingglass", title: L10n.logs)
                    sidebarItem(tab: .about, icon: "info.circle", title: L10n.about)
                }
            }
            .listStyle(.sidebar)
            .frame(width: 180)

            Divider()

            // Detail
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(minWidth: 780, minHeight: 560)
    }

    private func sidebarItem(tab: ConfigTab, icon: String, title: String) -> some View {
        Label(title, systemImage: icon)
            .tag(tab)
    }

    private func sidebarItem<V: View>(tab: ConfigTab, icon: String, title: String, @ViewBuilder trailing: @escaping () -> V) -> some View {
        Label {
            HStack(spacing: 6) {
                Text(title)
                Spacer()
                trailing()
            }
        } icon: {
            Image(systemName: icon)
        }
        .tag(tab)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedTab {
        case .server:
            ServerSettingsView(appState: appState)
        case .providers:
            ProvidersView(appState: appState)
        case .logs:
            LogViewerView()
        case .help:
            HelpView()
        case .about:
            AboutView()
        case nil:
            VStack {
                Image(systemName: "gearshape")
                    .font(.system(size: 32))
                    .foregroundColor(.secondary)
                Text(L10n.selectSection)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Config Tab

enum ConfigTab: String, CaseIterable, Identifiable {
    case server
    case providers
    case logs
    case help
    case about

    var id: String { rawValue }
}

// MARK: - Help View

private struct HelpView: View {
    @ObservedObject private var loc = LocalizationService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(L10n.helpTitle, systemImage: "questionmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                    Text(L10n.helpSubtitle)
                        .foregroundColor(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Label(L10n.howItWorks, systemImage: "arrow.triangle.swap")
                        .font(.headline)
                    Text(L10n.howItWorksDesc)
                        .font(.body)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label(L10n.setupGuide, systemImage: "list.number")
                        .font(.headline)
                    VStack(alignment: .leading, spacing: 6) {
                        step(1, L10n.setup1)
                        step(2, L10n.setup2)
                        step(3, L10n.setup3)
                        step(4, L10n.setup4)
                        step(5, L10n.setup5)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label(L10n.configFiles, systemImage: "doc.text")
                        .font(.headline)
                    VStack(alignment: .leading, spacing: 10) {
                        fileEntry(path: "~/.codex/config.toml", desc: L10n.fileConfigDesc)
                        fileEntry(path: "~/.codex/providers.json", desc: L10n.fileProvidersDesc)
                        fileEntry(path: "~/.codex/<provider-id>-model-catalog.json", desc: L10n.fileCatalogDesc)
                        fileEntry(path: "~/.codex/config.toml.bak.codexadaptor", desc: L10n.fileBackupDesc)
                    }
                }

                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func step(_ num: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(num).")
                .font(.body).fontWeight(.medium)
                .foregroundColor(.blue)
                .frame(width: 20, alignment: .leading)
            Text(text)
                .font(.body)
        }
    }

    private func fileEntry(path: String, desc: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(path)
                .font(.system(.callout, design: .monospaced))
                .foregroundColor(.primary)
            Text(desc)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Version

private func appVersion() -> String {
    // 1. Bundle Info.plist (production .app)
    if let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
       !ver.isEmpty {
        return ver
    }
    // 2. VERSION file (dev)
    if let execDir = Bundle.main.executableURL?
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent() {
        let verPath = execDir.appendingPathComponent("VERSION").path
        if let ver = try? String(contentsOfFile: verPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           !ver.isEmpty {
            return ver
        }
    }
    return "0.0.0"
}

// MARK: - About View

private struct AboutView: View {
    @ObservedObject private var loc = LocalizationService.shared

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Image(systemName: "network.badge.shield.half.filled")
                    .font(.system(size: 56))
                    .foregroundColor(.blue)

                Text("CodexAdaptor")
                    .font(.title)
                    .fontWeight(.bold)

                Text(L10n.version(appVersion()))
                    .font(.body)
                    .foregroundColor(.secondary)

                Text(L10n.aboutSubtitle)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .padding(.top, 40)
            .padding(.bottom, 24)

            Divider()
                .padding(.horizontal, 40)

            Form {
                Section {
                    Picker(L10n.language, selection: Binding(
                        get: { loc.language },
                        set: { loc.language = $0 }
                    )) {
                        Text(L10n.english).tag("en")
                        Text(L10n.chinese).tag("zh")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                } header: {
                    Label(L10n.preferences, systemImage: "gearshape")
                }
            }
            .formStyle(.grouped)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Server Settings

/// Server configuration section.
private struct ServerSettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var loc = LocalizationService.shared

    @State private var port: String = "15721"
    @State private var proxyURL: String = "http://127.0.0.1:15721/v1"
    @State private var availableProviders: [CodexModelProvider] = []

    init(appState: AppState) {
        self.appState = appState
    }

    var body: some View {
        Form {
            // Server controls
            Section {
                HStack {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(appState.isRunning ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(appState.isRunning ? L10n.running : L10n.stopped)
                            .fontWeight(.medium)
                        if appState.isRunning {
                            Text("(\(L10n.portLabel) \(String(appState.port)))")
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Button(action: {
                        Task {
                            if appState.isRunning { await appState.stopServer() }
                            else { await appState.startServer() }
                        }
                    }) {
                        Label(
                            appState.isRunning ? L10n.stopServer : L10n.startServer,
                            systemImage: appState.isRunning ? "stop.circle" : "play.circle"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            } header: {
                Label(L10n.runtimeStatus, systemImage: "power")
            }

            // Provider selection
            Section {
                Picker(L10n.activeProvider, selection: Binding(
                    get: { appState.currentProvider ?? "" },
                    set: { newProviderName in
                        if let provider = availableProviders.first(where: { $0.name == newProviderName }) {
                            do {
                                try CodexConfigService.shared.switchProvider(to: provider.id)
                                appState.loadConfig()
                            } catch {}
                        }
                    }
                )) {
                    ForEach(availableProviders.map { $0.name }, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .disabled(availableProviders.isEmpty || appState.isRunning)
            } header: {
                Label(L10n.providers, systemImage: "server.rack")
            }

            // Proxy settings
            Section {
                HStack(spacing: 8) {
                    Text(L10n.proxyPort)
                        .frame(width: 96, alignment: .leading)
                    TextField("", text: $port)
                        .textFieldStyle(.roundedBorder)
                    Text(L10n.restartToApply)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 112, alignment: .leading)
                }
                HStack(spacing: 8) {
                    Text(L10n.proxyURL)
                        .frame(width: 96, alignment: .leading)
                    TextField("", text: .constant(proxyURL))
                        .textFieldStyle(.roundedBorder)
                        .disabled(true)
                    Text(L10n.autoConfigured)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 112, alignment: .leading)
                }
            } header: {
                Text(L10n.proxyServer)
            }

            // Config files
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent("Config", value: "~/.codex/config.toml")
                        .font(.system(.body, design: .monospaced))
                    Text(L10n.configDesc)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent("Metadata", value: "~/.codex/providers.json")
                        .font(.system(.body, design: .monospaced))
                    Text(L10n.metadataDesc)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text(L10n.configFiles)
            }

            // Codex Enhancements
            Section {
                Toggle(isOn: Binding(
                    get: { appState.pluginEntryUnlock },
                    set: { newValue in
                        appState.pluginEntryUnlock = newValue
                        Task { await appState.pushInjectionSettings() }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.pluginEntryUnlock).fontWeight(.medium)
                        Text(L10n.pluginEntryUnlockDesc)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Toggle(isOn: Binding(
                    get: { appState.pluginMarketplaceUnlock },
                    set: { newValue in
                        appState.pluginMarketplaceUnlock = newValue
                        Task { await appState.pushInjectionSettings() }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.pluginMarketplaceUnlock).fontWeight(.medium)
                        Text(L10n.pluginMarketplaceUnlockDesc)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Toggle(isOn: Binding(
                    get: { appState.forcePluginInstall },
                    set: { newValue in
                        appState.forcePluginInstall = newValue
                        Task { await appState.pushInjectionSettings() }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.forcePluginInstall).fontWeight(.medium)
                        Text(L10n.forcePluginInstallDesc)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    Text(L10n.codexDebugPort)
                        .frame(width: 96, alignment: .leading)
                    TextField("", value: Binding(
                        get: { appState.codexDebugPort },
                        set: { appState.codexDebugPort = $0 }
                    ), format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                    Text(L10n.codexDebugPortDesc)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 112, alignment: .leading)
                }
            } header: {
                Label(L10n.codexEnhancements, systemImage: "wand.and.stars")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            port = String(appState.port)
            proxyURL = "http://127.0.0.1:\(appState.port)/v1"
            availableProviders = (try? CodexConfigService.shared.getModelProviders()) ?? []
        }
        .onChange(of: port) { _, newValue in
            if let portValue = Int(newValue) {
                appState.port = portValue
                proxyURL = "http://127.0.0.1:\(portValue)/v1"
            }
        }
    }
}
