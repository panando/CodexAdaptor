import Foundation
import NIOCore

// MARK: - SSE Parser

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
/// Handles both \n\n and \r\n\r\n delimiters.
public struct SSEParser: Sendable {
    public init() {}

    public func parse(_ data: Data) -> [SSEEvent] {
        guard let string = String(data: data, encoding: .utf8) else { return [] }
        var events: [SSEEvent] = []
        var currentId: String?
        var currentEvent: String?
        var currentData = ""

        for line in string.components(separatedBy: .newlines) {
            let trimmed = line.hasSuffix("\r") ? String(line.dropLast()) : line
            if trimmed.isEmpty {
                if !currentData.isEmpty {
                    events.append(SSEEvent(id: currentId, event: currentEvent, data: currentData))
                }
                currentId = nil
                currentEvent = nil
                currentData = ""
            } else if trimmed.hasPrefix("id:") {
                currentId = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("event:") {
                currentEvent = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("data:") {
                let value = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                currentData = currentData.isEmpty ? value : currentData + "\n" + value
            }
        }

        if !currentData.isEmpty {
            events.append(SSEEvent(id: currentId, event: currentEvent, data: currentData))
        }
        return events
    }
}

// MARK: - State

/// Accumulated output item for response.completed.
public struct OutputItemEntry: Sendable {
    public let itemId: String
    public let outputIndex: Int
    public let type: String
    public var text: String = ""
    public var arguments: String = ""
    public var callId: String = ""
    public var name: String = ""

    public func asJSON() -> [String: Any] {
        var item: [String: Any] = ["id": itemId, "status": "completed", "type": type]
        switch type {
        case "reasoning":
            item["summary"] = [[
                "type": "summary_text",
                "text": text
            ]]
        case "message":
            item["role"] = "assistant"
            item["content"] = [[
                "type": "output_text",
                "text": text,
                "annotations": []
            ]]
        case "function_call":
            item["call_id"] = callId
            item["name"] = name
            item["arguments"] = arguments
        default:
            break
        }
        return item
    }
}

public struct ChatToResponsesState: Sendable {
    public var responseStarted = false
    public var responseId = "resp_codexrouter"
    public var model = ""
    public var nextOutputIndex = 0
    public var textItemId: String?
    public var textItemAdded = false
    public var accumulatedText = ""
    public var reasoningItemId: String?
    public var reasoningItemAdded = false
    public var reasoningPartAdded = false
    public var accumulatedReasoning = ""
    public var toolCalls: [Int: ToolCallState] = [:]
    public var latestUsage: [String: Any]?
    public var finishReason: String?
    public var responseCompleted = false
    public var hasError = false
    /// Completed output items for the response.completed event
    public var completedItems: [OutputItemEntry] = []

    public struct ToolCallState: Sendable {
        public var itemId = ""
        public var callId = ""
        public var name = ""
        public var arguments = ""
        public var added = false
        public var outputIndex = 0
    }

    public init() {}
}

// MARK: - Transformer

/// Stateful stream transformer for Chat Completions to Responses API format.
/// Event lifecycle follows cc-switch's streaming_codex_chat.rs.
public actor ChatToResponsesStreamTransformer {
    private var state = ChatToResponsesState()
    private let parser = SSEParser()

    public init() {}

    /// Signal end of stream. Returns final events if response.completed not yet sent.
    public func finish() -> Data? {
        guard !state.responseCompleted else { return nil }
        finalizeAllOpenItems()
        state.responseCompleted = true
        var events: [String] = []
        if state.hasError {
            events.append(createResponseFailedEvent())
        } else {
            events.append(createResponseCompletedEvent())
        }
        events.append("data: [DONE]\n\n")
        return events.joined().data(using: .utf8)
    }

    public func transform(_ data: Data) -> Data? {
        let events = parser.parse(data)
        var outputEvents: [String] = []

        for event in events {
            guard !event.data.isEmpty, event.data != "[DONE]" else {
                if event.data == "[DONE]" {
                    finalizeAllOpenItems()
                    let completed = state.hasError
                        ? createResponseFailedEvent()
                        : createResponseCompletedEvent()
                    outputEvents.append(completed)
                    outputEvents.append("data: [DONE]\n\n")
                    state.responseCompleted = true
                }
                continue
            }

            guard let jsonData = event.data.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                continue
            }

            // Check for upstream error in SSE data
            if detectAndHandleError(json, events: &outputEvents) {
                state.responseCompleted = true
                outputEvents.append("data: [DONE]\n\n")
                continue
            }

            let responsesEvents = processChatChunk(json)
            outputEvents.append(contentsOf: responsesEvents)
        }

        guard !outputEvents.isEmpty else { return nil }
        return outputEvents.joined().data(using: .utf8)
    }

    /// Detect upstream error in SSE data and generate response.failed event.
    /// Following cc-switch's error handling in streaming_codex_chat.rs.
    private func detectAndHandleError(_ json: [String: Any], events: inout [String]) -> Bool {
        // Direct error field
        if let error = json["error"] as? [String: Any] {
            let errType = error["type"] as? String ?? "server_error"
            let message = error["message"] as? String ?? "Unknown error"
            // Ensure response lifecycle events are sent before error
            if !state.responseStarted {
                state.responseStarted = true
                events.append(createResponseCreatedEvent())
                events.append(createResponseInProgressEvent())
            }
            events.append(createResponseFailedEvent(message: message, code: errType))
            state.hasError = true
            return true
        }
        // Error field that's a string
        if let errMsg = json["error"] as? String {
            if !state.responseStarted {
                state.responseStarted = true
                events.append(createResponseCreatedEvent())
                events.append(createResponseInProgressEvent())
            }
            events.append(createResponseFailedEvent(message: errMsg, code: "server_error"))
            state.hasError = true
            return true
        }
        return false
    }

    // MARK: - Chunk Processing

    private func processChatChunk(_ chunk: [String: Any]) -> [String] {
        var events: [String] = []

        if let id = chunk["id"] as? String { state.responseId = "resp_\(id)" }
        if let model = chunk["model"] as? String, !model.isEmpty { state.model = model }

        if !state.responseStarted {
            state.responseStarted = true
            events.append(createResponseCreatedEvent())
            events.append(createResponseInProgressEvent())
        }

        if let usage = chunk["usage"] as? [String: Any] {
            state.latestUsage = convertUsage(usage)
        }

        guard let choices = chunk["choices"] as? [[String: Any]],
              let choice = choices.first else { return events }

        // Process delta content
        if let delta = choice["delta"] as? [String: Any] {
            // Reasoning: check multiple formats (reasoning_content, reasoning string/object)
            let reasoningText = extractReasoning(delta)
            if let r = reasoningText, !r.isEmpty {
                events.append(contentsOf: processReasoningDelta(r))
            }

            // Text content
            if let content = delta["content"] as? String, !content.isEmpty {
                events.append(contentsOf: processContentDelta(content))
            }

            // Tool calls
            if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
                events.append(contentsOf: processToolCallsDelta(toolCalls))
            }
        }

        // Finish reason — close all open items
        if let fr = choice["finish_reason"] as? String {
            state.finishReason = fr
            finalizeAllOpenItems(events: &events)
        }

        return events
    }

