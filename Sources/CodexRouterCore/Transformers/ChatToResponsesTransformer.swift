import Foundation

/// Responses API output item.
public struct ResponsesOutputItem: Codable, Equatable {
    public var type: String
    public var id: String?
    public var name: String?
    public var arguments: String?
    public var content: [ResponsesContentBlock]?

    public init(type: String, id: String? = nil, name: String? = nil, arguments: String? = nil, content: [ResponsesContentBlock]? = nil) {
        self.type = type
        self.id = id
        self.name = name
        self.arguments = arguments
        self.content = content
    }
}

/// Responses API content block.
public struct ResponsesContentBlock: Codable, Equatable {
    public var type: String
    public var text: String?

    public init(type: String, text: String? = nil) {
        self.type = type
        self.text = text
    }
}

/// Responses API response.
public struct ResponsesAPIResponse: Codable, Equatable {
    public var id: String
    public var object: String
    public var createdAt: Int
    public var model: String
    public var output: [ResponsesOutputItem]
    public var usage: ResponsesUsage?

    public init(id: String, model: String, output: [ResponsesOutputItem], usage: ResponsesUsage? = nil) {
        self.id = id
        self.object = "response"
        self.createdAt = Int(Date().timeIntervalSince1970)
        self.model = model
        self.output = output
        self.usage = usage
    }
}

/// Responses API usage.
public struct ResponsesUsage: Codable, Equatable {
    public var inputTokens: Int
    public var outputTokens: Int

    public init(inputTokens: Int, outputTokens: Int) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

/// Transforms Chat Completions format to OpenAI Responses API format.
public struct ChatToResponsesTransformer {

    public init() {}

    public func transform(chatResponse: ChatCompletionResponse) -> ResponsesAPIResponse {
        var outputItems: [ResponsesOutputItem] = []

        for choice in chatResponse.choices {
            let message = choice.message

            // Handle tool calls
            if let toolCalls = message.toolCalls {
                for toolCall in toolCalls {
                    outputItems.append(ResponsesOutputItem(
                        type: "function_call",
                        id: toolCall.id,
                        name: toolCall.function.name,
                        arguments: toolCall.function.arguments
                    ))
                }
            } else if let content = message.content {
                // Handle text content
                outputItems.append(ResponsesOutputItem(
                    type: "message",
                    content: [ResponsesContentBlock(type: "output_text", text: content)]
                ))
            }
        }

        var usage: ResponsesUsage?
        if let chatUsage = chatResponse.usage {
            usage = ResponsesUsage(
                inputTokens: chatUsage.promptTokens,
                outputTokens: chatUsage.completionTokens
            )
        }

        return ResponsesAPIResponse(
            id: chatResponse.id,
            model: chatResponse.model,
            output: outputItems,
            usage: usage
        )
    }

    /// Transform request body from Chat Completions to Responses format.
    public func transformRequest(_ chatRequest: [String: Any]) -> [String: Any] {
        var response: [String: Any] = [:]

        // Copy model
        if let model = chatRequest["model"] {
            response["model"] = model
        }

        // Transform messages to input
        if let messages = chatRequest["messages"] as? [[String: Any]] {
            response["input"] = transformMessages(messages)
        }

        // Copy other parameters
        if let stream = chatRequest["stream"] {
            response["stream"] = stream
        }
        if let maxTokens = chatRequest["max_tokens"] {
            response["max_output_tokens"] = maxTokens
        }
        if let temperature = chatRequest["temperature"] {
            response["temperature"] = temperature
        }
        if let tools = chatRequest["tools"] {
            response["tools"] = tools
        }

        return response
    }

    private func transformMessages(_ messages: [[String: Any]]) -> [[String: Any]] {
        return messages.compactMap { message -> [String: Any]? in
            var input: [String: Any] = [:]

            if let role = message["role"] as? String {
                input["role"] = role
            }

            if let content = message["content"] as? String {
                input["content"] = [
                    ["type": "input_text", "text": content]
                ]
            } else if let contentArray = message["content"] as? [[String: Any]] {
                input["content"] = contentArray.map { block -> [String: Any] in
                    if let type = block["type"] as? String, let text = block["text"] as? String {
                        return ["type": type == "text" ? "input_text" : type, "text": text]
                    }
                    return block
                }
            }

            if let toolCalls = message["tool_calls"] as? [[String: Any]] {
                input["tool_calls"] = toolCalls
            }

            if let toolCallId = message["tool_call_id"] as? String {
                input["tool_call_id"] = toolCallId
            }

            return input.isEmpty ? nil : input
        }
    }
}
