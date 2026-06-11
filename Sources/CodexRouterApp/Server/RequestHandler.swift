import Foundation
import Hummingbird
import NIOCore
import CodexRouterCore
import CodexRouterDB

/// Handles incoming proxy requests and forwards them to upstream providers.
public actor RequestHandler {
    private let database: Database
    private let providerRouter: ProviderRouter
    private let failoverManager: FailoverManager
    private let httpClient: HTTPClient
    private let reasoningRectifier: ReasoningRectifier
    private let chatToResponsesTransformer: ChatToResponsesTransformer
    private let responsesToChatTransformer: ResponsesToChatTransformer
    private let sseTransformer: SSEStreamTransformer

    public init(database: Database, providerRouter: ProviderRouter) {
        self.database = database
        self.providerRouter = providerRouter
        self.failoverManager = FailoverManager(database: database)
        self.httpClient = HTTPClient()
        self.reasoningRectifier = ReasoningRectifier()
        self.chatToResponsesTransformer = ChatToResponsesTransformer()
        self.responsesToChatTransformer = ResponsesToChatTransformer()
        self.sseTransformer = SSEStreamTransformer()
    }

    /// Handle a proxy request.
    public func handle(
        request: Request,
        endpoint: ProxyEndpoint
    ) async throws -> Response {
        // Get current provider
        guard let provider = try getCurrentProvider() else {
            return Response(
                status: .serviceUnavailable,
                body: .init(byteBuffer: ByteBuffer(string: #"{"error":"No provider configured"}"#))
            )
        }

        // Check circuit breaker (skip for models endpoint)
        if endpoint != .models {
            let breaker = await providerRouter.getCircuitBreaker(for: provider.id)
            guard await breaker.allowRequest() else {
                // Try failover if enabled
                if let failoverProvider = try await getFailoverProvider(excludeIds: [provider.id]) {
                    return try await forwardRequest(request: request, provider: failoverProvider, endpoint: endpoint)
                }

                return Response(
                    status: .serviceUnavailable,
                    body: .init(byteBuffer: ByteBuffer(string: #"{"error":"Provider unavailable"}"#))
                )
            }
        }

        return try await forwardRequest(request: request, provider: provider, endpoint: endpoint)
    }

    /// Forward request to upstream provider.
    private func forwardRequest(
        request: Request,
        provider: Provider,
        endpoint: ProxyEndpoint
    ) async throws -> Response {
        guard let baseURL = provider.baseURL else {
            return Response(
                status: .badGateway,
                body: .init(byteBuffer: ByteBuffer(string: #"{"error":"Provider has no base URL"}"#))
            )
        }

        // Build upstream URL
        let upstreamURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            + endpoint.upstreamPath(provider: provider)

        // Build headers
        var headers: [String: String] = [:]
        headers["Content-Type"] = "application/json"

        // Get API key from Keychain
        if let apiKey = try? KeychainService.shared.getAPIKey(for: provider.id) {
            headers["Authorization"] = "Bearer \(apiKey)"
        }

        if let customUserAgent = provider.meta?.customUserAgent {
            headers["User-Agent"] = customUserAgent
        }

        // Handle GET requests (models endpoint)
        if endpoint == .models {
            do {
                let (data, status) = try await httpClient.send(
                    url: upstreamURL,
                    method: .get,
                    headers: headers,
                    body: nil
                )
                return Response(
                    status: status,
                    body: .init(byteBuffer: ByteBuffer(data: data))
                )
            } catch {
                return Response(
                    status: .badGateway,
                    body: .init(byteBuffer: ByteBuffer(string: #"{"error":"\#(error.localizedDescription)"}"#))
                )
            }
        }

        // Parse request body for POST requests
        var requestBody: Data?
        var bodyBuffer = ByteBuffer()
        for try await chunk in request.body {
            var mutableChunk = chunk
            bodyBuffer.writeBuffer(&mutableChunk)
        }
        if bodyBuffer.readableBytes > 0 {
            requestBody = Data(buffer: bodyBuffer)
        }

        // Apply reasoning rectification
        var requestJSON: [String: Any]?
        if let data = requestBody,
           var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let platform = ReasoningPlatform.detect(from: provider.baseURL)
            reasoningRectifier.rectifyRequest(&json, provider: provider, platform: platform)
            requestJSON = json
            requestBody = try? JSONSerialization.data(withJSONObject: json)
        }

        // Determine if streaming
        let isStreaming = requestJSON?["stream"] as? Bool ?? false

        // Send request
        do {
            if isStreaming {
                return try await handleStreamingRequest(
                    url: upstreamURL,
                    headers: headers,
                    body: requestBody,
                    provider: provider,
                    endpoint: endpoint
                )
            } else {
                let (data, status) = try await httpClient.send(
                    url: upstreamURL,
                    method: .post,
                    headers: headers,
                    body: requestBody
                )

                // Record success
                await recordSuccess(providerId: provider.id)

                // Transform response if needed
                let transformedData = transformResponse(data: data, provider: provider, endpoint: endpoint)

                return Response(
                    status: status,
                    body: .init(byteBuffer: ByteBuffer(data: transformedData))
                )
            }
        } catch {
            // Record failure
            await recordFailure(providerId: provider.id, error: error.localizedDescription)

            // Try failover
            if let failoverProvider = try await getFailoverProvider(excludeIds: [provider.id]) {
                return try await forwardRequest(request: request, provider: failoverProvider, endpoint: endpoint)
            }

            return Response(
                status: .badGateway,
                body: .init(byteBuffer: ByteBuffer(string: #"{"error":"\#(error.localizedDescription)"}"#))
            )
        }
    }

    /// Handle streaming request.
    private func handleStreamingRequest(
        url: String,
        headers: [String: String],
        body: Data?,
        provider: Provider,
        endpoint: ProxyEndpoint
    ) async throws -> Response {
        // For now, return a simple streaming response
        // Full SSE streaming implementation would require more complex handling
        let status: HTTPResponse.Status = .ok
        var responseBody = ByteBuffer()

        _ = try await httpClient.sendStreaming(
            url: url,
            method: .post,
            headers: headers,
            body: body
        ) { data in
            // Transform and accumulate streaming data
            responseBody.writeBytes(data)
        }

        await recordSuccess(providerId: provider.id)

        return Response(
            status: status,
            body: .init(byteBuffer: responseBody)
        )
    }

    /// Transform response based on endpoint and provider.
    private func transformResponse(data: Data, provider: Provider, endpoint: ProxyEndpoint) -> Data {
        guard var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return data
        }

        let platform = ReasoningPlatform.detect(from: provider.baseURL)

        // Apply reasoning rectification to response
        reasoningRectifier.rectifyResponse(&json, provider: provider, platform: platform)

        // Transform format if needed
        if provider.usesChatCompletions && endpoint == .responses {
            // Convert Chat Completions to Responses format
            // This is handled by the transformer
        } else if !provider.usesChatCompletions && endpoint == .chatCompletions {
            // Convert Responses to Chat Completions format
            do {
                let jsonString = String(data: data, encoding: .utf8) ?? "{}"
                let chatResponse = try responsesToChatTransformer.transform(responsesJSON: jsonString)
                return try JSONEncoder().encode(chatResponse)
            } catch {
                return data
            }
        }

        return (try? JSONSerialization.data(withJSONObject: json)) ?? data
    }

    /// Get current provider.
    private func getCurrentProvider() throws -> Provider? {
        let dao = ProviderDAO(database)
        return try dao.getCurrent()
    }

    /// Get failover provider.
    private func getFailoverProvider(excludeIds: Set<String>) async throws -> Provider? {
        let enabled = try await failoverManager.isFailoverEnabled(appType: "codex")
        guard enabled else { return nil }

        return try await failoverManager.getNextProvider(
            appType: "codex",
            providerRouter: providerRouter,
            excludeIds: excludeIds
        )
    }

    /// Record successful request.
    private func recordSuccess(providerId: String) async {
        let breaker = await providerRouter.getCircuitBreaker(for: providerId)
        await breaker.recordSuccess()

        let healthDAO = ProviderHealthDAO(database)
        try? healthDAO.recordSuccess(providerId: providerId, appType: "codex")
    }

    /// Record failed request.
    private func recordFailure(providerId: String, error: String) async {
        let breaker = await providerRouter.getCircuitBreaker(for: providerId)
        await breaker.recordFailure()

        let healthDAO = ProviderHealthDAO(database)
        try? healthDAO.recordFailure(providerId: providerId, appType: "codex", error: error)
    }
}
