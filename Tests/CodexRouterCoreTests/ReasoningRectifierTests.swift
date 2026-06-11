import XCTest
@testable import CodexRouterCore

final class ReasoningRectifierTests: XCTestCase {
    var rectifier: ReasoningRectifier!

    override func setUp() async throws {
        try await super.setUp()
        rectifier = ReasoningRectifier()
    }

    // MARK: - Platform Detection Tests

    func testDetectDeepSeekPlatform() {
        XCTAssertEqual(ReasoningPlatform.detect(from: "https://api.deepseek.com"), .deepseek)
        XCTAssertEqual(ReasoningPlatform.detect(from: "https://api.deepseek.com/v1"), .deepseek)
    }

    func testDetectOpenRouterPlatform() {
        XCTAssertEqual(ReasoningPlatform.detect(from: "https://openrouter.ai/api/v1"), .openrouter)
        XCTAssertEqual(ReasoningPlatform.detect(from: "https://api.openrouter.ai/v1"), .openrouter)
    }

    func testDetectSiliconFlowPlatform() {
        XCTAssertEqual(ReasoningPlatform.detect(from: "https://api.siliconflow.cn/v1"), .siliconflow)
        XCTAssertEqual(ReasoningPlatform.detect(from: "https://api.silicon-flow.cn/v1"), .siliconflow)
    }

    func testDetectKimiPlatform() {
        XCTAssertEqual(ReasoningPlatform.detect(from: "https://api.moonshot.cn/v1"), .kimi)
        XCTAssertEqual(ReasoningPlatform.detect(from: "https://api.kimi.ai/v1"), .kimi)
    }

    func testDetectQwenPlatform() {
        XCTAssertEqual(ReasoningPlatform.detect(from: "https://dashscope.aliyuncs.com/api/v1"), .qwen)
        XCTAssertEqual(ReasoningPlatform.detect(from: "https://api.qwen.ai/v1"), .qwen)
    }

    func testDetectMiniMaxPlatform() {
        XCTAssertEqual(ReasoningPlatform.detect(from: "https://api.minimax.chat/v1"), .minimax)
    }

    func testDetectStandardPlatform() {
        XCTAssertEqual(ReasoningPlatform.detect(from: "https://api.openai.com/v1"), .standard)
        XCTAssertEqual(ReasoningPlatform.detect(from: "https://api.anthropic.com/v1"), .standard)
        XCTAssertEqual(ReasoningPlatform.detect(from: nil), .standard)
    }

    // MARK: - DeepSeek Rectification Tests

    func testRectifyDeepSeekRequest() throws {
        var request: [String: Any] = [
            "model": "deepseek-reasoner",
            "messages": [["role": "user", "content": "Hello"]]
        ]

        let meta = ProviderMeta(
            apiFormat: "chat",
            codexChatReasoning: ReasoningConfig(
                supportsThinking: true,
                supportsEffort: true,
                thinkingParam: "thinking",
                effortParam: "reasoning_effort"
            )
        )

        let provider = Provider(id: "deepseek", name: "DeepSeek", meta: meta)

        rectifier.rectifyRequest(&request, provider: provider, platform: .deepseek)

        // Should add thinking parameter
        XCTAssertNotNil(request["thinking"])
        XCTAssertEqual(request["thinking"] as? Bool, true)
    }

    func testRectifyDeepSeekWithEffort() throws {
        var request: [String: Any] = [
            "model": "deepseek-reasoner",
            "messages": [["role": "user", "content": "Hello"]],
            "effort": "high"
        ]

        let meta = ProviderMeta(
            apiFormat: "chat",
            codexChatReasoning: ReasoningConfig(
                supportsThinking: true,
                supportsEffort: true,
                thinkingParam: "thinking",
                effortParam: "reasoning_effort"
            )
        )

        let provider = Provider(id: "deepseek", name: "DeepSeek", meta: meta)

        rectifier.rectifyRequest(&request, provider: provider, platform: .deepseek)

        // Should transform effort to reasoning_effort
        XCTAssertNil(request["effort"])
        XCTAssertEqual(request["reasoning_effort"] as? String, "high")
    }

    // MARK: - OpenRouter Rectification Tests

