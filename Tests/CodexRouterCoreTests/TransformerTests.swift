import XCTest
@testable import CodexRouterCore

final class TransformerTests: XCTestCase {
    func testResponsesToChatBasicResponse() throws {
        let transformer = ResponsesToChatTransformer()

        let responsesJSON = """
        {
            "id": "resp_123",
            "model": "gpt-4o",
            "output": [
                {
                    "type": "message",
                    "content": [
                        {"type": "output_text", "text": "Hello, world!"}
                    ]
                }
            ],
            "usage": {
                "input_tokens": 10,
                "output_tokens": 5
            }
        }
        """

        let result = try transformer.transform(responsesJSON: responsesJSON)

        XCTAssertEqual(result.choices.count, 1)
        XCTAssertEqual(result.choices[0].message.content, "Hello, world!")
        XCTAssertEqual(result.model, "gpt-4o")
        XCTAssertEqual(result.usage?.totalTokens, 15)
    }

    func testResponsesToChatWithToolCalls() throws {
        let transformer = ResponsesToChatTransformer()

        let responsesJSON = """
        {
            "id": "resp_456",
            "model": "gpt-4o",
            "output": [
                {
                    "type": "function_call",
                    "id": "call_123",
                    "name": "get_weather",
                    "arguments": "{\"location\": \"Beijing\"}"
                }
            ]
        }
        """

        let result = try transformer.transform(responsesJSON: responsesJSON)

        XCTAssertEqual(result.choices[0].message.toolCalls?.count, 1)
        XCTAssertEqual(result.choices[0].message.toolCalls?[0].function.name, "get_weather")
    }
}
