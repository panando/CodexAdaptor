import Foundation
import Combine
import CodexRouterCore
import CodexRouterDB

/// Shared application state.
@MainActor
public final class AppState: ObservableObject {
    @Published public var isRunning = false
    @Published public var currentProvider: String?
    @Published public var port: Int = 15721
    @Published public var providers: [Provider] = []

    public let database: Database
    public let server: ProxyServer

    public init() throws {
        self.database = try Database()
        self.server = try ProxyServer(database: database)

        loadProviders()
    }

    public func loadProviders() {
        let dao = ProviderDAO(database)
        providers = (try? dao.getAll()) ?? []
        currentProvider = try? dao.getCurrent()?.name
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
