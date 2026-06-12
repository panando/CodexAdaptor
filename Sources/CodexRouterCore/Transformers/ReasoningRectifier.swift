import Foundation

/// Adapts reasoning parameters for different AI platforms.
public struct ReasoningRectifier: Sendable {

    public init() {}

    /// Rectify request parameters for a specific platform.
    /// Provider is optional since we now use simplified UpstreamProvider.
    public func rectifyRequest(
        _ request: inout [String: Any],
        provider: Provider?,
        platform: ReasoningPlatform
    ) {
        // If no provider config, use platform-based defaults
        guard let config = provider?.meta?.codexChatReasoning else {
            // Apply platform-specific defaults without config
            applyPlatformDefaults(&request, platform: platform)
            return
        }

        switch platform {
        case .deepseek:
            rectifyDeepSeek(&request, config: config)
        case .openrouter:
            rectifyOpenRouter(&request, config: config)
        case .siliconflow:
            rectifySiliconFlow(&request, config: config)
        case .kimi:
            rectifyKimi(&request, config: config)
        case .qwen:
            rectifyQwen(&request, config: config)
        case .minimax:
            rectifyMiniMax(&request, config: config)
        case .standard:
            break
        }
    }

    /// Rectify response for a specific platform.
    /// Provider is optional since we now use simplified UpstreamProvider.
    public func rectifyResponse(
        _ response: inout [String: Any],
        provider: Provider?,
        platform: ReasoningPlatform
    ) {
        // If no provider config, use platform-based defaults
        guard let config = provider?.meta?.codexChatReasoning else {
            // Apply platform-specific response transformation
            applyPlatformResponseDefaults(&response, platform: platform)
            return
        }

        // Handle output format transformation
        if let outputFormat = config.outputFormat {
            switch outputFormat {
            case "reasoning_content":
                transformReasoningContent(&response)
            case "reasoning_details":
                transformReasoningDetails(&response)
            default:
                break
            }
        }
    }

    /// Rectify request using a manual config instead of platform auto-detection.
    public func rectifyRequestWithConfig(_ request: inout [String: Any], config: ReasoningConfig) {
        // Apply thinking param
        if config.supportsThinking == true, let param = config.thinkingParam {
            // Remove common alternate params
            if param != "thinking" { request.removeValue(forKey: "thinking") }
            if param != "enable_thinking" { request.removeValue(forKey: "enable_thinking") }
            request[param] = true
        }

        // Apply effort
        if config.supportsEffort == true, let effort = request["effort"] as? String {
            request.removeValue(forKey: "effort")
            if let mode = config.effortValueMode {
                switch mode {
                case "deepseek":
                    if let param = config.effortParam {
                        request[param] = mapEffortValue(effort, mode: "deepseek")
                    } else {
                        request["reasoning_effort"] = effort
                    }
                case "openrouter":
                    request["reasoning"] = ["effort": effort]
                default:
                    request["reasoning_effort"] = effort
                }
            }
        }
    }

    /// Rectify response using a manual config.
    public func rectifyResponseWithConfig(_ response: inout [String: Any], config: ReasoningConfig) {
        if let outputFormat = config.outputFormat {
            switch outputFormat {
            case "reasoning_content":
                transformReasoningContent(&response)
            case "reasoning_details":
                transformReasoningDetails(&response)
            default:
                break
            }
        }
    }

    // MARK: - Platform-specific defaults (without config)

    private func applyPlatformDefaults(_ request: inout [String: Any], platform: ReasoningPlatform) {
        switch platform {
        case .deepseek:
            // DeepSeek default: enable thinking for reasoning models
            if request["thinking"] == nil {
                request["thinking"] = true
            }
        case .siliconflow, .qwen:
            // SiliconFlow/Qwen default: enable_thinking
            if request["thinking"] != nil || request["reasoning"] != nil {
                request.removeValue(forKey: "thinking")
                request.removeValue(forKey: "reasoning")
                request["enable_thinking"] = true
            }
        default:
            break
        }
    }

    private func applyPlatformResponseDefaults(_ response: inout [String: Any], platform: ReasoningPlatform) {
        switch platform {
        case .deepseek, .siliconflow, .qwen:
            // These platforms use reasoning_content
            transformReasoningContent(&response)
        default:
            break
        }
    }

    // MARK: - Platform-specific rectification

    private func rectifyDeepSeek(_ request: inout [String: Any], config: ReasoningConfig) {
        // DeepSeek uses "thinking" and "reasoning_effort" parameters
        if config.supportsThinking == true {
            // Ensure thinking parameter is set correctly
            if request["thinking"] == nil, let param = config.thinkingParam {
                request[param] = true
            }
        }

        if config.supportsEffort == true {
            // Map effort values
            if let effort = request["effort"] as? String {
                request.removeValue(forKey: "effort")
                if let param = config.effortParam {
                    request[param] = mapEffortValue(effort, mode: "deepseek")
                }
            }
        }
    }