    func testRectifyOpenRouterRequest() throws {
        var request: [String: Any] = [
            "model": "anthropic/claude-3-opus",
            "messages": [["role": "user", "content": "Hello"]],
            "effort": "medium"
        ]

        let meta = ProviderMeta(
            apiFormat: "chat",
            codexChatReasoning: ReasoningConfig(
                supportsEffort: true,
                effortParam: "reasoning.effort"
            )
        )

        let provider = Provider(id: "openrouter", name: "OpenRouter", meta: meta)

        rectifier.rectifyRequest(&request, provider: provider, platform: .openrouter)

        // Should transform effort
        XCTAssertNil(request["effort"])
        XCTAssertEqual(request["reasoning.effort"] as? String, "medium")
    }

    // MARK: - SiliconFlow Rectification Tests

    func testRectifySiliconFlowRequest() throws {
        var request: [String: Any] = [
            "model": "deepseek-ai/DeepSeek-R1",
            "messages": [["role": "user", "content": "Hello"]],
            "thinking": true
        ]

        let meta = ProviderMeta(
            apiFormat: "chat",
            codexChatReasoning: ReasoningConfig(
                supportsThinking: true,
                thinkingParam: "enable_thinking"
            )
        )

        let provider = Provider(id: "siliconflow", name: "SiliconFlow", meta: meta)

        rectifier.rectifyRequest(&request, provider: provider, platform: .siliconflow)

        // Should transform thinking to enable_thinking
        XCTAssertNil(request["thinking"])
        XCTAssertEqual(request["enable_thinking"] as? Bool, true)
    }

    // MARK: - Response Rectification Tests

    func testRectifyResponseWithReasoningContent() throws {
        var response: [String: Any] = [
            "id": "test-id",
            "choices": [
                [
                    "message": [
                        "role": "assistant",
                        "content": "Final answer",
                        "reasoning_content": "My reasoning process..."
                    ]
                ]
            ]
        ]

        let meta = ProviderMeta(
            apiFormat: "chat",
            codexChatReasoning: ReasoningConfig(
                outputFormat: "reasoning_content"
            )
        )

        let provider = Provider(id: "test", name: "Test", meta: meta)

        rectifier.rectifyResponse(&response, provider: provider, platform: .deepseek)

        // Should transform reasoning_content into content
        if let choices = response["choices"] as? [[String: Any]],
           let message = choices[0]["message"] as? [String: Any],
           let content = message["content"] as? String {
            XCTAssertTrue(content.contains("<reasoning>"))
            XCTAssertTrue(content.contains("My reasoning process..."))
            XCTAssertTrue(content.contains("Final answer"))
            XCTAssertNil(message["reasoning_content"])
        } else {
            XCTFail("Failed to get transformed response")
        }
    }

    func testRectifyResponseWithReasoningDetails() throws {
        var response: [String: Any] = [
            "id": "test-id",
            "choices": [
                [
                    "message": [
                        "role": "assistant",
                        "content": "Final answer",
                        "reasoning_details": [
                            ["text": "First thought"],
                            ["text": "Second thought"]
                        ]
                    ]
                ]
            ]
        ]

        let meta = ProviderMeta(
            apiFormat: "chat",
            codexChatReasoning: ReasoningConfig(
                outputFormat: "reasoning_details"
            )
        )

        let provider = Provider(id: "test", name: "Test", meta: meta)

        rectifier.rectifyResponse(&response, provider: provider, platform: .standard)

        // Should transform reasoning_details into content
        if let choices = response["choices"] as? [[String: Any]],
           let message = choices[0]["message"] as? [String: Any],
           let content = message["content"] as? String {
            XCTAssertTrue(content.contains("<reasoning>"))
            XCTAssertTrue(content.contains("First thought"))
            XCTAssertTrue(content.contains("Second thought"))
            XCTAssertNil(message["reasoning_details"])
        } else {
            XCTFail("Failed to get transformed response")
        }
    }

    // MARK: - No Op Tests

    func testNoRectificationWithoutMeta() {
        var request: [String: Any] = [
            "model": "gpt-4",
            "messages": [["role": "user", "content": "Hello"]]
        ]

        let provider = Provider(id: "test", name: "Test")

        rectifier.rectifyRequest(&request, provider: provider, platform: .standard)

        // Should not modify request
        XCTAssertEqual(request.count, 2)
        XCTAssertEqual(request["model"] as? String, "gpt-4")
    }

    func testNoResponseRectificationWithoutMeta() {
        var response: [String: Any] = [
            "id": "test-id",
            "choices": [
                ["message": ["role": "assistant", "content": "Hello"]]
            ]
        ]

        let provider = Provider(id: "test", name: "Test")

        rectifier.rectifyResponse(&response, provider: provider, platform: .standard)

        // Should not modify response
        XCTAssertNil(response["reasoning_content"])
    }
}
