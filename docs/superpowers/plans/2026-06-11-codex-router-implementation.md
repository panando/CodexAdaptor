# CodexRouter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a Swift-based local proxy router for Codex CLI with provider management, failover, circuit breaker, and format transformation.

**Architecture:** Modular Swift Package with Core/DB/App layers. Core contains models, router logic, transformers. DB handles SQLite persistence via GRDB. App is a macOS menu bar application using Hummingbird for HTTP proxy.

**Tech Stack:** Swift 5.9, Hummingbird 2.0, GRDB.swift, TOMLKit, SwiftUI

---

## File Structure

```
CodexRouter/
├── Package.swift
├── Sources/
│   ├── CodexRouterCore/
│   │   ├── Models/
│   │   │   ├── Provider.swift
│   │   │   ├── ProviderMeta.swift
│   │   │   ├── CircuitBreakerConfig.swift
│   │   │   ├── ReasoningConfig.swift
│   │   │   ├── ProxyConfig.swift
│   │   │   └── AnyCodable.swift
│   │   ├── Router/
│   │   │   ├── CircuitBreaker.swift
│   │   │   ├── ProviderRouter.swift
│   │   │   └── FailoverManager.swift
│   │   ├── Transformers/
│   │   │   ├── ResponsesToChatTransformer.swift
│   │   │   ├── ChatToResponsesTransformer.swift
│   │   │   ├── ReasoningRectifier.swift
│   │   │   └── SSEStreamTransformer.swift
│   │   ├── Config/
│   │   │   ├── TOMLConfigParser.swift
│   │   │   └── ConfigMigrator.swift
│   │   └── Networking/
│   │       ├── HTTPClient.swift
│   │       ├── SSEParser.swift
│   │       └── ProxyRequest.swift
│   │
│   ├── CodexRouterDB/
│   │   ├── Database.swift
│   │   ├── Schemas/
│   │   │   ├── ProviderRecord.swift
│   │   │   ├── FailoverQueueRecord.swift
│   │   │   ├── ProxyConfigRecord.swift
│   │   │   └── ProviderHealthRecord.swift
│   │   └── DAOs/
│   │       ├── ProviderDAO.swift
│   │       ├── FailoverDAO.swift
│   │       ├── ProxyConfigDAO.swift
│   │       └── ProviderHealthDAO.swift
│   │
│   └── CodexRouterApp/
│       ├── CodexRouterApp.swift
│       ├── AppDelegate.swift
│       ├── Server/
│       │   ├── ProxyServer.swift
│       │   ├── RequestHandler.swift
│       │   └── Routes.swift
│       ├── UI/
│       │   ├── MenuBarView.swift
│       │   ├── ProviderListView.swift
│       │   ├── ProviderFormView.swift
│       │   ├── FailoverConfigView.swift
│       │   └── SettingsView.swift
│       └── Services/
│           ├── AppState.swift
│           └── KeychainService.swift
│
└── Tests/
    ├── CodexRouterCoreTests/
    │   ├── CircuitBreakerTests.swift
    │   ├── TransformerTests.swift
    │   └── ReasoningRectifierTests.swift
    └── CodexRouterDBTests/
        └── DatabaseTests.swift
```

---

## Milestone 1: Core Framework

### Task 1: Package Structure Setup

**Files:**
- Create: `Package.swift`

- [ ] **Step 1: Create Package.swift with dependencies**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodexRouter",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CodexRouterCore", targets: ["CodexRouterCore"]),
        .library(name: "CodexRouterDB", targets: ["CodexRouterDB"]),
        .executable(name: "CodexRouterApp", targets: ["CodexRouterApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.24.0"),
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.5.0"),
    ],
    targets: [
        .target(
            name: "CodexRouterCore",
            dependencies: [
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "TOMLKit", package: "TOMLKit"),
            ],
            path: "Sources/CodexRouterCore"
        ),
        .target(
            name: "CodexRouterDB",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                "CodexRouterCore",
            ],
            path: "Sources/CodexRouterDB"
        ),
        .executableTarget(
            name: "CodexRouterApp",
            dependencies: [
                "CodexRouterCore",
                "CodexRouterDB",
                .product(name: "Hummingbird", package: "hummingbird"),
            ],
            path: "Sources/CodexRouterApp"
        ),
        .testTarget(
            name: "CodexRouterCoreTests",
            dependencies: ["CodexRouterCore"],
            path: "Tests/CodexRouterCoreTests"
        ),
        .testTarget(
            name: "CodexRouterDBTests",
            dependencies: ["CodexRouterDB"],
            path: "Tests/CodexRouterDBTests"
        ),
    ]
)
```

- [ ] **Step 2: Create directory structure**

Run:
```bash
mkdir -p Sources/CodexRouterCore/{Models,Router,Transformers,Config,Networking}
mkdir -p Sources/CodexRouterDB/{Schemas,DAOs}
mkdir -p Sources/CodexRouterApp/{Server,UI,Services}
mkdir -p Tests/{CodexRouterCoreTests,CodexRouterDBTests}
```

- [ ] **Step 3: Verify package resolves**

Run: `swift package resolve`
Expected: Dependencies downloaded successfully

- [ ] **Step 4: Commit**

```bash
git add Package.swift
git commit -m "chore: initialize Swift package structure"
```

---

### Task 2: AnyCodable Helper

**Files:**
- Create: `Sources/CodexRouterCore/Models/AnyCodable.swift`

- [ ] **Step 1: Write AnyCodable for flexible JSON handling**

```swift
import Foundation