    private func rectifyOpenRouter(_ request: inout [String: Any], config: ReasoningConfig) {
        // OpenRouter uses "reasoning.effort" parameter
        if config.supportsEffort == true {
            if let effort = request["effort"] as? String {
                request.removeValue(forKey: "effort")
                if let param = config.effortParam {
                    request[param] = mapEffortValue(effort, mode: "openrouter")
                }
            }
        }
    }

    private func rectifySiliconFlow(_ request: inout [String: Any], config: ReasoningConfig) {
        // SiliconFlow uses "enable_thinking" parameter
        if config.supportsThinking == true {
            if request["thinking"] != nil || request["reasoning"] != nil {
                request.removeValue(forKey: "thinking")
                request.removeValue(forKey: "reasoning")
                if let param = config.thinkingParam {
                    request[param] = true
                }
            }
        }
    }

    private func rectifyKimi(_ request: inout [String: Any], config: ReasoningConfig) {
        // Kimi uses "thinking" parameter
        if config.supportsThinking == true {
            if request["enable_thinking"] != nil {
                request.removeValue(forKey: "enable_thinking")
                if let param = config.thinkingParam {
                    request[param] = true
                }
            }
        }
    }

    private func rectifyQwen(_ request: inout [String: Any], config: ReasoningConfig) {
        // Qwen uses "enable_thinking" parameter
        if config.supportsThinking == true {
            if request["thinking"] != nil || request["reasoning"] != nil {
                request.removeValue(forKey: "thinking")
                request.removeValue(forKey: "reasoning")
                if let param = config.thinkingParam {
                    request[param] = true
                }
            }
        }
    }

    private func rectifyMiniMax(_ request: inout [String: Any], config: ReasoningConfig) {
        // MiniMax uses "reasoning_split" parameter
        if config.supportsThinking == true {
            if request["thinking"] != nil || request["reasoning"] != nil {
                request.removeValue(forKey: "thinking")
                request.removeValue(forKey: "reasoning")
                if let param = config.thinkingParam {
                    request[param] = true
                }
            }
        }
    }

    // MARK: - Helper methods

    private func mapEffortValue(_ effort: String, mode: String) -> Any {
        switch mode {
        case "deepseek":
            // DeepSeek accepts: low, medium, high
            return effort.lowercased()
        case "openrouter":
            // OpenRouter accepts: low, medium, high
            return effort.lowercased()
        default:
            return effort
        }
    }

    func transformReasoningContent(_ response: inout [String: Any]) {
        // Transform reasoning_content to standard format
        if let choices = response["choices"] as? [[String: Any]] {
            var newChoices: [[String: Any]] = []
            for choice in choices {
                var newChoice = choice
                if let message = choice["message"] as? [String: Any] {
                    var newMessage = message
                    if let reasoningContent = message["reasoning_content"] as? String {
                        // Prepend reasoning to content
                        let content = message["content"] as? String ?? ""
                        newMessage["content"] = "<reasoning>\(reasoningContent)</reasoning>\n\(content)"
                        newMessage.removeValue(forKey: "reasoning_content")
                    }
                    newChoice["message"] = newMessage
                }
                newChoices.append(newChoice)
            }
            response["choices"] = newChoices
        }
    }

    func transformReasoningDetails(_ response: inout [String: Any]) {
        // Transform reasoning_details to standard format
        if let choices = response["choices"] as? [[String: Any]] {
            var newChoices: [[String: Any]] = []
            for choice in choices {
                var newChoice = choice
                if let message = choice["message"] as? [String: Any] {
                    var newMessage = message
                    if let reasoningDetails = message["reasoning_details"] as? [[String: Any]] {
                        // Combine reasoning details into text
                        let reasoningText = reasoningDetails.compactMap { $0["text"] as? String }.joined(separator: "\n")
                        let content = message["content"] as? String ?? ""
                        newMessage["content"] = "<reasoning>\(reasoningText)</reasoning>\n\(content)"
                        newMessage.removeValue(forKey: "reasoning_details")
                    }
                    newChoice["message"] = newMessage
                }
                newChoices.append(newChoice)
            }
            response["choices"] = newChoices
        }
    }
}

/// Supported reasoning platforms.
public enum ReasoningPlatform: String, Codable, CaseIterable, Sendable {
    case deepseek
    case openrouter
    case siliconflow
    case kimi
    case qwen
    case minimax
    case standard

    /// Detect platform from base URL.
    public static func detect(from baseURL: String?) -> ReasoningPlatform {
        guard let url = baseURL?.lowercased() else {
            return .standard
        }

        if url.contains("deepseek") {
            return .deepseek
        } else if url.contains("openrouter") {
            return .openrouter
        } else if url.contains("siliconflow") || url.contains("silicon-flow") {
            return .siliconflow
        } else if url.contains("kimi") || url.contains("moonshot") {
            return .kimi
        } else if url.contains("qwen") || url.contains("dashscope") {
            return .qwen
        } else if url.contains("minimax") {
            return .minimax
        }

        return .standard
    }
}
