import Foundation
import NIOCore

/// SSE event structure.
public struct SSEEvent: Sendable {
    public var id: String?
    public var event: String?
    public var data: String

    public init(id: String? = nil, event: String? = nil, data: String) {
        self.id = id
        self.event = event
        self.data = data
    }
}

/// Parses Server-Sent Events from a byte stream.
public struct SSEParser: Sendable {

    public init() {}

    /// Parse SSE events from data.
    public func parse(_ data: Data) -> [SSEEvent] {
        var events: [SSEEvent] = []
        guard let string = String(data: data, encoding: .utf8) else {
            return events
        }

        var currentId: String?
        var currentEvent: String?
        var currentData: String = ""

        let lines = string.components(separatedBy: "\n")

        for line in lines {
            if line.isEmpty {
                // Empty line signals end of event
                if !currentData.isEmpty {
                    events.append(SSEEvent(
                        id: currentId,
                        event: currentEvent,
                        data: currentData
                    ))
                }
                currentId = nil
                currentEvent = nil
                currentData = ""
            } else if line.hasPrefix("id:") {
                currentId = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("event:") {
                currentEvent = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                let dataLine = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                if currentData.isEmpty {
                    currentData = dataLine
                } else {
                    currentData += "\n" + dataLine
                }
            }
        }

        // Handle last event if no trailing empty line
        if !currentData.isEmpty {
            events.append(SSEEvent(
                id: currentId,
                event: currentEvent,
                data: currentData
            ))
        }

        return events
    }
}

/// State for Chat Completions to Responses API stream transformation.
public struct ChatToResponsesState: Sendable {
    public var responseStarted: Bool = false
    public var responseId: String = "resp_codexrouter"
    public var model: String = ""
    public var nextOutputIndex: Int = 0
    public var textItemId: String?
    public var textItemAdded: Bool = false
    public var reasoningItemId: String?
    public var reasoningItemAdded: Bool = false
    public var toolCalls: [Int: ToolCallState] = [:]
    public var latestUsage: [String: Any]?
    public var finishReason: String?
    public var responseCompleted: Bool = false

    public struct ToolCallState: Sendable {
        public var itemId: String = ""
        public var callId: String = ""
        public var name: String = ""
        public var arguments: String = ""
        public var added: Bool = false
    }

    public init() {}
}

/// Stateful stream transformer for Chat Completions to Responses API format.
/// Following cc-switch's approach for proper Responses API lifecycle events.
public actor ChatToResponsesStreamTransformer {
    private var state: ChatToResponsesState = ChatToResponsesState()
    private let parser: SSEParser = SSEParser()

    public init() {}

    /// Signal the end of the stream. Returns final events (response.completed + [DONE])
    /// if they haven't been sent already.
    public func finish() -> Data? {
        guard !state.responseCompleted else { return nil }
        state.responseCompleted = true
        var events: [String] = []
        events.append(createResponseCompletedEvent(state: state))
        events.append("data: [DONE]\n\n")
        return events.joined().data(using: .utf8)
    }

    /// Transform a chunk of Chat Completions SSE data to Responses API format.
    public func transform(_ data: Data) -> Data? {
        let events = parser.parse(data)

        var outputEvents: [String] = []

        for event in events {
            // Skip [DONE] marker
            guard !event.data.isEmpty, event.data != "[DONE]" else {
                if event.data == "[DONE]" {
                    // Send response.completed event
                    let completedEvent = createResponseCompletedEvent(state: state)
                    outputEvents.append(completedEvent)
                    outputEvents.append("data: [DONE]\n\n")
                    state.responseCompleted = true
                }
                continue
            }

            guard let jsonData = event.data.data(using: .utf8),
                  let chatChunk = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                continue
            }

            // Process the chat chunk and generate Responses API events
            let responsesEvents = processChatChunk(chatChunk)
            outputEvents.append(contentsOf: responsesEvents)
        }

        guard !outputEvents.isEmpty else { return nil }
        return outputEvents.joined().data(using: .utf8)
    }

