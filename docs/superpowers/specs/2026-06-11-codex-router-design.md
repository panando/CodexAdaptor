# CodexRouter 设计文档

## 概述

从 cc-switch 项目中提取 Codex 本地路由功能，用 Swift 实现为独立模块，最终整合到 APIbypass 项目。

## 目标

1. **阶段一**：独立的 macOS 菜单栏应用，提供完整的 Codex 本地代理功能
2. **阶段二**：提取核心模块为 Swift Package，整合到 APIbypass

## 功能范围

与 cc-switch 的 Codex 功能对等：

- HTTP 代理服务器（Chat Completions、Responses API、Models 端点）
- Provider 管理（多上游配置、API Key 存储）
- 故障转移队列（按优先级自动切换）
- 熔断器（失败阈值、自动恢复）
- Responses ↔ Chat Completions 格式转换
- reasoning 参数整流（DeepSeek、Kimi、Qwen 等平台适配）
- Codex TOML 配置解析与写入

## 架构设计

### 模块划分

```
CodexRouter/
├── Sources/
│   ├── CodexRouterCore/        # 核心库（可嵌入 APIbypass）
│   │   ├── Models/             # 数据模型
│   │   ├── Router/             # 路由选择、熔断器、故障转移
│   │   ├── Transformers/       # Responses↔Chat 转换、整流器
│   │   ├── Config/             # TOML 解析、配置迁移
│   │   └── Networking/         # HTTP 客户端、SSE 解析
│   │
│   ├── CodexRouterDB/          # 数据库层（GRDB）
│   │   ├── Database.swift
│   │   ├── Schemas/
│   │   └── DAOs/
│   │
│   └── CodexRouterApp/         # 菜单栏应用（整合后删除）
│       ├── App.swift
│       ├── Server/
│       └── UI/
│
└── Tests/
```

### 核心组件

#### 1. Provider 模型

与 cc-switch 配置格式兼容：

```swift
struct Provider: Codable, Identifiable {
    let id: String
    var name: String
    var settingsConfig: [String: AnyCodable]
    var category: String?
    var meta: ProviderMeta?
    var inFailoverQueue: Bool
}

struct ProviderMeta: Codable {
    var apiFormat: String?           // "responses" | "chat"
    var codexChatReasoning: ReasoningConfig?
    var customUserAgent: String?
}
```

#### 2. 熔断器

```swift
actor CircuitBreaker {
    enum State { case closed, open, halfOpen }
    
    let config: CircuitBreakerConfig
    private var state: State = .closed
    private var failureCount: UInt = 0
    
    func allowRequest() -> Bool
    func recordSuccess()
    func recordFailure()
    func reset()
}

struct CircuitBreakerConfig {
    var failureThreshold: UInt = 5
    var successThreshold: UInt = 3
    var timeoutSeconds: UInt = 60
}
```

#### 3. Provider 路由器

```swift
actor ProviderRouter {
    func selectProviders(appType: String) async throws -> [Provider]
    func allowProviderRequest(providerId: String, appType: String) async -> Bool
    func recordResult(providerId: String, appType: String, success: Bool) async
    func resetCircuitBreaker(providerId: String, appType: String) async
}
```

#### 4. 格式转换器

```swift
// Responses → Chat Completions
struct ResponsesToChatTransformer {
    func transform(_ responses: ResponsesAPIResponse) -> ChatCompletionResponse
    func transformStream(_ sse: AsyncThrowingStream<Data, Error>) -> AsyncThrowingStream<String, Error>
}

// Chat Completions → Responses
struct ChatToResponsesTransformer {
    func transform(_ chat: ChatCompletionResponse) -> ResponsesAPIResponse
    func transformStream(_ sse: AsyncThrowingStream<Data, Error>) -> AsyncThrowingStream<String, Error>
}
```

#### 5. Reasoning 整流器

针对不同平台的 reasoning 参数适配：

```swift
struct ReasoningRectifier {
    func rectifyRequest(
        _ request: inout [String: Any],
        provider: Provider,
        platform: ReasoningPlatform
    )
    
    func rectifyResponse(
        _ response: inout [String: Any],
        provider: Provider,
        platform: ReasoningPlatform
    )
}

enum ReasoningPlatform {
    case deepseek      // thinking + reasoning_effort
    case openrouter    // reasoning.effort
    case siliconflow   // enable_thinking
    case kimi          // thinking
    case qwen          // enable_thinking
    case minimax       // reasoning_split
    case standard      // 无特殊处理
}
```

### 数据存储

**存储位置**：`~/.codex-router/`

```
~/.codex-router/
├── config.json          # 主配置
├── proxy.db             # SQLite 数据库
└── codex-backup/        # Codex 原始配置备份
```

**数据库 Schema**（与 cc-switch 兼容）：