    /// Extract reasoning text from multiple possible formats (following cc-switch's codex_chat_common.rs).
    private func extractReasoning(_ delta: [String: Any]) -> String? {
        // reasoning_content string
        if let rc = delta["reasoning_content"] as? String, !rc.isEmpty { return rc }
        // reasoning string
        if let r = delta["reasoning"] as? String, !r.isEmpty { return r }
        // reasoning object (OpenRouter)
        if let rObj = delta["reasoning"] as? [String: Any] {
            return (rObj["content"] as? String) ?? (rObj["text"] as? String) ?? (rObj["summary"] as? String)
        }
        // reasoning_details array
        if let details = delta["reasoning_details"] as? [[String: Any]] {
            return details.compactMap { ($0["text"] as? String) ?? ($0["content"] as? String) }.joined()
        }
        return nil
    }

    // MARK: - Reasoning Delta

    private func processReasoningDelta(_ delta: String) -> [String] {
        var events: [String] = []

        if !state.reasoningItemAdded {
            let itemId = "rs_\(state.responseId)"
            state.reasoningItemId = itemId
            state.reasoningItemAdded = true
            let oi = state.nextOutputIndex; state.nextOutputIndex += 1
            // output_item.added for reasoning (with summary array)
            events.append(createOutputItemAdded(itemId: itemId, outputIndex: oi, type: "reasoning", extra: ["summary": [] as [Any]]))
        }

        if !state.reasoningPartAdded {
            state.reasoningPartAdded = true
            let oi = state.nextOutputIndex - 1
            // reasoning_summary_part.added
            events.append(sseEvent("response.reasoning_summary_part.added", [
                "type": "response.reasoning_summary_part.added",
                "item_id": state.reasoningItemId!,
                "output_index": oi,
                "summary_index": 0,
                "part": ["type": "summary_text", "text": ""]
            ]))
        }

        // reasoning_summary_text.delta
        if let itemId = state.reasoningItemId {
            let oi = state.nextOutputIndex - 1
            events.append(sseEvent("response.reasoning_summary_text.delta", [
                "type": "response.reasoning_summary_text.delta",
                "item_id": itemId,
                "output_index": oi,
                "delta": delta
            ]))
            state.accumulatedReasoning += delta
        }

        return events
    }