    /// Process a single Chat Completions chunk and generate Responses API events.
    private func processChatChunk(_ chunk: [String: Any]) -> [String] {
        var events: [String] = []

        // Extract response ID and model
        if let id = chunk["id"] as? String {
            state.responseId = "resp_\(id)"
        }
        if let model = chunk["model"] as? String, !model.isEmpty {
            state.model = model
        }

        // Send response.created if not started
        if !state.responseStarted {
            state.responseStarted = true
            events.append(createResponseCreatedEvent(state: state))
            events.append(createResponseInProgressEvent(state: state))
        }

        // Extract usage if present
        if let usage = chunk["usage"] as? [String: Any] {
            state.latestUsage = convertUsage(usage)
        }

        // Process choices
        guard let choices = chunk["choices"] as? [[String: Any]],
              let choice = choices.first else {
            return events
        }

        if let delta = choice["delta"] as? [String: Any] {
            // Handle reasoning_content (DeepSeek style)
            if let reasoning = delta["reasoning_content"] as? String, !reasoning.isEmpty {
                events.append(contentsOf: processReasoningDelta(reasoning))
            }

            // Handle regular content
            if let content = delta["content"] as? String, !content.isEmpty {
                events.append(contentsOf: processContentDelta(content))
            }

            // Handle tool calls
            if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
                events.append(contentsOf: processToolCallsDelta(toolCalls))
            }
        }

        // Handle finish reason — close all open output items before stream ends
        if let finishReason = choice["finish_reason"] as? String {
            state.finishReason = finishReason
            // Finalize text item if open
            if state.textItemAdded, let itemId = state.textItemId {
                let outputIndex = state.nextOutputIndex - 1
                events.append(createContentPartDoneEvent(itemId: itemId, outputIndex: outputIndex))
                events.append(createOutputItemDoneEvent(itemId: itemId, outputIndex: outputIndex, type: "message"))
                state.textItemAdded = false
                state.textItemId = nil
            }
            // Finalize reasoning item if still open (no text content followed)
            if state.reasoningItemAdded, let itemId = state.reasoningItemId {
                let outputIndex = state.nextOutputIndex - 1
                events.append(createOutputItemDoneEvent(itemId: itemId, outputIndex: outputIndex, type: "reasoning"))
                state.reasoningItemAdded = false
                state.reasoningItemId = nil
            }
            // Finalize any open tool call items
            for (index, var toolState) in state.toolCalls {
                if toolState.added {
                    let outputIndex = state.nextOutputIndex - 1
                    events.append(createOutputItemDoneEvent(itemId: toolState.itemId, outputIndex: outputIndex, type: "function_call"))
                    toolState.added = false
                    state.toolCalls[index] = toolState
                }
            }
        }

