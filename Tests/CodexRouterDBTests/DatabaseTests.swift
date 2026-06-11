import XCTest
@testable import CodexRouterDB
@testable import CodexRouterCore

final class DatabaseTests: XCTestCase {
    var database: Database!

    override func setUp() async throws {
        try await super.setUp()
        database = try Database.inMemory()
    }

    override func tearDown() async throws {
        database = nil
        try await super.tearDown()
    }

    // MARK: - ProviderDAO Tests

    func testProviderDAOInsert() throws {
        let dao = ProviderDAO(database)

        let provider = Provider(
            id: "test-provider",
            name: "Test Provider",
            settingsConfig: ["base_url": AnyCodable("https://api.example.com")]
        )

        try dao.save(provider)

        let retrieved = try dao.get(byId: "test-provider")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.name, "Test Provider")
        XCTAssertEqual(retrieved?.baseURL, "https://api.example.com")
    }

    func testProviderDAOGetAll() throws {
        let dao = ProviderDAO(database)

        let provider1 = Provider(id: "provider-1", name: "Provider 1")
        let provider2 = Provider(id: "provider-2", name: "Provider 2")

        try dao.save(provider1)
        try dao.save(provider2)

        let all = try dao.getAll()
        XCTAssertEqual(all.count, 2)
    }

    func testProviderDAODelete() throws {
        let dao = ProviderDAO(database)

        let provider = Provider(id: "to-delete", name: "To Delete")
        try dao.save(provider)

        var retrieved = try dao.get(byId: "to-delete")
        XCTAssertNotNil(retrieved)

        try dao.delete(id: "to-delete")

        retrieved = try dao.get(byId: "to-delete")
        XCTAssertNil(retrieved)
    }

    func testProviderDAOSetCurrent() throws {
        let dao = ProviderDAO(database)

        let provider1 = Provider(id: "current-1", name: "Current 1")
        let provider2 = Provider(id: "current-2", name: "Current 2")

        try dao.save(provider1)
        try dao.save(provider2)

        try dao.setCurrent(id: "current-2")

        let current = try dao.getCurrent()
        XCTAssertNotNil(current)
        XCTAssertEqual(current?.id, "current-2")
    }

    // MARK: - ProxyConfigDAO Tests

    func testProxyConfigDAODefault() throws {
        let dao = ProxyConfigDAO(database)

        let config = try dao.get()

        XCTAssertEqual(config.appType, "codex")
        XCTAssertFalse(config.autoFailoverEnabled)
        XCTAssertEqual(config.maxRetries, 3)
        XCTAssertEqual(config.circuitBreaker.failureThreshold, 5)
    }

    func testProxyConfigDAOSave() throws {
        let dao = ProxyConfigDAO(database)

        let config = ProxyConfig(
            appType: "codex",
            autoFailoverEnabled: true,
            maxRetries: 5,
            circuitBreaker: CircuitBreakerConfig(
                failureThreshold: 10,
                successThreshold: 5,
                timeoutSeconds: 120
            )
        )

        try dao.save(config)

        let retrieved = try dao.get()
        XCTAssertTrue(retrieved.autoFailoverEnabled)
        XCTAssertEqual(retrieved.maxRetries, 5)
        XCTAssertEqual(retrieved.circuitBreaker.failureThreshold, 10)
    }

    func testProxyConfigDAOSetAutoFailover() throws {
        let dao = ProxyConfigDAO(database)

        try dao.setAutoFailover(enabled: true)

        let config = try dao.get()
        XCTAssertTrue(config.autoFailoverEnabled)
    }

    // MARK: - FailoverDAO Tests

    func testFailoverDAOAddToQueue() throws {
        let providerDAO = ProviderDAO(database)
        let failoverDAO = FailoverDAO(database)

        let provider = Provider(id: "failover-test", name: "Failover Test")
        try providerDAO.save(provider)

        try failoverDAO.addToQueue(providerId: "failover-test", appType: "codex", priority: 0)

        let queue = try failoverDAO.getQueue(appType: "codex")
        XCTAssertEqual(queue.count, 1)
        XCTAssertEqual(queue.first?.id, "failover-test")
    }

    func testFailoverDAORemoveFromQueue() throws {
        let providerDAO = ProviderDAO(database)
        let failoverDAO = FailoverDAO(database)

        let provider = Provider(id: "remove-test", name: "Remove Test")
        try providerDAO.save(provider)
        try failoverDAO.addToQueue(providerId: "remove-test", appType: "codex", priority: 0)

        var queue = try failoverDAO.getQueue(appType: "codex")
        XCTAssertEqual(queue.count, 1)

        try failoverDAO.removeFromQueue(providerId: "remove-test", appType: "codex")

        queue = try failoverDAO.getQueue(appType: "codex")
        XCTAssertEqual(queue.count, 0)
    }

    func testFailoverDAOReorderQueue() throws {
        let providerDAO = ProviderDAO(database)
        let failoverDAO = FailoverDAO(database)

        let provider1 = Provider(id: "order-1", name: "Order 1")
        let provider2 = Provider(id: "order-2", name: "Order 2")
        let provider3 = Provider(id: "order-3", name: "Order 3")

        try providerDAO.save(provider1)
        try providerDAO.save(provider2)
        try providerDAO.save(provider3)

        try failoverDAO.addToQueue(providerId: "order-1", appType: "codex", priority: 0)
        try failoverDAO.addToQueue(providerId: "order-2", appType: "codex", priority: 1)
        try failoverDAO.addToQueue(providerId: "order-3", appType: "codex", priority: 2)

        var queue = try failoverDAO.getQueue(appType: "codex")
        XCTAssertEqual(queue[0].id, "order-1")

        // Reorder: 3, 1, 2
        try failoverDAO.reorderQueue(appType: "codex", providerIds: ["order-3", "order-1", "order-2"])

        queue = try failoverDAO.getQueue(appType: "codex")
        XCTAssertEqual(queue.count, 3)
        XCTAssertEqual(queue[0].id, "order-3")
        XCTAssertEqual(queue[1].id, "order-1")
        XCTAssertEqual(queue[2].id, "order-2")
    }

    // MARK: - ProviderHealthDAO Tests

    func testProviderHealthDAORecordSuccess() throws {
        let dao = ProviderHealthDAO(database)

        try dao.recordSuccess(providerId: "health-test", appType: "codex")

        let health = try dao.get(providerId: "health-test", appType: "codex")
        XCTAssertTrue(health.isHealthy)
        XCTAssertEqual(health.consecutiveFailures, 0)
        XCTAssertNotNil(health.lastSuccessAt)
    }

    func testProviderHealthDAORecordFailure() throws {
        let dao = ProviderHealthDAO(database)

        try dao.recordFailure(providerId: "failure-test", appType: "codex", error: "Test error")

        let health = try dao.get(providerId: "failure-test", appType: "codex")
        XCTAssertEqual(health.consecutiveFailures, 1)
        XCTAssertEqual(health.lastError, "Test error")
    }

    func testProviderHealthDAOMarkUnhealthy() throws {
        let dao = ProviderHealthDAO(database)

        // Record 5 failures
        for _ in 0..<5 {
            try dao.recordFailure(providerId: "unhealthy-test", appType: "codex", error: "Error")
        }

        let health = try dao.get(providerId: "unhealthy-test", appType: "codex")
        XCTAssertFalse(health.isHealthy)
    }

    func testProviderHealthDAOReset() throws {
        let dao = ProviderHealthDAO(database)

        // Record failures
        for _ in 0..<3 {
            try dao.recordFailure(providerId: "reset-test", appType: "codex", error: "Error")
        }

        var health = try dao.get(providerId: "reset-test", appType: "codex")
        XCTAssertEqual(health.consecutiveFailures, 3)

        // Reset
        try dao.reset(providerId: "reset-test", appType: "codex")

        health = try dao.get(providerId: "reset-test", appType: "codex")
        XCTAssertTrue(health.isHealthy)
        XCTAssertEqual(health.consecutiveFailures, 0)
    }
}
