import Foundation
import Hummingbird
import CodexRouterCore

/// Route configuration for proxy server.
public enum Routes {
    public static func configure(
        router: Router<BasicRequestContext>,
        settingsHandler: @escaping () async -> (Int, String, String)
    ) {
        // Create request handler
        let requestHandler = RequestHandler()

        // Health check
        router.get("/health") { _, _ in
            return Response(
                status: .ok,
                body: .init(byteBuffer: ByteBuffer(string: #"{"status":"healthy"}"#))
            )
        }

        // CDP injection settings endpoint (polled by injected JS)
        router.get("/settings/get") { _, _ in
            let (status, contentType, body) = await settingsHandler()
            var headers = HTTPFields()
            headers[.contentType] = contentType
            return Response(
                status: .init(code: status, reasonPhrase: status == 200 ? "OK" : "Error"),
                headers: headers,
                body: .init(byteBuffer: ByteBuffer(string: body))
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