        return events
    }

    /// Process reasoning content delta.
    private func processReasoningDelta(_ delta: String) -> [String] {
        var events: [String] = []

        // Create reasoning item if not exists
        if !state.reasoningItemAdded {
            let itemId = "rs_\(state.responseId)"
            state.reasoningItemId = itemId
            state.reasoningItemAdded = true

            let outputIndex = state.nextOutputIndex
            state.nextOutputIndex += 1

            events.append(createOutputItemAddedEvent(
                itemId: itemId,
                outputIndex: outputIndex,
                type: "reasoning"
            ))
        }

        // Send reasoning delta
        if let itemId = state.reasoningItemId {
            let outputIndex = state.nextOutputIndex - 1
            events.append(createReasoningDeltaEvent(
                itemId: itemId,
                outputIndex: outputIndex,
                delta: delta
            ))
        }

        return events
    }

    /// Process regular text content delta.
    private func processContentDelta(_ delta: String) -> [String] {
        var events: [String] = []

        // Finalize reasoning if active
        if state.reasoningItemAdded, let itemId = state.reasoningItemId {
            let outputIndex = state.nextOutputIndex - 1
            events.append(createOutputItemDoneEvent(itemId: itemId, outputIndex: outputIndex, type: "reasoning"))
            state.reasoningItemAdded = false
        }

        // Create text item if not exists
        if !state.textItemAdded {
            let itemId = "text_\(state.responseId)"
            state.textItemId = itemId
            state.textItemAdded = true

            let outputIndex = state.nextOutputIndex
            state.nextOutputIndex += 1

            events.append(createOutputItemAddedEvent(
                itemId: itemId,
                outputIndex: outputIndex,
                type: "message"
            ))
            events.append(createContentPartAddedEvent(itemId: itemId, outputIndex: outputIndex))
        }

        // Send text delta
        if let itemId = state.textItemId {
            let outputIndex = state.nextOutputIndex - 1
            events.append(createOutputTextDeltaEvent(
                itemId: itemId,
                outputIndex: outputIndex,
                delta: delta
            ))
        }

        return events
    }

    /// Process tool calls delta.
    private func processToolCallsDelta(_ toolCalls: [[String: Any]]) -> [String] {
        var events: [String] = []

        // Finalize text item if active
        if state.textItemAdded, let itemId = state.textItemId {
            let outputIndex = state.nextOutputIndex - 1
            events.append(createContentPartDoneEvent(itemId: itemId, outputIndex: outputIndex))
            events.append(createOutputItemDoneEvent(itemId: itemId, outputIndex: outputIndex, type: "message"))
            state.textItemAdded = false
        }

        for toolCall in toolCalls {
            guard let index = toolCall["index"] as? Int else { continue }

            // Initialize tool call state if needed
            if state.toolCalls[index] == nil {
                state.toolCalls[index] = ChatToResponsesState.ToolCallState()
            }

            var toolState = state.toolCalls[index]!

            // Extract function info
            if let function = toolCall["function"] as? [String: Any] {
                if let name = function["name"] as? String {
                    toolState.name = name
                }
                if let arguments = function["arguments"] as? String {
                    toolState.arguments += arguments
                }
            }

            // Extract call_id
            if let callId = toolCall["id"] as? String {
                toolState.callId = callId
            }

            // Create tool item if not added
            if !toolState.added {
                let itemId = "fc_\(state.responseId)_\(index)"
                toolState.itemId = itemId
                toolState.added = true

                let outputIndex = state.nextOutputIndex
                state.nextOutputIndex += 1

                events.append(createToolCallItemAddedEvent(
                    itemId: itemId,
                    outputIndex: outputIndex,
                    callId: toolState.callId,
                    name: toolState.name
                ))

                // Send initial arguments delta
                if !toolState.arguments.isEmpty {
                    events.append(createFunctionCallDeltaEvent(
                        itemId: itemId,
                        outputIndex: outputIndex,
                        delta: toolState.arguments
                    ))
                    toolState.arguments = "" // Clear after sending
                }
            } else {
                // Send arguments delta
                if !toolState.arguments.isEmpty {
                    let outputIndex = state.nextOutputIndex - 1
                    events.append(createFunctionCallDeltaEvent(
                        itemId: toolState.itemId,
                        outputIndex: outputIndex,
                        delta: toolState.arguments
                    ))
                    toolState.arguments = ""
                }
            }

            state.toolCalls[index] = toolState
        }

        return events
    }

    // MARK: - Event Creation Helpers

    private func createResponseCreatedEvent(state: ChatToResponsesState) -> String {
        let response: [String: Any] = [
            "id": state.responseId,
            "object": "response",
            "created_at": Int(Date().timeIntervalSince1970),
            "status": "in_progress",
            "model": state.model,
            "output": []
        ]
        let event: [String: Any] = [
            "type": "response.created",
            "response": response
        ]
        return createSSEEvent(event: "response.created", data: event)
    }

    private func createResponseInProgressEvent(state: ChatToResponsesState) -> String {
        let response: [String: Any] = [
            "id": state.responseId,
            "object": "response",
            "status": "in_progress",
            "model": state.model,
            "output": []
        ]
        let event: [String: Any] = [
            "type": "response.in_progress",
            "response": response
        ]
        return createSSEEvent(event: "response.in_progress", data: event)
    }

    private func createResponseCompletedEvent(state: ChatToResponsesState) -> String {
        var usage: [String: Any] = ["input_tokens": 0, "output_tokens": 0, "total_tokens": 0]
        if let latestUsage = state.latestUsage {
            usage = latestUsage
        }

        let response: [String: Any] = [
            "id": state.responseId,
            "object": "response",
            "created_at": Int(Date().timeIntervalSince1970),
            "status": "completed",
            "model": state.model,
            "output": [],
            "usage": usage
        ]
        let event: [String: Any] = [
            "type": "response.completed",
            "response": response
        ]
        return createSSEEvent(event: "response.completed", data: event)
    }

    private func createOutputItemAddedEvent(itemId: String, outputIndex: Int, type: String) -> String {
        let item: [String: Any] = [
            "id": itemId,
            "type": type,
            "status": "in_progress"
        ]
        let event: [String: Any] = [
            "type": "response.output_item.added",
            "output_index": outputIndex,
            "item": item
        ]
        return createSSEEvent(event: "response.output_item.added", data: event)
    }

    private func createContentPartAddedEvent(itemId: String, outputIndex: Int) -> String {
        let part: [String: Any] = [
            "type": "output_text",
            "text": ""
        ]
        let event: [String: Any] = [
            "type": "response.content_part.added",
            "item_id": itemId,
            "output_index": outputIndex,
            "content_index": 0,
            "part": part
        ]
        return createSSEEvent(event: "response.content_part.added", data: event)
    }

    private func createOutputTextDeltaEvent(itemId: String, outputIndex: Int, delta: String) -> String {
        let event: [String: Any] = [
            "type": "response.output_text.delta",
            "item_id": itemId,
            "output_index": outputIndex,
            "content_index": 0,
            "delta": delta
        ]
        return createSSEEvent(event: "response.output_text.delta", data: event)
    }

    private func createReasoningDeltaEvent(itemId: String, outputIndex: Int, delta: String) -> String {
        let event: [String: Any] = [
            "type": "response.reasoning_summary_text.delta",
            "item_id": itemId,
            "output_index": outputIndex,
            "delta": delta
        ]
        return createSSEEvent(event: "response.reasoning_summary_text.delta", data: event)
    }

    private func createContentPartDoneEvent(itemId: String, outputIndex: Int) -> String {
        let event: [String: Any] = [
            "type": "response.content_part.done",
            "item_id": itemId,
            "output_index": outputIndex,
            "content_index": 0
        ]
        return createSSEEvent(event: "response.content_part.done", data: event)
    }

    private func createOutputItemDoneEvent(itemId: String, outputIndex: Int, type: String) -> String {
        let item: [String: Any] = [
            "id": itemId,
            "type": type,
            "status": "completed"
        ]
        let event: [String: Any] = [
            "type": "response.output_item.done",
            "output_index": outputIndex,
            "item": item
        ]
        return createSSEEvent(event: "response.output_item.done", data: event)
    }

    private func createToolCallItemAddedEvent(itemId: String, outputIndex: Int, callId: String, name: String) -> String {
        let item: [String: Any] = [
            "id": itemId,
            "type": "function_call",
            "call_id": callId,
            "name": name,
            "arguments": "",
            "status": "in_progress"
        ]
        let event: [String: Any] = [
            "type": "response.output_item.added",
            "output_index": outputIndex,
            "item": item
        ]
        return createSSEEvent(event: "response.output_item.added", data: event)
    }

    private func createFunctionCallDeltaEvent(itemId: String, outputIndex: Int, delta: String) -> String {
        let event: [String: Any] = [
            "type": "response.function_call_arguments.delta",
            "item_id": itemId,
            "output_index": outputIndex,
            "delta": delta
        ]
        return createSSEEvent(event: "response.function_call_arguments.delta", data: event)
    }

    private func createSSEEvent(event: String, data: [String: Any]) -> String {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: data),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return ""
        }
        return "event: \(event)\ndata: \(jsonString)\n\n"
    }

    /// Convert Chat Completions usage to Responses API format.
    private func convertUsage(_ usage: [String: Any]) -> [String: Any] {
        let inputTokens = usage["prompt_tokens"] as? Int ?? 0
        let outputTokens = usage["completion_tokens"] as? Int ?? 0
        let totalTokens = usage["total_tokens"] as? Int ?? (inputTokens + outputTokens)

        return [
            "input_tokens": inputTokens,
            "output_tokens": outputTokens,
            "total_tokens": totalTokens
        ]
    }
}

