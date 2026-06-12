import Foundation
import Combine
import CodexRouterCore

/// Shared application state.
/// Uses CodexConfigService as the SINGLE source of truth for configuration.
@MainActor
public final class AppState: ObservableObject {
    @Published public var isRunning = false
    @Published public var currentProvider: String?
    @Published public var currentModel: String?
    @Published public var port: Int = 15721

    public let server: ProxyServer

    public init() {
        self.server = ProxyServer()
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
            try await server.start(port: port)
            isRunning = true
        } catch {
            print("Failed to start server: \(error)")
        }
    }

    public func stopServer() async {
        await server.stop()
        isRunning = false
    }
}
