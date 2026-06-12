import Foundation
import Hummingbird
import CodexRouterCore

/// HTTP proxy server for Codex routing.
/// Simplified - reads configuration directly from ~/.codex/config.toml
public final class ProxyServer: ObservableObject {
    @Published public private(set) var isRunning = false
    @Published public private(set) var port: Int = 15721

    private var app: Application<RouterResponder<BasicRequestContext>>?

    public init() {}

    public func start(port: Int = 15721) async throws {
        self.port = port

        let router = Router()
        Routes.configure(router: router)

        let responder = router.buildResponder()
        let app = Application(
            responder: responder,
            configuration: .init(address: .hostname("127.0.0.1", port: port))
        )

        self.app = app

        Task {
            do {
                try await app.run()
            } catch {
                print("Server error: \(error)")
            }
        }

        await MainActor.run {
            self.isRunning = true
        }

        print("Proxy server started on port \(port)")
    }

    public func stop() async {
        // Application in Hummingbird 2.0 doesn't have shutdown()
        // It will be cleaned up when the process exits
        self.app = nil

        await MainActor.run {
            self.isRunning = false
        }

        print("Proxy server stopped")
    }
}
