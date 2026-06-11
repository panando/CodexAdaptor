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

        // Models endpoint
        router.get("/v1/models") { _, _ in
            let response: [String: Any] = [
                "object": "list",
                "data": []
            ]
            let data = try! JSONSerialization.data(withJSONObject: response)
            return Response(
                status: .ok,
                body: .init(byteBuffer: ByteBuffer(data: data))
            )
        }

        // Chat Completions
        router.post("/v1/chat/completions") { request, context in
            return try await requestHandler.handle(request: request, endpoint: .chatCompletions)
        }

        // Responses API
        router.post("/v1/responses") { request, context in
            return try await requestHandler.handle(request: request, endpoint: .responses)
        }

        // Responses Compact
        router.post("/v1/responses/compact") { request, context in
            return try await requestHandler.handle(request: request, endpoint: .responsesCompact)
        }
    }
}