    // MARK: - Content Delta

    private func processContentDelta(_ delta: String) -> [String] {
        var events: [String] = []

        // Close reasoning first
        closeReasoning(events: &events)

        // Create text item if needed
        if !state.textItemAdded {
            let itemId = "text_\(state.responseId)"
            state.textItemId = itemId
            state.textItemAdded = true
            let oi = state.nextOutputIndex; state.nextOutputIndex += 1
            // output_item.added for message with role and content array
            events.append(createOutputItemAdded(itemId: itemId, outputIndex: oi, type: "message", extra: [
                "role": "assistant",
                "content": [] as [Any]
            ]))
            // content_part.added
            events.append(sseEvent("response.content_part.added", [
                "type": "response.content_part.added",
                "item_id": itemId,
                "output_index": oi,
                "content_index": 0,
                "part": ["type": "output_text", "text": "", "annotations": []]
            ]))
        }

        // output_text.delta
        if let itemId = state.textItemId {
            let oi = state.nextOutputIndex - 1
            events.append(sseEvent("response.output_text.delta", [
                "type": "response.output_text.delta",
                "item_id": itemId,
                "output_index": oi,
                "content_index": 0,
                "delta": delta
            ]))
            state.accumulatedText += delta
        }

        return events
    }

    private func closeReasoning(events: inout [String]) {
        guard state.reasoningItemAdded, let itemId = state.reasoningItemId else { return }
        let oi = state.nextOutputIndex - 1
        // Close reasoning part
        if state.reasoningPartAdded {
            events.append(sseEvent("response.reasoning_summary_text.done", [
                "type": "response.reasoning_summary_text.done",
                "item_id": itemId,
                "output_index": oi,
                "summary_index": 0,
                "text": state.accumulatedReasoning
            ]))
            events.append(sseEvent("response.reasoning_summary_part.done", [
                "type": "response.reasoning_summary_part.done",
                "item_id": itemId,
                "output_index": oi,
                "summary_index": 0
            ]))
            state.reasoningPartAdded = false
        }
        // Close reasoning item
        events.append(createOutputItemDone(itemId: itemId, outputIndex: oi, type: "reasoning"))
        // Record completed reasoning item
        trackCompletedItem(itemId: itemId, outputIndex: oi, type: "reasoning", text: state.accumulatedReasoning)
        state.reasoningItemAdded = false
        state.reasoningItemId = nil
    }

    // MARK: - Tool Calls Delta

