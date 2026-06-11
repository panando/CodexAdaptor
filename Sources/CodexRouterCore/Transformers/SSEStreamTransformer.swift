import Foundation
import NIOCore

/// SSE event structure.
public struct SSEEvent {
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
public struct SSEParser {

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

/// Transforms streaming responses between Chat Completions and Responses API formats.
public struct SSEStreamTransformer {

    private let chatToResponses: ChatToResponsesTransformer
    private let responsesToChat: ResponsesToChatTransformer
    private let parser: SSEParser

    public init() {
        self.chatToResponses = ChatToResponsesTransformer()
        self.responsesToChat = ResponsesToChatTransformer()
        self.parser = SSEParser()
    }

    /// Transform Chat Completions SSE stream to Responses format.
    public func transformChatToResponsesStream(_ data: Data) -> Data? {
        let events = parser.parse(data)

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

            if let responsesChunk = transformChatChunkToResponses(chatChunk) {
                if let chunkData = try? JSONSerialization.data(withJSONObject: responsesChunk),
                   let chunkString = String(data: chunkData, encoding: .utf8) {
                    outputEvents.append("data: \(chunkString)\n\n")
                }
            }
        }

        guard !outputEvents.isEmpty else { return nil }
        return outputEvents.joined().data(using: .utf8)
    }

    /// Transform Responses SSE stream to Chat Completions format.
    public func transformResponsesToChatStream(_ data: Data) -> Data? {
        let events = parser.parse(data)

        var outputEvents: [String] = []

        for event in events {
            guard !event.data.isEmpty else { continue }

            guard let jsonData = event.data.data(using: .utf8),
                  let responsesChunk = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                continue
            }

            if let chatChunk = transformResponsesChunkToChat(responsesChunk) {
                if let chunkData = try? JSONSerialization.data(withJSONObject: chatChunk),
                   let chunkString = String(data: chunkData, encoding: .utf8) {
                    outputEvents.append("data: \(chunkString)\n\n")
                }
            }
        }

        guard !outputEvents.isEmpty else { return nil }
        return outputEvents.joined().data(using: .utf8)
    }

    private func transformChatChunkToResponses(_ chunk: [String: Any]) -> [String: Any]? {
        var response: [String: Any] = [:]

        if let id = chunk["id"] as? String {
            response["id"] = id
        }
        if let model = chunk["model"] as? String {
            response["model"] = model
        }

        if let choices = chunk["choices"] as? [[String: Any]] {
            var outputs: [[String: Any]] = []

            for choice in choices {
                if let delta = choice["delta"] as? [String: Any] {
                    var output: [String: Any] = [:]

                    if let content = delta["content"] as? String {
                        output["type"] = "message"
                        output["content"] = [
                            ["type": "output_text", "text": content]
                        ]
                    }

                    if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
                        for toolCall in toolCalls {
                            var tc = toolCall
                            tc["type"] = "function_call"
                            outputs.append(tc)
                        }
                    }

                    if !output.isEmpty {
                        outputs.append(output)
                    }
                }
            }

            if !outputs.isEmpty {
                response["output"] = outputs
            }
        }

        return response.isEmpty ? nil : response
    }

    private func transformResponsesChunkToChat(_ chunk: [String: Any]) -> [String: Any]? {
        var response: [String: Any] = [:]

        response["object"] = "chat.completion.chunk"

        if let id = chunk["id"] as? String {
            response["id"] = id
        }
        if let model = chunk["model"] as? String {
            response["model"] = model
        }

        response["created"] = Int(Date().timeIntervalSince1970)

        if let output = chunk["output"] as? [[String: Any]] {
            var choices: [[String: Any]] = []

            for item in output {
                var delta: [String: Any] = [:]

                if let type = item["type"] as? String {
                    if type == "message" {
                        if let content = item["content"] as? [[String: Any]] {
                            for block in content {
                                if let text = block["text"] as? String {
                                    delta["content"] = text
                                }
                            }
                        }
                    } else if type == "function_call" {
                        if let id = item["id"] as? String,
                           let name = item["name"] as? String,
                           let arguments = item["arguments"] as? String {
                            delta["tool_calls"] = [[
                                "index": 0,
                                "id": id,
                                "type": "function",
                                "function": [
                                    "name": name,
                                    "arguments": arguments
                                ]
                            ]]
                        }
                    }
                }

                if !delta.isEmpty {
                    choices.append([
                        "index": 0,
                        "delta": delta
                    ])
                }
            }

            if !choices.isEmpty {
                response["choices"] = choices
            }
        }

        return response.isEmpty ? nil : response
    }
}
