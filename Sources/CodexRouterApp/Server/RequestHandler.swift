import Foundation
import Hummingbird
import NIOCore
import CodexRouterCore

/// Handles incoming proxy requests and forwards them to upstream providers.
/// Uses CodexConfigService as the SINGLE source of truth for configuration.
public actor RequestHandler {
    private let reasoningRectifier: ReasoningRectifier
    private let chatToResponsesTransformer: ChatToResponsesTransformer
    private let responsesToChatTransformer: ResponsesToChatTransformer
    private let sseTransformer: SSEStreamTransformer
    private let httpClient: HTTPClient

    public init() {
        self.reasoningRectifier = ReasoningRectifier()
        self.chatToResponsesTransformer = ChatToResponsesTransformer()
        self.responsesToChatTransformer = ResponsesToChatTransformer()
        self.sseTransformer = SSEStreamTransformer()
        self.httpClient = HTTPClient()
    }

    /// Handle a proxy request.
    public func handle(
        request: Request,
        endpoint: ProxyEndpoint
    ) async throws -> Response {
        // Get current upstream provider from Codex config (SINGLE SOURCE OF TRUTH)
        guard let provider = try CodexConfigService.shared.getCurrentUpstreamProvider() else {
            return Response(
                status: .serviceUnavailable,
                body: .init(byteBuffer: ByteBuffer(string: #"{"error":"No provider configured in ~/.codex/config.toml"}"#))
            )
        }

        return try await forwardRequest(request: request, provider: provider, endpoint: endpoint)
    }

    /// Forward request to upstream provider.
    private func forwardRequest(
        request: Request,
        provider: UpstreamProvider,
        endpoint: ProxyEndpoint
    ) async throws -> Response {
        // Build upstream URL
        let upstreamURL = provider.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            + endpoint.upstreamPath(usesChatCompletions: provider.usesChatCompletions)

        NSLog("[CodexRouter] Upstream URL: \(upstreamURL)")
        NSLog("[CodexRouter] usesChatCompletions: \(provider.usesChatCompletions)")

        // Build headers
        var headers: [String: String] = [:]
        headers["Content-Type"] = "application/json"

        // Add bearer token if configured
        if let token = provider.bearerToken {
            headers["Authorization"] = "Bearer \(token)"
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
            if let bodyString = String(data: requestBody!, encoding: .utf8) {
                NSLog("[CodexRouter] Request body: \(bodyString.prefix(500))")
            }
        }

        // Apply reasoning rectification and transform request if needed
        var requestJSON: [String: Any]?
        if let data = requestBody,
           var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let rc = provider.reasoningConfig {
                reasoningRectifier.rectifyRequestWithConfig(&json, config: rc)
            } else {
                let platform = ReasoningPlatform.detect(from: provider.baseURL)
                reasoningRectifier.rectifyRequest(&json, provider: nil, platform: platform)
            }

            // Transform request from Responses API to Chat Completions format if needed
            if endpoint == .responses && provider.usesChatCompletions {
                NSLog("[CodexRouter] Transforming Responses request to Chat Completions")
                json = transformResponsesRequestToChat(json)
            }

            requestJSON = json
            requestBody = try? JSONSerialization.data(withJSONObject: json)
            if let body = requestBody, let str = String(data: body, encoding: .utf8) {
                NSLog("[CodexRouter] Transformed request body: \(str.prefix(500))")
            }
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

                // Transform response if needed
                let transformedData = transformResponse(data: data, provider: provider, endpoint: endpoint)

                return Response(
                    status: status,
                    body: .init(byteBuffer: ByteBuffer(data: transformedData))
                )
            }
        } catch {
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
        provider: UpstreamProvider,
        endpoint: ProxyEndpoint
    ) async throws -> Response {
        // Determine if we need to transform the stream
        let needsTransformation = provider.usesChatCompletions && endpoint == .responses

        NSLog("[CodexRouter] Streaming request to \(url), needsTransformation: \(needsTransformation)")

        // Get the streaming response from the upstream
        let streamingResponse = try await httpClient.sendStreaming(
            url: url,
            method: .post,
            headers: headers,
            body: body
        )

        // Build response headers
        var responseHeaders = HTTPFields()
        responseHeaders[.contentType] = "text/event-stream"
        responseHeaders[.cacheControl] = "no-cache"
        responseHeaders[.connection] = "keep-alive"

        if needsTransformation {
            // Create a stateful transformer for this stream
            let transformer = ChatToResponsesStreamTransformer()

            // Create an async sequence that transforms and yields events
            let eventSequence = streamingResponse.events.map { (data: Data) -> ByteBuffer in
                if let transformedData = await transformer.transform(data) {
                    NSLog("[CodexRouter] Transformed \(data.count) bytes -> \(transformedData.count) bytes")
                    return ByteBuffer(data: transformedData)
                } else {
                    NSLog("[CodexRouter] Transformation returned nil, passing through \(data.count) bytes")
                    return ByteBuffer(data: data)
                }
            }

            let streamingBody = ResponseBody(asyncSequence: eventSequence)

            return Response(
                status: streamingResponse.status,
                headers: responseHeaders,
                body: streamingBody
            )
        } else {
            // No transformation needed - pass through
            let eventSequence = streamingResponse.events.map { (data: Data) -> ByteBuffer in
                return ByteBuffer(data: data)
            }

            let streamingBody = ResponseBody(asyncSequence: eventSequence)

            return Response(
                status: streamingResponse.status,
                headers: responseHeaders,
                body: streamingBody
            )
        }
    }

    /// Transform response based on endpoint and provider.
    private func transformResponse(data: Data, provider: UpstreamProvider, endpoint: ProxyEndpoint) -> Data {
        guard var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return data
        }

        // Apply reasoning rectification to response
        if let rc = provider.reasoningConfig {
            reasoningRectifier.rectifyResponseWithConfig(&json, config: rc)
        } else {
            let platform = ReasoningPlatform.detect(from: provider.baseURL)
            reasoningRectifier.rectifyResponse(&json, provider: nil, platform: platform)
        }

        // Transform format if needed
        if provider.usesChatCompletions && endpoint == .responses {
            // Convert Chat Completions to Responses format
            do {
                let chatResponse = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
                let responsesAPI = chatToResponsesTransformer.transform(chatResponse: chatResponse)
                return try JSONEncoder().encode(responsesAPI)
            } catch {
                NSLog("[CodexRouter] Failed to transform Chat to Responses: \(error)")
                return data
            }
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

    /// Transform Responses API request to Chat Completions format.
    private func transformResponsesRequestToChat(_ json: [String: Any]) -> [String: Any] {
        var result = json

        // Transform input to messages
        if let input = json["input"] as? [[String: Any]] {
            var messages: [[String: Any]] = []

            for item in input {
                var message: [String: Any] = [:]

                if let role = item["role"] as? String {
                    message["role"] = role
                }

                // Handle content
                if let content = item["content"] as? String {
                    message["content"] = content
                } else if let contentArray = item["content"] as? [[String: Any]] {
                    // Convert input_text to text
                    let convertedContent = contentArray.compactMap { block -> [String: Any]? in
                        guard let type = block["type"] as? String else { return nil }
                        var newBlock = block
                        if type == "input_text" {
                            newBlock["type"] = "text"
                        }
                        return newBlock
                    }
                    message["content"] = convertedContent
                }

                // Copy tool calls and tool call ID
                if let toolCalls = item["tool_calls"] as? [[String: Any]] {
                    message["tool_calls"] = toolCalls
                }
                if let toolCallId = item["tool_call_id"] as? String {
                    message["tool_call_id"] = toolCallId
                }

                if !message.isEmpty {
                    messages.append(message)
                }
            }

            result["messages"] = messages
            result.removeValue(forKey: "input")
        }

        // Rename max_output_tokens to max_tokens
        if let maxOutputTokens = json["max_output_tokens"] {
            result["max_tokens"] = maxOutputTokens
            result.removeValue(forKey: "max_output_tokens")
        }

        return result
    }
}