    private func processToolCallsDelta(_ toolCalls: [[String: Any]]) -> [String] {
        var events: [String] = []

        // Close text item first
        closeTextItem(events: &events)

        for tc in toolCalls {
            guard let index = tc["index"] as? Int else { continue }

            if state.toolCalls[index] == nil {
                var ts = ChatToResponsesState.ToolCallState()
                ts.itemId = "fc_\(state.responseId)_\(index)"
                ts.outputIndex = state.nextOutputIndex
                state.nextOutputIndex += 1
                state.toolCalls[index] = ts
            }

            var ts = state.toolCalls[index]!

            if let function = tc["function"] as? [String: Any] {
                if let n = function["name"] as? String { ts.name = n }
                if let a = function["arguments"] as? String { ts.arguments += a }
            }
            if let cid = tc["id"] as? String { ts.callId = cid }

            // Defer output_item.added until we have both id and name (cc-switch pattern)
            if !ts.added, !ts.callId.isEmpty, !ts.name.isEmpty {
                ts.added = true
                events.append(createOutputItemAdded(itemId: ts.itemId, outputIndex: ts.outputIndex, type: "function_call", extra: [
                    "call_id": ts.callId,
                    "name": ts.name,
                    "arguments": "",
                    "status": "in_progress"
                ]))
                // Initial arguments delta if we already have some
                if !ts.arguments.isEmpty {
                    events.append(sseEvent("response.function_call_arguments.delta", [
                        "type": "response.function_call_arguments.delta",
                        "item_id": ts.itemId,
                        "output_index": ts.outputIndex,
                        "delta": ts.arguments
                    ]))
                    ts.arguments = ""
                }
            } else if ts.added, !ts.arguments.isEmpty {
                // Subsequent arguments delta
                events.append(sseEvent("response.function_call_arguments.delta", [
                    "type": "response.function_call_arguments.delta",
                    "item_id": ts.itemId,
                    "output_index": ts.outputIndex,
                    "delta": ts.arguments
                ]))
                ts.arguments = ""
            }

            state.toolCalls[index] = ts
        }

        return events
    }

    private func closeTextItem(events: inout [String]) {
        guard state.textItemAdded, let itemId = state.textItemId else { return }
        let oi = state.nextOutputIndex - 1
        // output_text.done
        events.append(sseEvent("response.output_text.done", [
            "type": "response.output_text.done",
            "item_id": itemId,
            "output_index": oi,
            "content_index": 0,
            "text": state.accumulatedText
        ]))
        // content_part.done
        events.append(sseEvent("response.content_part.done", [
            "type": "response.content_part.done",
            "item_id": itemId,
            "output_index": oi,
            "content_index": 0
        ]))
        // output_item.done
        events.append(createOutputItemDone(itemId: itemId, outputIndex: oi, type: "message"))
        // Record completed text item
        trackCompletedItem(itemId: itemId, outputIndex: oi, type: "message", text: state.accumulatedText)
        state.textItemAdded = false
        state.textItemId = nil
    }

    // MARK: - Finalization

    private func finalizeAllOpenItems(events: inout [String]) {
        closeReasoning(events: &events)
        closeTextItem(events: &events)
        // Close any open tool calls with function_call_arguments.done + output_item.done
        for (_, var ts) in state.toolCalls {
            if ts.added {
                events.append(sseEvent("response.function_call_arguments.done", [
                    "type": "response.function_call_arguments.done",
                    "item_id": ts.itemId,
                    "output_index": ts.outputIndex,
                    "arguments": ts.arguments
                ]))
                events.append(createOutputItemDone(itemId: ts.itemId, outputIndex: ts.outputIndex, type: "function_call"))
                trackCompletedItem(itemId: ts.itemId, outputIndex: ts.outputIndex, type: "function_call", arguments: ts.arguments, callId: ts.callId, name: ts.name)
                ts.added = false
            }
        }
    }

    private func finalizeAllOpenItems() {
        var dummy: [String] = []
        finalizeAllOpenItems(events: &dummy)
    }

    // MARK: - Event Builders

    private func createResponseCreatedEvent() -> String {
        sseEvent("response.created", [
            "type": "response.created",
            "response": [
                "id": state.responseId,
                "object": "response",
                "created_at": Int(Date().timeIntervalSince1970),
                "status": "in_progress",
                "model": state.model,
                "output": []
            ]
        ])
    }

    private func createResponseInProgressEvent() -> String {
        sseEvent("response.in_progress", [
            "type": "response.in_progress",
            "response": [
                "id": state.responseId,
                "object": "response",
                "status": "in_progress",
                "model": state.model,
                "output": []
            ]
        ])
    }

    private func createResponseFailedEvent(message: String = "Unknown error", code: String = "server_error") -> String {
        sseEvent("response.failed", [
            "type": "response.failed",
            "response": [
                "id": state.responseId,
                "object": "response",
                "status": "failed",
                "model": state.model,
                "output": []
            ],
            "error": [
                "type": code,
                "message": message
            ]
        ])
    }

