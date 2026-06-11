import XCTest
@testable import CodexRouterCore

final class CircuitBreakerTests: XCTestCase {
    func testInitialStateIsClosed() async {
        let breaker = CircuitBreaker(config: .default)
        let allowed = await breaker.allowRequest()
        XCTAssertTrue(allowed, "Circuit breaker should allow requests in closed state")
    }

    func testOpensAfterFailureThreshold() async {
        let config = CircuitBreakerConfig(failureThreshold: 3, timeoutSeconds: 0)
        let breaker = CircuitBreaker(config: config)

        for _ in 0..<3 {
            await breaker.recordFailure()
        }

        let allowed = await breaker.allowRequest()
        XCTAssertFalse(allowed, "Circuit breaker should be open after failure threshold")
    }

    func testClosesAfterSuccessThreshold() async {
        let config = CircuitBreakerConfig(
            failureThreshold: 1,
            successThreshold: 2,
            timeoutSeconds: 0
        )
        let breaker = CircuitBreaker(config: config)

        await breaker.recordFailure()
        var allowed = await breaker.allowRequest()
        XCTAssertFalse(allowed, "Should be open after failure")

        // Reset to enter half-open
        try? await Task.sleep(nanoseconds: 100_000_000)
        await breaker.reset()

        for _ in 0..<2 {
            allowed = await breaker.allowRequest()
            XCTAssertTrue(allowed, "Should allow in half-open")
            await breaker.recordSuccess()
        }

        allowed = await breaker.allowRequest()
        XCTAssertTrue(allowed, "Should be closed after success threshold")
    }

    func testResetReturnsToClosed() async {
        let config = CircuitBreakerConfig(failureThreshold: 1, timeoutSeconds: 60)
        let breaker = CircuitBreaker(config: config)

        await breaker.recordFailure()
        var allowed = await breaker.allowRequest()
        XCTAssertFalse(allowed, "Should be open")

        await breaker.reset()
        allowed = await breaker.allowRequest()
        XCTAssertTrue(allowed, "Should be closed after reset")
    }
}
