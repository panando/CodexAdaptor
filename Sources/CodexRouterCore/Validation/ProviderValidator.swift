import Foundation

/// Validation error types for providers.
public enum ProviderValidationError: Error, LocalizedError, Equatable {
    case emptyName
    case emptyBaseURL
    case invalidBaseURL(String)
    case emptyAPIKey
    case invalidAPIKeyFormat(String)
    case duplicateID(String)
    case invalidTimeout(Int)

    public var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Provider name cannot be empty"
        case .emptyBaseURL:
            return "Base URL cannot be empty"
        case .invalidBaseURL(let url):
            return "Invalid base URL: \(url)"
        case .emptyAPIKey:
            return "API key cannot be empty"
        case .invalidAPIKeyFormat(let reason):
            return "Invalid API key format: \(reason)"
        case .duplicateID(let id):
            return "Provider with ID '\(id)' already exists"
        case .invalidTimeout(let value):
            return "Invalid timeout value: \(value). Must be between 1 and 3600 seconds."
        }
    }
}

/// Validates provider configurations.
public struct ProviderValidator {
    public init() {}

    /// Validate a provider configuration.
    public func validate(_ provider: Provider, existingIds: [String] = []) throws {
        // Validate name
        guard !provider.name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ProviderValidationError.emptyName
        }

        // Validate base URL
        guard let baseURL = provider.baseURL,
              !baseURL.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ProviderValidationError.emptyBaseURL
        }

        guard isValidURL(baseURL) else {
            throw ProviderValidationError.invalidBaseURL(baseURL)
        }

        // Check for duplicate ID
        if existingIds.contains(provider.id) {
            throw ProviderValidationError.duplicateID(provider.id)
        }
    }

    /// Validate an API key format (optional, provider-specific).
    public func validateAPIKey(_ apiKey: String, providerId: String) throws {
        guard !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ProviderValidationError.emptyAPIKey
        }

        // Provider-specific validation
        if providerId.contains("openai") || providerId.contains("openrouter") {
            // OpenAI keys start with "sk-"
            if !apiKey.hasPrefix("sk-") {
                throw ProviderValidationError.invalidAPIKeyFormat("OpenAI API keys should start with 'sk-'")
            }
        } else if providerId.contains("anthropic") {
            // Anthropic keys start with "sk-ant-"
            if !apiKey.hasPrefix("sk-ant-") {
                throw ProviderValidationError.invalidAPIKeyFormat("Anthropic API keys should start with 'sk-ant-'")
            }
        }
        // Other providers don't have strict key format requirements
    }

    /// Validate timeout configuration.
    public func validateTimeout(_ timeout: Int) throws {
        guard timeout >= 1 && timeout <= 3600 else {
            throw ProviderValidationError.invalidTimeout(timeout)
        }
    }

    // MARK: - Private Helpers

    private func isValidURL(_ string: String) -> Bool {
        guard let url = URL(string: string) else { return false }
        return url.scheme == "http" || url.scheme == "https"
    }
}

/// Validates proxy configuration.
public struct ConfigValidator {
    public init() {}

    /// Validate proxy configuration.
    public func validate(_ config: ProxyConfig) throws {
        let validator = ProviderValidator()

        // Validate timeouts
        try validator.validateTimeout(Int(config.circuitBreaker.timeoutSeconds))
        try validator.validateTimeout(Int(config.streamingFirstByteTimeout))
        try validator.validateTimeout(Int(config.streamingIdleTimeout))

        // Validate max retries
        guard config.maxRetries >= 0 && config.maxRetries <= 10 else {
            throw ProviderValidationError.invalidTimeout(Int(config.maxRetries))
        }

        // Validate circuit breaker thresholds
        guard config.circuitBreaker.failureThreshold >= 1 && config.circuitBreaker.failureThreshold <= 100 else {
            throw ProviderValidationError.invalidTimeout(Int(config.circuitBreaker.failureThreshold))
        }

        guard config.circuitBreaker.successThreshold >= 1 && config.circuitBreaker.successThreshold <= 100 else {
            throw ProviderValidationError.invalidTimeout(Int(config.circuitBreaker.successThreshold))
        }
    }
}