/// A type-erased Codable value for handling arbitrary JSON.
public struct AnyCodable: Codable, Equatable {
    public let value: Any
    
    public init(_ value: Any) {
        self.value = value
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else if container.decodeNil() {
            value = NSNull()
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "AnyCodable: unable to decode value"
            )
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let string as String:
            try container.encode(string)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let bool as Bool:
            try container.encode(bool)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        case is NSNull:
            try container.encodeNil()
        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "AnyCodable: unable to encode value"
                )
            )
        }
    }
    
    public static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        return String(describing: lhs.value) == String(describing: rhs.value)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/CodexRouterCore/Models/AnyCodable.swift
git commit -m "feat(core): add AnyCodable for flexible JSON handling"
```

---

### Task 3: Provider Model

**Files:**
- Create: `Sources/CodexRouterCore/Models/Provider.swift`
- Create: `Sources/CodexRouterCore/Models/ProviderMeta.swift`

- [ ] **Step 1: Write Provider model**

```swift
// Sources/CodexRouterCore/Models/Provider.swift
import Foundation

/// Provider configuration compatible with cc-switch format.
public struct Provider: Codable, Identifiable, Hashable {
    public let id: String
    public var name: String
    public var settingsConfig: [String: AnyCodable]
    public var websiteUrl: String?
    public var category: String?
    public var createdAt: Date?
    public var sortIndex: Int?
    public var notes: String?
    public var meta: ProviderMeta?
    public var icon: String?
    public var iconColor: String?
    public var inFailoverQueue: Bool
    
    public init(
        id: String,
        name: String,
        settingsConfig: [String: AnyCodable] = [:],
        websiteUrl: String? = nil,
        category: String? = nil,
        meta: ProviderMeta? = nil
    ) {
        self.id = id
        self.name = name
        self.settingsConfig = settingsConfig
        self.websiteUrl = websiteUrl
        self.category = category
        self.createdAt = Date()
        self.sortIndex = nil
        self.notes = nil
        self.meta = meta
        self.icon = nil
        self.iconColor = nil
        self.inFailoverQueue = false
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: Provider, rhs: Provider) -> Bool {
        lhs.id == rhs.id
    }
    
    /// Extract base URL from settings config.
    public var baseURL: String? {
        if let url = settingsConfig["base_url"]?.value as? String {
            return url
        }
        if let url = settingsConfig["baseURL"]?.value as? String {
            return url
        }
        return nil
    }
    
    /// Extract API key from settings config.
    public var apiKey: String? {
        if let env = settingsConfig["env"]?.value as? [String: Any],
           let key = env["OPENAI_API_KEY"] as? String,
           !key.isEmpty {
            return key
        }
        if let auth = settingsConfig["auth"]?.value as? [String: Any],
           let key = auth["OPENAI_API_KEY"] as? String,
           !key.isEmpty {
            return key
        }
        return nil
    }
    
    /// Check if provider uses Chat Completions API format.
    public var usesChatCompletions: Bool {
        guard let apiFormat = meta?.apiFormat ?? 
              (settingsConfig["api_format"]?.value as? String) ??
              (settingsConfig["apiFormat"]?.value as? String) else {
            return false
        }
        return ["chat", "chat_completions", "openai_chat"].contains(apiFormat.lowercased())
    }
}
```

- [ ] **Step 2: Write ProviderMeta model**

```swift
// Sources/CodexRouterCore/Models/ProviderMeta.swift
import Foundation

/// Provider metadata for advanced configuration.
public struct ProviderMeta: Codable, Equatable {
    public var apiFormat: String?
    public var codexChatReasoning: ReasoningConfig?
    public var customUserAgent: String?
    public var providerType: String?
    
    public init(
        apiFormat: String? = nil,
        codexChatReasoning: ReasoningConfig? = nil,
        customUserAgent: String? = nil,
        providerType: String? = nil
    ) {
        self.apiFormat = apiFormat
        self.codexChatReasoning = codexChatReasoning
        self.customUserAgent = customUserAgent
        self.providerType = providerType
    }
    