    private func createResponseCompletedEvent() -> String {
        var usage: [String: Any] = ["input_tokens": 0, "output_tokens": 0, "total_tokens": 0]
        if let u = state.latestUsage { usage = u }

        // Build output items from state, sorted by output_index
        var items = state.completedItems
        // Add any still-open items that weren't recorded
        if state.reasoningItemAdded, let id = state.reasoningItemId {
            items.append(OutputItemEntry(itemId: id, outputIndex: state.nextOutputIndex - 1, type: "reasoning", text: state.accumulatedReasoning))
        }
        if state.textItemAdded, let id = state.textItemId {
            items.append(OutputItemEntry(itemId: id, outputIndex: state.nextOutputIndex - 1, type: "message", text: state.accumulatedText))
        }
        for (_, ts) in state.toolCalls where ts.added {
            items.append(OutputItemEntry(itemId: ts.itemId, outputIndex: ts.outputIndex, type: "function_call", arguments: ts.arguments, callId: ts.callId, name: ts.name))
        }
        let outputItems = items.sorted { $0.outputIndex < $1.outputIndex }.map { $0.asJSON() }
        NSLog("[CodexRouter] response.completed with \(outputItems.count) output items")

        return sseEvent("response.completed", [
            "type": "response.completed",
            "response": [
                "id": state.responseId,
                "object": "response",
                "created_at": Int(Date().timeIntervalSince1970),
                "status": "completed",
                "model": state.model,
                "output": outputItems,
                "usage": usage
            ]
        ])
    }

    private func createOutputItemAdded(itemId: String, outputIndex: Int, type: String, extra: [String: Any] = [:]) -> String {
        var item: [String: Any] = ["id": itemId, "type": type, "status": "in_progress"]
        for (k, v) in extra { item[k] = v }
        return sseEvent("response.output_item.added", [
            "type": "response.output_item.added",
            "output_index": outputIndex,
            "item": item
        ])
    }

    private func createOutputItemDone(itemId: String, outputIndex: Int, type: String) -> String {
        sseEvent("response.output_item.done", [
            "type": "response.output_item.done",
            "output_index": outputIndex,
            "item": ["id": itemId, "type": type, "status": "completed"]
        ])
    }

    /// Track a completed output item for the response.completed event.
    /// Uses a separate array (not inout) to avoid Swift COW issues with nested struct mutation.
    private func trackCompletedItem(itemId: String, outputIndex: Int, type: String, text: String = "", arguments: String = "", callId: String = "", name: String = "") {
        var entry = OutputItemEntry(itemId: itemId, outputIndex: outputIndex, type: type)
        entry.text = text
        entry.arguments = arguments
        entry.callId = callId
        entry.name = name
        var items = state.completedItems
        items.append(entry)
        state.completedItems = items
    }

    // MARK: - Helpers

    private func sseEvent(_ event: String, _ data: [String: Any]) -> String {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: data),
              let jsonStr = String(data: jsonData, encoding: .utf8) else { return "" }
        return "event: \(event)\ndata: \(jsonStr)\n\n"
    }

    private func convertUsage(_ usage: [String: Any]) -> [String: Any] {
        let input = usage["prompt_tokens"] as? Int ?? 0
        let output = usage["completion_tokens"] as? Int ?? 0
        let total = usage["total_tokens"] as? Int ?? (input + output)
        var result: [String: Any] = [
            "input_tokens": input,
            "output_tokens": output,
            "total_tokens": total
        ]
        // Include reasoning_tokens if available
        if let rt = usage["completion_tokens_details"] as? [String: Any],
           let reasoningTokens = rt["reasoning_tokens"] as? Int {
            result["output_tokens_details"] = ["reasoning_tokens": reasoningTokens]
        }
        return result
    }
}

// MARK: - Deprecated (kept for compat)

public struct SSEStreamTransformer: Sendable {
    private let parser: SSEParser
    public init() { self.parser = SSEParser() }

    @available(*, deprecated, message: "Use ChatToResponsesStreamTransformer for stateful transformation")
    public func transformChatToResponsesStream(_ data: Data) -> Data? { nil }
}