```sql
CREATE TABLE providers (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    app_type TEXT NOT NULL DEFAULT 'codex',
    settings_config TEXT NOT NULL,
    category TEXT,
    meta TEXT,
    sort_index INTEGER,
    in_failover_queue BOOLEAN DEFAULT 0,
    created_at INTEGER
);

CREATE TABLE failover_queue (
    app_type TEXT NOT NULL,
    provider_id TEXT NOT NULL,
    priority INTEGER NOT NULL,
    PRIMARY KEY (app_type, provider_id)
);

CREATE TABLE proxy_config (
    app_type TEXT PRIMARY KEY,
    auto_failover_enabled BOOLEAN DEFAULT 0,
    max_retries INTEGER DEFAULT 3,
    circuit_failure_threshold INTEGER DEFAULT 5,
    circuit_success_threshold INTEGER DEFAULT 3,
    circuit_timeout_seconds INTEGER DEFAULT 60,
    streaming_first_byte_timeout INTEGER DEFAULT 60,
    streaming_idle_timeout INTEGER DEFAULT 120
);

CREATE TABLE provider_health (
    provider_id TEXT NOT NULL,
    app_type TEXT NOT NULL,
    is_healthy BOOLEAN DEFAULT 1,
    consecutive_failures INTEGER DEFAULT 0,
    last_success_at INTEGER,
    last_failure_at INTEGER,
    last_error TEXT,
    PRIMARY KEY (provider_id, app_type)
);
```

### HTTP 端点

```
POST /v1/chat/completions     → Chat Completions API（透传或转换）
POST /v1/responses            → Responses API（透传或转换）
POST /v1/responses/compact    → Responses Compact API
GET  /v1/models               → 模型列表（返回 Codex catalog）
GET  /health                  → 健康检查
GET  /status                  → 代理状态
```

### 请求处理流程

```
1. 接收请求 → 解析 endpoint 和 body
2. ProviderRouter 选择可用 Provider（检查熔断器状态）
3. 如果启用故障转移，按队列顺序尝试
4. 根据 Provider 配置决定是否需要格式转换
5. 发送请求到上游 API
6. 处理响应（转换格式、记录使用量、更新熔断器状态）
7. 返回响应给客户端
```

### 故障转移逻辑

```
1. 检查 auto_failover_enabled 配置
2. 如果启用：
   a. 从 failover_queue 按优先级获取 Provider 列表
   b. 跳过熔断器打开的 Provider
   c. 按顺序尝试，直到成功或全部失败
3. 如果禁用：
   a. 仅使用当前选中的 Provider
   b. 失败直接返回错误
```

## 技术选型

| 组件 | 选择 | 理由 |
|------|------|------|
| HTTP 服务器 | Hummingbird 2.0 | 与 APIbypass 一致，异步架构 |
| 数据库 | GRDB.swift | SQLite 封装，类型安全 |
| TOML 解析 | TOMLKit | 兼容 Swift 5.9，支持编辑操作 |
| JSON 编解码 | Codable | Swift 原生 |
| 并发模型 | async/await + actor | Swift 原生并发 |

## 与 APIbypass 整合路径

### 阶段一：独立开发

1. 实现完整功能
2. 模块化设计确保核心代码可复用
3. 配置格式与 cc-switch 兼容

### 阶段二：整合

1. 将 `CodexRouterCore` 和 `CodexRouterDB` 移入 APIbypass
2. 删除 `CodexRouterApp` 层
3. 在 APIbypass 的 `HTTPServer` 添加 Codex 端点
4. 复用 APIbypass 现有基础设施：
   - `NetworkService` → HTTP 客户端
   - `KeychainService` → API Key 存储
   - `AsyncSemaphore` → 并发控制
   - SSE 解析逻辑

## 配置迁移

支持从 cc-switch 导入配置：

1. 读取 `~/.cc-switch/config.json`
2. 提取 `codex` 类型的 Provider
3. 转换并写入 `~/.codex-router/config.json`
4. 保持原始配置不变

## GUI 功能

菜单栏应用提供：

1. **状态显示**：代理运行状态、当前 Provider、端口
2. **Provider 管理**：添加、编辑、删除、排序
3. **故障转移配置**：启用/禁用、队列管理
4. **熔断器状态**：查看和重置
5. **日志查看**：请求记录、错误日志

## 测试策略

1. **单元测试**：
   - 熔断器状态转换
   - 格式转换正确性
   - Reasoning 整流器
   - TOML 解析

2. **集成测试**：
   - 端到端请求转发
   - 故障转移切换
   - 配置持久化

3. **兼容性测试**：
   - 与 cc-switch 配置格式兼容
   - 与官方 Codex CLI 兼容

## 里程碑

1. **M1**：核心框架搭建（Package 结构、基础模型）
2. **M2**：代理服务器实现（Hummingbird 端点、请求转发）
3. **M3**：格式转换器（Responses↔Chat、流式处理）
4. **M4**：熔断器与故障转移
5. **M5**：GUI 实现
6. **M6**：配置迁移工具
7. **M7**：测试与文档