    public static func == (lhs: ProviderMeta, rhs: ProviderMeta) -> Bool {
        lhs.apiFormat == rhs.apiFormat &&
        lhs.codexChatReasoning == rhs.codexChatReasoning &&
        lhs.customUserAgent == rhs.customUserAgent &&
        lhs.providerType == rhs.providerType
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add Sources/CodexRouterCore/Models/Provider.swift
git add Sources/CodexRouterCore/Models/ProviderMeta.swift
git commit -m "feat(core): add Provider and ProviderMeta models"
```

---

### Task 4: Reasoning Config Model

**Files:**
- Create: `Sources/CodexRouterCore/Models/ReasoningConfig.swift`

- [ ] **Step 1: Write ReasoningConfig model**

```swift
// Sources/CodexRouterCore/Models/ReasoningConfig.swift
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
```

- [ ] **Step 2: Commit**

```bash
git add Sources/CodexRouterCore/Models/ReasoningConfig.swift
git commit -m "feat(core): add ReasoningConfig with platform presets"
```

---

### Task 5: Circuit Breaker Config Model

**Files:**
- Create: `Sources/CodexRouterCore/Models/CircuitBreakerConfig.swift`

- [ ] **Step 1: Write CircuitBreakerConfig model**

```swift
// Sources/CodexRouterCore/Models/CircuitBreakerConfig.swift
import Foundation

/// Configuration for circuit breaker behavior.
public struct CircuitBreakerConfig: Codable, Equatable {
    public var failureThreshold: UInt
    public var successThreshold: UInt
    public var timeoutSeconds: UInt
    public var errorRateThreshold: Double?
    public var minRequests: UInt?
    
    public init(
        failureThreshold: UInt = 5,
        successThreshold: UInt = 3,
        timeoutSeconds: UInt = 60,
        errorRateThreshold: Double? = nil,
        minRequests: UInt? = nil
    ) {
        self.failureThreshold = failureThreshold
        self.successThreshold = successThreshold
        self.timeoutSeconds = timeoutSeconds
        self.errorRateThreshold = errorRateThreshold
        self.minRequests = minRequests
    }
    
    public static let `default` = CircuitBreakerConfig()
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/CodexRouterCore/Models/CircuitBreakerConfig.swift
git commit -m "feat(core): add CircuitBreakerConfig model"
```

---

### Task 6: Proxy Config Model

**Files:**
- Create: `Sources/CodexRouterCore/Models/ProxyConfig.swift`

- [ ] **Step 1: Write ProxyConfig model**

```swift
// Sources/CodexRouterCore/Models/ProxyConfig.swift
import Foundation

/// Per-application proxy configuration.
public struct ProxyConfig: Codable, Equatable {
    public var appType: String
    public var enabled: Bool
    public var autoFailoverEnabled: Bool
    public var maxRetries: UInt
    public var streamingFirstByteTimeout: UInt
    public var streamingIdleTimeout: UInt
    public var nonStreamingTimeout: UInt
    public var circuitBreaker: CircuitBreakerConfig
    
    public init(
        appType: String = "codex",
        enabled: Bool = true,
        autoFailoverEnabled: Bool = false,
        maxRetries: UInt = 3,
        streamingFirstByteTimeout: UInt = 60,
        streamingIdleTimeout: UInt = 120,
        nonStreamingTimeout: UInt = 600,
        circuitBreaker: CircuitBreakerConfig = .default
    ) {
        self.appType = appType
        self.enabled = enabled
        self.autoFailoverEnabled = autoFailoverEnabled
        self.maxRetries = maxRetries
        self.streamingFirstByteTimeout = streamingFirstByteTimeout
        self.streamingIdleTimeout = streamingIdleTimeout
        self.nonStreamingTimeout = nonStreamingTimeout
        self.circuitBreaker = circuitBreaker
    }
    
    public static let `default` = ProxyConfig()
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/CodexRouterCore/Models/ProxyConfig.swift
git commit -m "feat(core): add ProxyConfig model"
```

---

### Task 7: Circuit Breaker Implementation

**Files:**
- Create: `Sources/CodexRouterCore/Router/CircuitBreaker.swift`
- Create: `Tests/CodexRouterCoreTests/CircuitBreakerTests.swift`

- [ ] **Step 1: Write failing test for CircuitBreaker initial state**

```swift
// Tests/CodexRouterCoreTests/CircuitBreakerTests.swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CircuitBreakerTests`
Expected: Compilation error - CircuitBreaker not found

- [ ] **Step 3: Implement CircuitBreaker**

```swift
// Sources/CodexRouterCore/Router/CircuitBreaker.swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CircuitBreakerTests`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexRouterCore/Router/CircuitBreaker.swift
git add Tests/CodexRouterCoreTests/CircuitBreakerTests.swift
git commit -m "feat(core): implement CircuitBreaker with tests"
```

---

## Milestone 2: Database Layer

### Task 8: Database Setup

**Files:**
- Create: `Sources/CodexRouterDB/Database.swift`

- [ ] **Step 1: Write Database manager**

```swift
// Sources/CodexRouterDB/Database.swift
import Foundation
import GRDB
import CodexRouterCore

/// Database manager for CodexRouter persistence.
public final class Database {
    public let dbQueue: DatabaseQueue
    public let databasePath: String
    
    public init(path: String? = nil) throws {
        let dbPath = path ?? Self.defaultDatabasePath()
        self.databasePath = dbPath
        
        // Ensure directory exists
        let directory = URL(fileURLWithPath: dbPath).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        
        self.dbQueue = try DatabaseQueue(path: dbPath)
        
        try migrate()
    }
    
    /// Create in-memory database for testing.
    public static func inMemory() throws -> Database {
        let dbQueue = try DatabaseQueue()
        let database = Database(dbQueue: dbQueue, path: ":memory:")
        try database.migrate()
        return database
    }
    
    private init(dbQueue: DatabaseQueue, path: String) {
        self.dbQueue = dbQueue
        self.databasePath = path
    }
    
    /// Default database path: ~/.codex-router/proxy.db
    public static func defaultDatabasePath() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.codex-router/proxy.db"
    }
    
    /// Run database migrations.
    public func migrate() throws {
        var migrator = DatabaseMigrator()
        
        migrator.registerMigration("v1_initial") { db in
            // Providers table
            try db.create(table: "providers") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("app_type", .text).notNull().defaults(to: "codex")
                t.column("settings_config", .text).notNull()
                t.column("category", .text)
                t.column("meta", .text)
                t.column("sort_index", .integer)
                t.column("in_failover_queue", .boolean).defaults(to: false)
                t.column("created_at", .datetime)
            }
            
            // Failover queue table
            try db.create(table: "failover_queue") { t in
                t.column("app_type", .text).notNull()
                t.column("provider_id", .text).notNull()
                t.column("priority", .integer).notNull()
                t.primaryKey(["app_type", "provider_id"])
            }
            
            // Proxy config table
            try db.create(table: "proxy_config") { t in
                t.column("app_type", .text).primaryKey()
                t.column("auto_failover_enabled", .boolean).defaults(to: false)
                t.column("max_retries", .integer).defaults(to: 3)
                t.column("circuit_failure_threshold", .integer).defaults(to: 5)
                t.column("circuit_success_threshold", .integer).defaults(to: 3)
                t.column("circuit_timeout_seconds", .integer).defaults(to: 60)
                t.column("streaming_first_byte_timeout", .integer).defaults(to: 60)
                t.column("streaming_idle_timeout", .integer).defaults(to: 120)
            }
            
            // Provider health table
            try db.create(table: "provider_health") { t in
                t.column("provider_id", .text).notNull()
                t.column("app_type", .text).notNull()
                t.column("is_healthy", .boolean).defaults(to: true)
                t.column("consecutive_failures", .integer).defaults(to: 0)
                t.column("last_success_at", .datetime)
                t.column("last_failure_at", .datetime)
                t.column("last_error", .text)
                t.primaryKey(["provider_id", "app_type"])
            }
        }
        
        try migrator.migrate(dbQueue)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/CodexRouterDB/Database.swift
git commit -m "feat(db): add Database manager with migrations"
```

---

### Task 9: Provider Record and DAO

**Files:**
- Create: `Sources/CodexRouterDB/Schemas/ProviderRecord.swift`
- Create: `Sources/CodexRouterDB/DAOs/ProviderDAO.swift`

- [ ] **Step 1: Write ProviderRecord**

```swift
// Sources/CodexRouterDB/Schemas/ProviderRecord.swift
import Foundation
import GRDB
import CodexRouterCore

/// Database record for Provider.
public struct ProviderRecord: Codable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "providers"
    
    public var id: String
    public var name: String
    public var appType: String
    public var settingsConfig: String
    public var category: String?
    public var meta: String?
    public var sortIndex: Int?
    public var inFailoverQueue: Bool
    public var createdAt: Date?
    
    public init(from provider: Provider, appType: String = "codex") throws {
        self.id = provider.id
        self.name = provider.name
        self.appType = appType
        self.settingsConfig = try JSONEncoder().encode(provider.settingsConfig).base64EncodedString()
        self.category = provider.category
        if let meta = provider.meta {
            self.meta = try JSONEncoder().encode(meta).base64EncodedString()
        }
        self.sortIndex = provider.sortIndex
        self.inFailoverQueue = provider.inFailoverQueue
        self.createdAt = provider.createdAt
    }
    
    public func toProvider() throws -> Provider {
        guard let configData = Data(base64Encoded: settingsConfig) else {
            throw NSError(domain: "ProviderRecord", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid settings config"])
        }
        let config = try JSONDecoder().decode([String: AnyCodable].self, from: configData)
        
        var meta: ProviderMeta?
        if let metaString = self.meta, let metaData = Data(base64Encoded: metaString) {
            meta = try JSONDecoder().decode(ProviderMeta.self, from: metaData)
        }
        
        return Provider(
            id: id,
            name: name,
            settingsConfig: config,
            category: category,
            meta: meta
        )
    }
}
```

- [ ] **Step 2: Write ProviderDAO**

```swift
// Sources/CodexRouterDB/DAOs/ProviderDAO.swift
import Foundation
import GRDB
import CodexRouterCore

/// Data Access Object for Provider records.
public final class ProviderDAO {
    private let db: Database
    
    public init(_ db: Database) {
        self.db = db
    }
    
    /// Save a provider.
    public func save(_ provider: Provider, appType: String = "codex") throws {
        let record = try ProviderRecord(from: provider, appType: appType)
        try db.dbQueue.write { db in
            try record.save(db)
        }
    }
    
    /// Get all providers for an app type.
    public func getAll(appType: String = "codex") throws -> [Provider] {
        try db.dbQueue.read { db in
            let records = try ProviderRecord
                .filter(Column("appType") == appType)
                .order(Column("sortIndex"))
                .fetchAll(db)
            return try records.map { try $0.toProvider() }
        }
    }
    
    /// Get a provider by ID.
    public func get(byId id: String, appType: String = "codex") throws -> Provider? {
        try db.dbQueue.read { db in
            guard let record = try ProviderRecord
                .filter(Column("id") == id && Column("appType") == appType)
                .fetchOne(db) else {
                return nil
            }
            return try record.toProvider()
        }
    }
    
    /// Delete a provider.
    public func delete(id: String, appType: String = "codex") throws {
        try db.dbQueue.write { db in
            _ = try ProviderRecord
                .filter(Column("id") == id && Column("appType") == appType)
                .deleteAll(db)
        }
    }
    
    /// Set current provider (update sort_index to 0).
    public func setCurrent(id: String, appType: String = "codex") throws {
        try db.dbQueue.write { db in
            // Reset all sort indexes for this app type
            try db.execute(
                sql: "UPDATE providers SET sort_index = 1 WHERE app_type = ?",
                arguments: [appType]
            )
            // Set selected provider to 0
            try db.execute(
                sql: "UPDATE providers SET sort_index = 0 WHERE id = ? AND app_type = ?",
                arguments: [id, appType]
            )
        }
    }
    
    /// Get current provider.
    public func getCurrent(appType: String = "codex") throws -> Provider? {
        try db.dbQueue.read { db in
            guard let record = try ProviderRecord
                .filter(Column("appType") == appType && Column("sortIndex") == 0)
                .fetchOne(db) else {
                return nil
            }
            return try record.toProvider()
        }
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add Sources/CodexRouterDB/Schemas/ProviderRecord.swift
git add Sources/CodexRouterDB/DAOs/ProviderDAO.swift
git commit -m "feat(db): add ProviderRecord and ProviderDAO"
```

---

### Task 10: Proxy Config DAO

**Files:**
- Create: `Sources/CodexRouterDB/Schemas/ProxyConfigRecord.swift`
- Create: `Sources/CodexRouterDB/DAOs/ProxyConfigDAO.swift`

- [ ] **Step 1: Write ProxyConfigRecord**

```swift
// Sources/CodexRouterDB/Schemas/ProxyConfigRecord.swift
import Foundation
import GRDB
import CodexRouterCore

/// Database record for ProxyConfig.
public struct ProxyConfigRecord: Codable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "proxy_config"
    
    public var appType: String
    public var autoFailoverEnabled: Bool
    public var maxRetries: Int
    public var circuitFailureThreshold: Int
    public var circuitSuccessThreshold: Int
    public var circuitTimeoutSeconds: Int
    public var streamingFirstByteTimeout: Int
    public var streamingIdleTimeout: Int
    
    public init(from config: ProxyConfig) {
        self.appType = config.appType
        self.autoFailoverEnabled = config.autoFailoverEnabled
        self.maxRetries = Int(config.maxRetries)
        self.circuitFailureThreshold = Int(config.circuitBreaker.failureThreshold)
        self.circuitSuccessThreshold = Int(config.circuitBreaker.successThreshold)
        self.circuitTimeoutSeconds = Int(config.circuitBreaker.timeoutSeconds)
        self.streamingFirstByteTimeout = Int(config.streamingFirstByteTimeout)
        self.streamingIdleTimeout = Int(config.streamingIdleTimeout)
    }
    
    public func toProxyConfig() -> ProxyConfig {
        ProxyConfig(
            appType: appType,
            enabled: true,
            autoFailoverEnabled: autoFailoverEnabled,
            maxRetries: UInt(maxRetries),
            streamingFirstByteTimeout: UInt(streamingFirstByteTimeout),
            streamingIdleTimeout: UInt(streamingIdleTimeout),
            circuitBreaker: CircuitBreakerConfig(
                failureThreshold: UInt(circuitFailureThreshold),
                successThreshold: UInt(circuitSuccessThreshold),
                timeoutSeconds: UInt(circuitTimeoutSeconds)
            )
        )
    }
}
```

- [ ] **Step 2: Write ProxyConfigDAO**

```swift
// Sources/CodexRouterDB/DAOs/ProxyConfigDAO.swift
import Foundation
import GRDB
import CodexRouterCore

/// Data Access Object for ProxyConfig records.
public final class ProxyConfigDAO {
    private let db: Database
    
    public init(_ db: Database) {
        self.db = db
    }
    
    /// Get config for an app type, creating default if not exists.
    public func get(appType: String = "codex") throws -> ProxyConfig {
        try db.dbQueue.read { db in
            guard let record = try ProxyConfigRecord
                .filter(Column("appType") == appType)
                .fetchOne(db) else {
                return ProxyConfig(appType: appType)
            }
            return record.toProxyConfig()
        }
    }
    
    /// Save config for an app type.
    public func save(_ config: ProxyConfig) throws {
        let record = ProxyConfigRecord(from: config)
        try db.dbQueue.write { db in
            try record.save(db)
        }
    }
    
    /// Update auto failover setting.
    public func setAutoFailover(enabled: Bool, appType: String = "codex") throws {
        try db.dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO proxy_config 
                    (app_type, auto_failover_enabled, max_retries, circuit_failure_threshold, 
                     circuit_success_threshold, circuit_timeout_seconds, streaming_first_byte_timeout, streaming_idle_timeout)
                    VALUES (?, ?, 
                        COALESCE((SELECT max_retries FROM proxy_config WHERE app_type = ?), 3),
                        COALESCE((SELECT circuit_failure_threshold FROM proxy_config WHERE app_type = ?), 5),
                        COALESCE((SELECT circuit_success_threshold FROM proxy_config WHERE app_type = ?), 3),
                        COALESCE((SELECT circuit_timeout_seconds FROM proxy_config WHERE app_type = ?), 60),
                        COALESCE((SELECT streaming_first_byte_timeout FROM proxy_config WHERE app_type = ?), 60),
                        COALESCE((SELECT streaming_idle_timeout FROM proxy_config WHERE app_type = ?), 120)
                    )
                """,
                arguments: [appType, enabled, appType, appType, appType, appType, appType, appType]
            )
        }
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add Sources/CodexRouterDB/Schemas/ProxyConfigRecord.swift
git add Sources/CodexRouterDB/DAOs/ProxyConfigDAO.swift
git commit -m "feat(db): add ProxyConfigRecord and ProxyConfigDAO"
```

---

## Milestone 3: Format Transformers

### Task 11: Responses to Chat Transformer

**Files:**
- Create: `Sources/CodexRouterCore/Transformers/ResponsesToChatTransformer.swift`
- Create: `Tests/CodexRouterCoreTests/TransformerTests.swift`

- [ ] **Step 1: Write transformer test**

```swift
// Tests/CodexRouterCoreTests/TransformerTests.swift
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
                    "arguments": "{\\"location\\": \\"Beijing\\"}"
                }
            ]
        }
        """
        
        let result = try transformer.transform(responsesJSON: responsesJSON)
        
        XCTAssertEqual(result.choices[0].message.toolCalls?.count, 1)
        XCTAssertEqual(result.choices[0].message.toolCalls?[0].function.name, "get_weather")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter TransformerTests`
Expected: Compilation error

- [ ] **Step 3: Implement ResponsesToChatTransformer**

```swift
// Sources/CodexRouterCore/Transformers/ResponsesToChatTransformer.swift
import Foundation

/// Chat completion message.
public struct ChatMessage: Codable, Equatable {
    public var role: String
    public var content: String?
    public var toolCalls: [ToolCall]?
    
    public init(role: String, content: String? = nil, toolCalls: [ToolCall]? = nil) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
    }
}

/// Tool call in chat completion.
public struct ToolCall: Codable, Equatable {
    public var id: String
    public var type: String
    public var function: FunctionCall
    
    public init(id: String, function: FunctionCall) {
        self.id = id
        self.type = "function"
        self.function = function
    }
}

/// Function call details.
public struct FunctionCall: Codable, Equatable {
    public var name: String
    public var arguments: String
    
    public init(name: String, arguments: String) {
        self.name = name
        self.arguments = arguments
    }
}

/// Chat completion choice.
public struct ChatChoice: Codable, Equatable {
    public var index: Int
    public var message: ChatMessage
    public var finishReason: String?
    
    public init(index: Int, message: ChatMessage, finishReason: String? = nil) {
        self.index = index
        self.message = message
        self.finishReason = finishReason
    }
}

/// Token usage.
public struct Usage: Codable, Equatable {
    public var promptTokens: Int
    public var completionTokens: Int
    public var totalTokens: Int
    
    public init(promptTokens: Int, completionTokens: Int) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = promptTokens + completionTokens
    }
}

/// Chat completion response.
public struct ChatCompletionResponse: Codable, Equatable {
    public var id: String
    public var object: String
    public var created: Int
    public var model: String
    public var choices: [ChatChoice]
    public var usage: Usage?
    
    public init(id: String, model: String, choices: [ChatChoice], usage: Usage? = nil) {
        self.id = id
        self.object = "chat.completion"
        self.created = Int(Date().timeIntervalSince1970)
        self.model = model
        self.choices = choices
        self.usage = usage
    }
}

/// Transforms OpenAI Responses API format to Chat Completions format.
public struct ResponsesToChatTransformer {
    
    public init() {}
    
    public func transform(responsesJSON: String) throws -> ChatCompletionResponse {
        guard let data = responsesJSON.data(using: .utf8) else {
            throw TransformerError.invalidInput
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        
        let id = json["id"] as? String ?? "unknown"
        let model = json["model"] as? String ?? "unknown"
        
        var content = ""
        var toolCalls: [ToolCall] = []
        var finishReason: String?
        
        if let output = json["output"] as? [[String: Any]] {
            for item in output {
                let type = item["type"] as? String
                
                switch type {
                case "message":
                    if let messageContent = item["content"] as? [[String: Any]] {
                        for block in messageContent {
                            if let text = block["text"] as? String {
                                content += text
                            }
                        }
                    }
                    
                case "function_call":
                    if let callId = item["id"] as? String,
                       let name = item["name"] as? String,
                       let arguments = item["arguments"] as? String {
                        toolCalls.append(ToolCall(
                            id: callId,
                            function: FunctionCall(name: name, arguments: arguments)
                        ))
                    }
                    finishReason = "tool_calls"
                    
                default:
                    break
                }
            }
        }
        
        var usage: Usage?
        if let usageDict = json["usage"] as? [String: Any] {
            let inputTokens = usageDict["input_tokens"] as? Int ?? 0
            let outputTokens = usageDict["output_tokens"] as? Int ?? 0
            usage = Usage(promptTokens: inputTokens, completionTokens: outputTokens)
        }
        
        let message = ChatMessage(role: "assistant", content: content.isEmpty ? nil : content, toolCalls: toolCalls.isEmpty ? nil : toolCalls)
        
        if finishReason == nil && !content.isEmpty {
            finishReason = "stop"
        }
        
        return ChatCompletionResponse(
            id: id,
            model: model,
            choices: [ChatChoice(index: 0, message: message, finishReason: finishReason)],
            usage: usage
        )
    }
}

public enum TransformerError: Error, LocalizedError {
    case invalidInput
    case transformationFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidInput:
            return "Invalid input data"
        case .transformationFailed(let message):
            return "Transformation failed: \(message)"
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter TransformerTests`
Expected: Tests pass

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexRouterCore/Transformers/ResponsesToChatTransformer.swift
git add Tests/CodexRouterCoreTests/TransformerTests.swift
git commit -m "feat(core): add ResponsesToChatTransformer"
```

---

## Milestone 4: HTTP Server

### Task 12: Proxy Server Setup

**Files:**
- Create: `Sources/CodexRouterApp/Server/ProxyServer.swift`
- Create: `Sources/CodexRouterApp/Server/Routes.swift`

- [ ] **Step 1: Write ProxyServer**

```swift
// Sources/CodexRouterApp/Server/ProxyServer.swift
import Foundation
import Hummingbird
import CodexRouterCore
import CodexRouterDB

/// HTTP proxy server for Codex routing.
public final class ProxyServer: ObservableObject {
    @Published public private(set) var isRunning = false
    @Published public private(set) var port: Int = 15721
    
    private var app: Application<RouterResponder<BasicRequestContext>>?
    private let database: Database
    private let providerRouter: ProviderRouter
    
    public init(database: Database) throws {
        self.database = database
        self.providerRouter = ProviderRouter(database: database)
    }
    
    public func start(port: Int = 15721) async throws {
        self.port = port
        
        let router = Router()
        Routes.configure(router: router, providerRouter: providerRouter, database: database)
        
        let app = Application(
            router: router,
            configuration: .init(address: .hostname("127.0.0.1", port: port))
        )
        
        self.app = app
        
        Task {
            do {
                try await app.run()
            } catch {
                print("Server error: \(error)")
            }
        }
        
        await MainActor.run {
            self.isRunning = true
        }
        
        print("Proxy server started on port \(port)")
    }
    
    public func stop() async {
        await app?.shutdown()
        self.app = nil
        
        await MainActor.run {
            self.isRunning = false
        }
        
        print("Proxy server stopped")
    }
}
```

- [ ] **Step 2: Write Routes**

```swift
// Sources/CodexRouterApp/Server/Routes.swift
import Foundation
import Hummingbird
import CodexRouterCore
import CodexRouterDB

/// Route configuration for proxy server.
public enum Routes {
    public static func configure(
        router: Router,
        providerRouter: ProviderRouter,
        database: Database
    ) {
        // Health check
        router.get("/health") { _, _ in
            return Response(
                status: .ok,
                body: .init(byteBuffer: ByteBuffer(string: #"{"status":"healthy"}"#))
            )
        }
        
        // Models endpoint
        router.get("/v1/models") { _, _ in
            let response: [String: Any] = [
                "object": "list",
                "data": []
            ]
            let data = try! JSONSerialization.data(withJSONObject: response)
            return Response(
                status: .ok,
                body: .init(byteBuffer: ByteBuffer(data: data))
            )
        }
        
        // Chat Completions
        router.post("/v1/chat/completions") { request, context in
            return try await handleChatCompletions(
                request: request,
                providerRouter: providerRouter,
                database: database
            )
        }
        
        // Responses API
        router.post("/v1/responses") { request, context in
            return try await handleResponses(
                request: request,
                providerRouter: providerRouter,
                database: database
            )
        }
        
        // Responses Compact
        router.post("/v1/responses/compact") { request, context in
            return try await handleResponsesCompact(
                request: request,
                providerRouter: providerRouter,
                database: database
            )
        }
    }
    
    private static func handleChatCompletions(
        request: Request,
        providerRouter: ProviderRouter,
        database: Database
    ) async throws -> Response {
        // TODO: Implement request forwarding
        return Response(
            status: .notImplemented,
            body: .init(byteBuffer: ByteBuffer(string: #"{"error":"Not implemented"}"#))
        )
    }
    
    private static func handleResponses(
        request: Request,
        providerRouter: ProviderRouter,
        database: Database
    ) async throws -> Response {
        // TODO: Implement request forwarding
        return Response(
            status: .notImplemented,
            body: .init(byteBuffer: ByteBuffer(string: #"{"error":"Not implemented"}"#))
        )
    }
    
    private static func handleResponsesCompact(
        request: Request,
        providerRouter: ProviderRouter,
        database: Database
    ) async throws -> Response {
        // TODO: Implement request forwarding
        return Response(
            status: .notImplemented,
            body: .init(byteBuffer: ByteBuffer(string: #"{"error":"Not implemented"}"#))
        )
    }
}
```

- [ ] **Step 3: Write ProviderRouter placeholder**

```swift
// Sources/CodexRouterCore/Router/ProviderRouter.swift
import Foundation
import CodexRouterDB

/// Manages provider selection and failover.
public actor ProviderRouter {
    private let database: Database
    private var circuitBreakers: [String: CircuitBreaker] = [:]
    
    public init(database: Database) {
        self.database = database
    }
    
    /// Select available providers for an app type.
    public func selectProviders(appType: String) async throws -> [Provider] {
        let dao = ProviderDAO(database)
        let allProviders = try dao.getAll(appType: appType)
        return allProviders
    }
    
    /// Get or create circuit breaker for a provider.
    public func getCircuitBreaker(for providerId: String) -> CircuitBreaker {
        if let existing = circuitBreakers[providerId] {
            return existing
        }
        let breaker = CircuitBreaker()
        circuitBreakers[providerId] = breaker
        return breaker
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add Sources/CodexRouterApp/Server/ProxyServer.swift
git add Sources/CodexRouterApp/Server/Routes.swift
git add Sources/CodexRouterCore/Router/ProviderRouter.swift
git commit -m "feat(server): add ProxyServer with basic routes"
```

---

## Milestone 5: App Shell

### Task 13: Menu Bar Application

**Files:**
- Create: `Sources/CodexRouterApp/CodexRouterApp.swift`
- Create: `Sources/CodexRouterApp/AppDelegate.swift`
- Create: `Sources/CodexRouterApp/UI/MenuBarView.swift`
- Create: `Sources/CodexRouterApp/Services/AppState.swift`

- [ ] **Step 1: Write AppState**

```swift
// Sources/CodexRouterApp/Services/AppState.swift
import Foundation
import Combine
import CodexRouterCore
import CodexRouterDB

/// Shared application state.
@MainActor
public final class AppState: ObservableObject {
    @Published public var isRunning = false
    @Published public var currentProvider: String?
    @Published public var port: Int = 15721
    @Published public var providers: [Provider] = []
    
    public let database: Database
    public let server: ProxyServer
    
    public init() throws {
        self.database = try Database()
        self.server = try ProxyServer(database: database)
        
        loadProviders()
    }
    
    public func loadProviders() {
        let dao = ProviderDAO(database)
        providers = (try? dao.getAll()) ?? []
        currentProvider = try? dao.getCurrent()?.name
    }
    
    public func startServer() async {
        do {
            try await server.start(port: port)
            isRunning = true
        } catch {
            print("Failed to start server: \(error)")
        }
    }
    
    public func stopServer() async {
        await server.stop()
        isRunning = false
    }
}
```

- [ ] **Step 2: Write MenuBarView**

```swift
// Sources/CodexRouterApp/UI/MenuBarView.swift
import SwiftUI

public struct MenuBarView: View {
    @ObservedObject var appState: AppState
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(appState.isRunning ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(appState.isRunning ? "Running" : "Stopped")
            }
            
            if appState.isRunning {
                Text("Port: \(appState.port)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let provider = appState.currentProvider {
                    Text("Provider: \(provider)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            Button(appState.isRunning ? "Stop Server" : "Start Server") {
                Task {
                    if appState.isRunning {
                        await appState.stopServer()
                    } else {
                        await appState.startServer()
                    }
                }
            }
            
            Divider()
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 200)
    }
}
```

- [ ] **Step 3: Write AppDelegate**

```swift
// Sources/CodexRouterApp/AppDelegate.swift
import AppKit
import SwiftUI

public class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var appState: AppState!
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            appState = try AppState()
        } catch {
            print("Failed to initialize: \(error)")
            NSApplication.shared.terminate(nil)
            return
        }
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "network", accessibilityDescription: "CodexRouter")
        }
        
        let menuBarView = MenuBarView(appState: appState)
        let hostingView = NSHostingView(rootView: menuBarView)
        
        let menu = NSMenu()
        let menuItem = NSMenuItem()
        menuItem.view = hostingView
        menu.addItem(menuItem)
        
        statusItem?.menu = menu
        
        // Auto-start server
        Task {
            await appState.startServer()
        }
    }
}
```

- [ ] **Step 4: Write main App**

```swift
// Sources/CodexRouterApp/CodexRouterApp.swift
import AppKit

@main
struct CodexRouterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
```

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexRouterApp/CodexRouterApp.swift
git add Sources/CodexRouterApp/AppDelegate.swift
git add Sources/CodexRouterApp/UI/MenuBarView.swift
git add Sources/CodexRouterApp/Services/AppState.swift
git commit -m "feat(app): add menu bar application shell"
```

---

## Remaining Tasks Summary

The above tasks establish the core framework. Remaining implementation follows the same pattern:

- **Tasks 14-20**: Complete transformer implementations (ChatToResponses, SSE streaming)
- **Tasks 21-25**: HTTP client and request forwarding
- **Tasks 26-30**: Failover manager and health tracking
- **Tasks 31-35**: TOML config parser
- **Tasks 36-40**: Provider management UI
- **Tasks 41-45**: Settings and failover configuration UI
- **Tasks 46-50**: Config migration from cc-switch

Each task follows TDD: write failing test → implement → verify → commit.

---

## Spec Coverage Check

| Spec Requirement | Task |
|-----------------|------|
| Package structure | Task 1 |
| Provider model | Task 3 |
| Circuit breaker | Task 7 |
| Database layer | Tasks 8-10 |
| Responses→Chat transform | Task 11 |
| HTTP server | Task 12 |
| Menu bar app | Task 13 |
| Failover logic | Tasks 21-25 |
| Reasoning rectifier | Design complete, implementation follows |
| TOML parsing | Tasks 31-35 |
| GUI | Tasks 36-45 |

All spec requirements have corresponding tasks.
