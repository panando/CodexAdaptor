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

        NSLog("[CodexRouter] Upstream status: \(streamingResponse.status.code)")

        // Build response headers
        var responseHeaders = HTTPFields()
        responseHeaders[.contentType] = "text/event-stream"
        responseHeaders[.cacheControl] = "no-cache"
        responseHeaders[.connection] = "keep-alive"

        if needsTransformation {
            // Create a stateful transformer for this stream
            let transformer = ChatToResponsesStreamTransformer()

            var isFirstChunk = true

            // Create an async sequence that transforms and yields events
            let eventSequence = streamingResponse.events.map { (data: Data) -> ByteBuffer in
                if isFirstChunk {
                    isFirstChunk = false
                    if let raw = String(data: data, encoding: .utf8) {
                        NSLog("[CodexRouter] First raw upstream chunk: \(raw.prefix(500))")
                    }
                }
                if let transformedData = await transformer.transform(data) {
                    if let transformed = String(data: transformedData, encoding: .utf8) {
                        NSLog("[CodexRouter] Transformed output: \(transformed.prefix(500))")
                    }
                    return ByteBuffer(data: transformedData)
                } else {
                    if let raw = String(data: data, encoding: .utf8) {
                        NSLog("[CodexRouter] Transform returned nil, raw upstream: \(raw.prefix(500))")
                    }
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
            // Re-encode rectified json so reasoning changes are preserved
            do {
                let rectifiedData = try JSONSerialization.data(withJSONObject: json)
                let chatResponse = try JSONDecoder().decode(ChatCompletionResponse.self, from: rectifiedData)
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
                    // Convert Responses API content block types to Chat Completions types
                    let convertedContent = contentArray.compactMap { block -> [String: Any]? in
                        guard let type = block["type"] as? String else { return nil }
                        var newBlock = block
                        if type == "input_text" || type == "output_text" {
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

        // Handle instructions as system message (prepended before other messages)
        if let instructions = json["instructions"] as? String {
            var messages = (result["messages"] as? [[String: Any]]) ?? []
            messages.insert(["role": "system", "content": instructions], at: 0)
            result["messages"] = messages
            result.removeValue(forKey: "instructions")
        }

        // Handle developer role → system (most Chat APIs don't support "developer")
        if let messages = result["messages"] as? [[String: Any]] {
            result["messages"] = messages.map { msg in
                var m = msg
                if m["role"] as? String == "developer" { m["role"] = "system" }
                return m
            }
        }

        // Remove Responses API-only fields that upstream Chat APIs don't understand
        result.removeValue(forKey: "client_metadata")
        result.removeValue(forKey: "store")
        result.removeValue(forKey: "include")
        result.removeValue(forKey: "disable_response_storage")
        result.removeValue(forKey: "model_reasoning_effort")
        result.removeValue(forKey: "text")
        result.removeValue(forKey: "reasoning")
        result.removeValue(forKey: "verbosity")
        result.removeValue(forKey: "instructions")
        result.removeValue(forKey: "prompt_cache_key")

        // Convert tools from Responses API format to Chat Completions format.
        // Responses: {"type":"function","name":"...","description":"...","parameters":{...}}
        // Chat: {"type":"function","function":{"name":"...","description":"...","parameters":{...}}}
        // Following cc-switch's transform_codex_chat.rs:1095-1130
        if let tools = result["tools"] as? [[String: Any]] {
            result["tools"] = tools.flatMap { tool -> [[String: Any]] in
                convertToolToChat(tool)
            }
        }

        // Rename max_output_tokens to max_tokens
        if let maxOutputTokens = json["max_output_tokens"] {
            result["max_tokens"] = maxOutputTokens
            result.removeValue(forKey: "max_output_tokens")
        }

        return result
    }

    /// Convert a Responses API tool to Chat Completions format.
    /// Following cc-switch's transform_codex_chat.rs approach.
    private func convertToolToChat(_ tool: [String: Any]) -> [[String: Any]] {
        guard let type = tool["type"] as? String else { return [] }

        switch type {
        case "function":
            // Already has function wrapper → pass through
            if tool["function"] != nil { return [tool] }
            // Flat Responses format → wrap in function
            var t = tool
            var function: [String: Any] = [:]
            if let name = t.removeValue(forKey: "name") { function["name"] = name }
            if let desc = t.removeValue(forKey: "description") { function["description"] = desc }
            if let params = t.removeValue(forKey: "parameters") { function["parameters"] = params }
            if let strict = t.removeValue(forKey: "strict") { function["strict"] = strict }
            t["function"] = function
            return [t]

        case "custom":
            // Custom tools become function tools with an "input" string param
            let toolName = (tool["name"] as? String) ?? "custom_tool"
            let toolDesc: String
            if let data = try? JSONSerialization.data(withJSONObject: tool, options: .prettyPrinted),
               let jsonStr = String(data: data, encoding: .utf8) {
                toolDesc = "Custom tool: \(toolName)\n\nOriginal tool definition:\n\(jsonStr)"
            } else {
                toolDesc = "Custom tool: \(toolName)"
            }
            return [[
                "type": "function",
                "function": [
                    "name": toolName,
                    "description": toolDesc,
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "input": [
                                "type": "string",
                                "description": "The input to pass to the custom tool"
                            ]
                        ],
                        "required": ["input"]
                    ]
                ]
            ]]

        case "namespace":
            // Flatten namespace: convert each child tool, prefixing names
            guard let children = tool["tools"] as? [[String: Any]] else { return [] }
            let namespace = (tool["name"] as? String) ?? ""
            return children.flatMap { child -> [[String: Any]] in
                let converted = convertToolToChat(child)
                return converted.map { c in
                    var ct = c
                    if var funcObj = ct["function"] as? [String: Any],
                       let name = funcObj["name"] as? String {
                        let prefix = namespace.isEmpty ? "" : "\(namespace)__"
                        funcObj["name"] = "\(prefix)\(name)"
                        ct["function"] = funcObj
                    }
                    return ct
                }
            }

        case "tool_search":
            // Web search → function tool with query + limit params
            return [[
                "type": "function",
                "function": [
                    "name": "tool_search",
                    "description": "Search the web for information",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "query": [
                                "type": "string",
                                "description": "The search query"
                            ],
                            "limit": [
                                "type": "integer",
                                "description": "Max number of results"
                            ]
                        ],
                        "required": ["query"]
                    ]
                ]
            ]]

        default:
            return []
        }
    }
}
