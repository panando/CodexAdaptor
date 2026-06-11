import Foundation

/// Configuration for reasoning/thinking support in Codex Chat providers.
public struct ReasoningConfig: Codable, Equatable {
    public var supportsThinking: Bool?
    public var supportsEffort: Bool?
    public var thinkingParam: String?
    public var effortParam: String?
    public var effortValueMode: String?
    public var outputFormat: String?

    public init(
        supportsThinking: Bool? = nil,
        supportsEffort: Bool? = nil,
        thinkingParam: String? = nil,
        effortParam: String? = nil,
        effortValueMode: String? = nil,
        outputFormat: String? = nil
    ) {
        self.supportsThinking = supportsThinking
        self.supportsEffort = supportsEffort
        self.thinkingParam = thinkingParam
        self.effortParam = effortParam
        self.effortValueMode = effortValueMode
        self.outputFormat = outputFormat
    }

    /// Default config for DeepSeek platform.
    public static let deepseek = ReasoningConfig(
        supportsThinking: true,
        supportsEffort: true,
        thinkingParam: "thinking",
        effortParam: "reasoning_effort",
        effortValueMode: "deepseek",
        outputFormat: "reasoning_content"
    )

    /// Default config for OpenRouter platform.
    public static let openrouter = ReasoningConfig(
        supportsThinking: false,
        supportsEffort: true,
        thinkingParam: "none",
        effortParam: "reasoning.effort",
        effortValueMode: "openrouter",
        outputFormat: "auto"
    )

    /// Default config for SiliconFlow platform.
    public static let siliconflow = ReasoningConfig(
        supportsThinking: true,
        supportsEffort: false,
        thinkingParam: "enable_thinking",
        effortParam: "none",
        outputFormat: "reasoning_content"
    )

    /// Default config for Kimi platform.
    public static let kimi = ReasoningConfig(
        supportsThinking: true,
        supportsEffort: false,
        thinkingParam: "thinking",
        effortParam: "none",
        outputFormat: "reasoning_content"
    )

    /// Default config for Qwen platform.
    public static let qwen = ReasoningConfig(
        supportsThinking: true,
        supportsEffort: false,
        thinkingParam: "enable_thinking",
        effortParam: "none",
        outputFormat: "reasoning_content"
    )

    /// Default config for MiniMax platform.
    public static let minimax = ReasoningConfig(
        supportsThinking: true,
        supportsEffort: false,
        thinkingParam: "reasoning_split",
        effortParam: "none",
        outputFormat: "reasoning_details"
    )
}
