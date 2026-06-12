import Foundation
import Combine
import CodexRouterCore

/// Keys for UserDefaults plugin settings.
public enum PluginSettingKeys {
    public static let pluginEntryUnlock = "codexAppPluginEntryUnlock"
    public static let forcePluginInstall = "codexAppForcePluginInstall"
    public static let pluginMarketplaceUnlock = "codexAppPluginMarketplaceUnlock"
    public static let codexDebugPort = "codexDebugPort"
}

/// Shared application state.
/// Uses CodexConfigService as the SINGLE source of truth for configuration.
@MainActor
public final class AppState: ObservableObject {
    @Published public var isRunning = false
    @Published public var currentProvider: String?
    @Published public var currentModel: String?
    @Published public var port: Int = 15721

    @Published public var pluginEntryUnlock: Bool {
        didSet { UserDefaults.standard.set(pluginEntryUnlock, forKey: PluginSettingKeys.pluginEntryUnlock) }
    }
    @Published public var forcePluginInstall: Bool {
        didSet { UserDefaults.standard.set(forcePluginInstall, forKey: PluginSettingKeys.forcePluginInstall) }
    }
    @Published public var pluginMarketplaceUnlock: Bool {
        didSet { UserDefaults.standard.set(pluginMarketplaceUnlock, forKey: PluginSettingKeys.pluginMarketplaceUnlock) }
    }
    @Published public var codexDebugPort: Int {
        didSet { UserDefaults.standard.set(codexDebugPort, forKey: PluginSettingKeys.codexDebugPort) }
    }

    public let server: ProxyServer
    private var injector: CodexAppInjector?

    public init() {
        self.server = ProxyServer()

        let defaults = UserDefaults.standard

        // Plugin settings — default to true (matching CodexPlusPlus)
        if defaults.object(forKey: PluginSettingKeys.pluginEntryUnlock) == nil {
            defaults.set(true, forKey: PluginSettingKeys.pluginEntryUnlock)
        }
        if defaults.object(forKey: PluginSettingKeys.forcePluginInstall) == nil {
            defaults.set(true, forKey: PluginSettingKeys.forcePluginInstall)
        }
        if defaults.object(forKey: PluginSettingKeys.pluginMarketplaceUnlock) == nil {
            defaults.set(true, forKey: PluginSettingKeys.pluginMarketplaceUnlock)
        }
        if defaults.object(forKey: PluginSettingKeys.codexDebugPort) == nil {
            defaults.set(9222, forKey: PluginSettingKeys.codexDebugPort)
        }

        self.pluginEntryUnlock = defaults.bool(forKey: PluginSettingKeys.pluginEntryUnlock)
        self.forcePluginInstall = defaults.bool(forKey: PluginSettingKeys.forcePluginInstall)
        self.pluginMarketplaceUnlock = defaults.bool(forKey: PluginSettingKeys.pluginMarketplaceUnlock)
        self.codexDebugPort = defaults.integer(forKey: PluginSettingKeys.codexDebugPort)

        loadConfig()
    }

    /// Load configuration from Codex config file.
    public func loadConfig() {
        if let provider = try? CodexConfigService.shared.getCurrentProvider() {
            currentProvider = provider.name
        }
        currentModel = try? CodexConfigService.shared.getCurrentModel()
    }

    public func startServer() async {
        do {
            try await server.start(port: port) { [weak self] in
                guard let self = self else {
                    return (500, "application/json", #"{"error":"appState gone"}"#)
                }
                return await self.handleSettingsGet()
            }
            isRunning = true
            await startCDPInjection()
        } catch {
            print("Failed to start server: \(error)")
        }
    }

    public func stopServer() async {
        await stopCDPInjection()
        await server.stop()
        isRunning = false
    }

    // MARK: - CDP Injection

    private func startCDPInjection() async {
        let settings = currentInjectionSettings()
        let injector = CodexAppInjector(debugPort: UInt16(codexDebugPort), settings: settings)
        self.injector = injector
        await injector.start()
    }

    private func stopCDPInjection() async {
        await injector?.stop()
        injector = nil
    }

    public func pushInjectionSettings() async {
        guard let injector = injector else { return }
        await injector.updateSettings(currentInjectionSettings())
    }

    public func currentInjectionSettings() -> CDPInjectionSettings {
        CDPInjectionSettings(
            codexAppPluginEntryUnlock: pluginEntryUnlock,
            codexAppForcePluginInstall: forcePluginInstall,
            enhancementsEnabled: true,
            launchMode: "patch",
            codexAppVersion: "",
            codexAppPluginMarketplaceUnlock: pluginMarketplaceUnlock
        )
    }

    /// Serve the /settings/get endpoint response for injected JS.
    public func handleSettingsGet() async -> (Int, String, String) {
        await pushInjectionSettings()
        guard let injector = injector else {
            let fallback = currentInjectionSettings()
            if let data = try? JSONEncoder().encode(fallback),
               let json = String(data: data, encoding: .utf8) {
                return (200, "application/json", json)
            }
            return (500, "application/json", #"{"error":"no injector"}"#)
        }
        return await injector.handleSettingsGet()
    }
}
