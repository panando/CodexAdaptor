import XCTest
@testable import CodexRouterCore

final class ProviderValidatorTests: XCTestCase {
    var validator: ProviderValidator!
    var configValidator: ConfigValidator!

    override func setUp() async throws {
        try await super.setUp()
        validator = ProviderValidator()
        configValidator = ConfigValidator()
    }

    // MARK: - Provider Validation Tests

    func testValidProvider() throws {
        let provider = Provider(
            id: "test-provider",
            name: "Test Provider",
            settingsConfig: ["base_url": AnyCodable("https://api.example.com")]
        )

        XCTAssertNoThrow(try validator.validate(provider))
    }

    func testEmptyNameThrowsError() {
        let provider = Provider(
            id: "test",
            name: "",
            settingsConfig: ["base_url": AnyCodable("https://api.example.com")]
        )

        XCTAssertThrowsError(try validator.validate(provider)) { error in
            XCTAssertTrue(error is ProviderValidationError)
            XCTAssertEqual(error as? ProviderValidationError, .emptyName)
        }
    }

    func testWhitespaceNameThrowsError() {
        let provider = Provider(
            id: "test",
            name: "   ",
            settingsConfig: ["base_url": AnyCodable("https://api.example.com")]
        )

        XCTAssertThrowsError(try validator.validate(provider)) { error in
            XCTAssertTrue(error is ProviderValidationError)
            XCTAssertEqual(error as? ProviderValidationError, .emptyName)
        }
    }

    func testEmptyBaseURLThrowsError() {
        let provider = Provider(
            id: "test",
            name: "Test",
            settingsConfig: [:]
        )

        XCTAssertThrowsError(try validator.validate(provider)) { error in
            XCTAssertTrue(error is ProviderValidationError)
            XCTAssertEqual(error as? ProviderValidationError, .emptyBaseURL)
        }
    }

    func testInvalidBaseURLThrowsError() {
        let provider = Provider(
            id: "test",
            name: "Test",
            settingsConfig: ["base_url": AnyCodable("not-a-valid-url")]
        )

        XCTAssertThrowsError(try validator.validate(provider)) { error in
            XCTAssertTrue(error is ProviderValidationError)
            if case .invalidBaseURL(let url) = error as? ProviderValidationError {
                XCTAssertEqual(url, "not-a-valid-url")
            }
        }
    }

    func testDuplicateIDThrowsError() {
        let provider = Provider(
            id: "existing-id",
            name: "Test",
            settingsConfig: ["base_url": AnyCodable("https://api.example.com")]
        )

        XCTAssertThrowsError(try validator.validate(provider, existingIds: ["existing-id", "other-id"])) { error in
            XCTAssertTrue(error is ProviderValidationError)
            XCTAssertEqual(error as? ProviderValidationError, .duplicateID("existing-id"))
        }
    }

    // MARK: - API Key Validation Tests

    func testEmptyAPIKeyThrowsError() {
        XCTAssertThrowsError(try validator.validateAPIKey("", providerId: "test")) { error in
            XCTAssertEqual(error as? ProviderValidationError, .emptyAPIKey)
        }
    }

    func testOpenAIKeyFormat() throws {
        // Valid OpenAI key
        XCTAssertNoThrow(try validator.validateAPIKey("sk-test123", providerId: "openai-main"))

        // Invalid OpenAI key
        XCTAssertThrowsError(try validator.validateAPIKey("test123", providerId: "openai-main")) { error in
            if case .invalidAPIKeyFormat(let reason) = error as? ProviderValidationError {
                XCTAssertTrue(reason.contains("sk-"))
            }
        }
    }

    func testAnthropicKeyFormat() throws {
        // Valid Anthropic key
        XCTAssertNoThrow(try validator.validateAPIKey("sk-ant-test123", providerId: "anthropic-main"))

        // Invalid Anthropic key
        XCTAssertThrowsError(try validator.validateAPIKey("sk-test123", providerId: "anthropic-main")) { error in
            if case .invalidAPIKeyFormat(let reason) = error as? ProviderValidationError {
                XCTAssertTrue(reason.contains("sk-ant-"))
            }
        }
    }

    func testOtherProviderKeyFormat() throws {
        // Other providers don't have strict requirements
        XCTAssertNoThrow(try validator.validateAPIKey("any-key-format", providerId: "custom-provider"))
    }

    // MARK: - Timeout Validation Tests

    func testValidTimeout() throws {
        XCTAssertNoThrow(try validator.validateTimeout(60))
        XCTAssertNoThrow(try validator.validateTimeout(1))
        XCTAssertNoThrow(try validator.validateTimeout(3600))
    }

    func testInvalidTimeoutTooLow() {
        XCTAssertThrowsError(try validator.validateTimeout(0)) { error in
            XCTAssertEqual(error as? ProviderValidationError, .invalidTimeout(0))
        }
    }

    func testInvalidTimeoutTooHigh() {
        XCTAssertThrowsError(try validator.validateTimeout(3601)) { error in
            XCTAssertEqual(error as? ProviderValidationError, .invalidTimeout(3601))
        }
    }

    // MARK: - Config Validation Tests

    func testValidProxyConfig() throws {
        let config = ProxyConfig(
            appType: "codex",
            maxRetries: 3,
            streamingFirstByteTimeout: 60,
            streamingIdleTimeout: 120,
            circuitBreaker: CircuitBreakerConfig(
                failureThreshold: 5,
                successThreshold: 3,
                timeoutSeconds: 60
            )
        )

        XCTAssertNoThrow(try configValidator.validate(config))
    }

    func testInvalidProxyConfigMaxRetries() {
        let config = ProxyConfig(
            appType: "codex",
            maxRetries: 15,  // Too high
            streamingFirstByteTimeout: 60,
            streamingIdleTimeout: 120,
            circuitBreaker: CircuitBreakerConfig(
                failureThreshold: 5,
                successThreshold: 3,
                timeoutSeconds: 60
            )
        )

        XCTAssertThrowsError(try configValidator.validate(config))
    }

    // MARK: - Error Description Tests

    func testErrorDescriptions() {
        XCTAssertEqual(ProviderValidationError.emptyName.errorDescription, "Provider name cannot be empty")
        XCTAssertEqual(ProviderValidationError.emptyBaseURL.errorDescription, "Base URL cannot be empty")
        XCTAssertEqual(ProviderValidationError.emptyAPIKey.errorDescription, "API key cannot be empty")
        XCTAssertTrue(ProviderValidationError.invalidBaseURL("test").errorDescription?.contains("test") ?? false)
    }
}
