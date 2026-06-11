import Foundation

/// Circuit breaker state.
public enum CircuitState: String, Codable {
    case closed
    case open
    case halfOpen
}

/// Thread-safe circuit breaker implementation using actor isolation.
public actor CircuitBreaker {
    public let config: CircuitBreakerConfig
    private(set) public var state: CircuitState = .closed
    private var failureCount: UInt = 0
    private var successCount: UInt = 0
    private var lastFailureTime: Date?

    public init(config: CircuitBreakerConfig = .default) {
        self.config = config
    }

    /// Check if a request should be allowed.
    public func allowRequest() -> Bool {
        switch state {
        case .closed:
            return true
        case .open:
            // Check if timeout has passed
            guard let lastFailure = lastFailureTime else { return false }
            let elapsed = Date().timeIntervalSince(lastFailure)
            if elapsed >= Double(config.timeoutSeconds) {
                state = .halfOpen
                successCount = 0
                return true
            }
            return false
        case .halfOpen:
            return true
        }
    }

    /// Record a successful request.
    public func recordSuccess() {
        failureCount = 0

        switch state {
        case .closed:
            break
        case .open:
            break
        case .halfOpen:
            successCount += 1
            if successCount >= config.successThreshold {
                state = .closed
                successCount = 0
            }
        }
    }

    /// Record a failed request.
    public func recordFailure() {
        successCount = 0
        lastFailureTime = Date()

        switch state {
        case .closed:
            failureCount += 1
            if failureCount >= config.failureThreshold {
                state = .open
            }
        case .open:
            break
        case .halfOpen:
            state = .open
        }
    }

    /// Reset to closed state.
    public func reset() {
        state = .closed
        failureCount = 0
        successCount = 0
        lastFailureTime = nil
    }

    /// Get current state.
    public func getState() -> CircuitState {
        return state
    }
}
