import Foundation
import Hummingbird
import CodexRouterCore
import CodexRouterDB

/// Route configuration for proxy server.
public enum Routes {
    public static func configure(
        router: Router<BasicRequestContext>,
        providerRouter: ProviderRouter,
        database: Database
    ) {
        // Create request handler
        let requestHandler = RequestHandler(database: database, providerRouter: providerRouter)

        // Health check
        router.get("/health") { _, _ in
            return Response(
                status: .ok,
                body: .init(byteBuffer: ByteBuffer(string: #"{"status":"healthy"}"#))
            )
        }

        // Models endpoint - proxy to upstream
        router.get("/v1/models") { request, context in
            return try await requestHandler.handle(request: request, endpoint: .models)
        }

        // Chat Completions (with /v1 prefix)
        router.post("/v1/chat/completions") { request, context in
            return try await requestHandler.handle(request: request, endpoint: .chatCompletions)
        }

        // Responses API (with /v1 prefix)
        router.post("/v1/responses") { request, context in
            return try await requestHandler.handle(request: request, endpoint: .responses)
        }

        // Responses Compact (with /v1 prefix)
        router.post("/v1/responses/compact") { request, context in
            return try await requestHandler.handle(request: request, endpoint: .responsesCompact)
        }

        // MARK: - Routes without /v1 prefix (for Codex compatibility)

        // Models
        router.get("/models") { request, context in
            return try await requestHandler.handle(request: request, endpoint: .models)
        }

        // Chat Completions
        router.post("/chat/completions") { request, context in
            return try await requestHandler.handle(request: request, endpoint: .chatCompletions)
        }

        // Responses API
        router.post("/responses") { request, context in
            return try await requestHandler.handle(request: request, endpoint: .responses)
        }

        // Responses Compact
        router.post("/responses/compact") { request, context in
            return try await requestHandler.handle(request: request, endpoint: .responsesCompact)
        }
    }
}