/// Non-stateful transformer for simple transformations (kept for compatibility).
public struct SSEStreamTransformer: Sendable {
    private let parser: SSEParser

    public init() {
        self.parser = SSEParser()
    }

    /// Transform Chat Completions SSE stream to Responses API format.
    @available(*, deprecated, message: "Use ChatToResponsesStreamTransformer for stateful transformation")
    public func transformChatToResponsesStream(_ data: Data) -> Data? {
        let events = parser.parse(data)
        var state = ChatToResponsesState()
        var outputEvents: [String] = []

        for event in events {
            guard !event.data.isEmpty, event.data != "[DONE]" else {
                if event.data == "[DONE]" {
                    outputEvents.append("data: [DONE]\n\n")
                }
                continue
            }

            guard let jsonData = event.data.data(using: .utf8),
                  let chatChunk = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                continue
            }

            // Simple passthrough for deprecated method
            if let chunk = transformSimpleChunk(chatChunk) {
                outputEvents.append(chunk)
            }
        }

        guard !outputEvents.isEmpty else { return nil }
        return outputEvents.joined().data(using: .utf8)
    }

    private func transformSimpleChunk(_ chunk: [String: Any]) -> String? {
        var response: [String: Any] = [:]
        response["object"] = "response.chunk"

        if let id = chunk["id"] as? String {
            response["id"] = id
        }
        if let model = chunk["model"] as? String {
            response["model"] = model
        }

        guard let choices = chunk["choices"] as? [[String: Any]],
              let choice = choices.first,
              let delta = choice["delta"] as? [String: Any] else {
            return nil
        }

        var output: [String: Any] = [:]

        if let content = delta["content"] as? String, !content.isEmpty {
            output["type"] = "message"
            output["content"] = [["type": "output_text", "text": content]]
        }

        if let reasoning = delta["reasoning_content"] as? String, !reasoning.isEmpty {
            output["type"] = "reasoning"
            output["content"] = [["type": "reasoning_text", "text": reasoning]]
        }

        if output.isEmpty { return nil }

        response["output"] = [output]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: response),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return nil
        }

        return "data: \(jsonString)\n\n"
    }
}
