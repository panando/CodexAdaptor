import XCTest
@testable import CodexRouterApp

final class LoggingServiceTests: XCTestCase {

    func testLogLevelComparison() {
        XCTAssertTrue(LogLevel.error > LogLevel.warning)
        XCTAssertTrue(LogLevel.warning > LogLevel.info)
        XCTAssertTrue(LogLevel.info > LogLevel.debug)
    }

    func testLogLevelPrefix() {
        XCTAssertEqual(LogLevel.debug.prefix, "[DEBUG]")
        XCTAssertEqual(LogLevel.info.prefix, "[INFO]")
        XCTAssertEqual(LogLevel.warning.prefix, "[WARN]")
        XCTAssertEqual(LogLevel.error.prefix, "[ERROR]")
    }

    func testSetMinimumLevel() async {
        let service = LoggingService.shared
        await service.setMinimumLevel(.debug)
        // No assertion needed, just verify it doesn't crash
    }

    func testDefaultLogPath() {
        let path = LoggingService.defaultLogPath()
        XCTAssertTrue(path.contains(".codex-router"))
        XCTAssertTrue(path.contains("logs"))
    }

    func testLogCategories() {
        XCTAssertEqual(LogCategory.proxy.rawValue, "Proxy")
        XCTAssertEqual(LogCategory.provider.rawValue, "Provider")
        XCTAssertEqual(LogCategory.database.rawValue, "Database")
        XCTAssertEqual(LogCategory.failover.rawValue, "Failover")
        XCTAssertEqual(LogCategory.circuitBreaker.rawValue, "CircuitBreaker")
        XCTAssertEqual(LogCategory.transformer.rawValue, "Transformer")
        XCTAssertEqual(LogCategory.config.rawValue, "Config")
        XCTAssertEqual(LogCategory.ui.rawValue, "UI")
        XCTAssertEqual(LogCategory.general.rawValue, "General")
    }

    func testDebugLogging() async {
        let service = LoggingService.shared
        await service.setMinimumLevel(.debug)
        await service.debug("Test debug message", category: .general)
        // No assertion needed, just verify it doesn't crash
    }

    func testInfoLogging() async {
        let service = LoggingService.shared
        await service.info("Test info message", category: .proxy)
    }

    func testWarningLogging() async {
        let service = LoggingService.shared
        await service.warning("Test warning message", category: .provider)
    }

    func testErrorLogging() async {
        let service = LoggingService.shared
        await service.error("Test error message", category: .database, error: NSError(domain: "test", code: 1))
    }

    func testFileLogging() async throws {
        let service = LoggingService.shared
        let tempPath = NSTemporaryDirectory() + "test-log-\(UUID().uuidString).log"

        try await service.enableFileLogging(to: tempPath)
        await service.info("Test file logging", category: .general)
        await service.disableFileLogging()

        // Verify file was created
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempPath))

        // Clean up
        try? FileManager.default.removeItem(atPath: tempPath)
    }
}
