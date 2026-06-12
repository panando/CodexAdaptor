# CodexAdaptor 增强设计文档

## 概述

在现有 CodexRouter 代码基础上增强供应商管理、模型目录自定义和思考强度配置功能。参考 cc-switch 和 EchoBird 的实现模式。

## 实现优先级

1. **Codex 能正常启动** — config.toml 管理正确，Codex CLI 不报错
2. **第三方模型接入 Codex** — 模型在 Codex 模型选择器中正确显示自定义名称
3. **模型正确调用** — 协议转换、推理适配正常工作
4. **UI 优化** — 界面美观、操作流畅

## 现有代码评估

### 保留并增强的部分
- `ProxyServer` / `RequestHandler` — 代理核心，已能正确转发和转换协议
- `CodexConfigService` — TOML 配置管理，需增强模型目录和推理配置
- `ReasoningRectifier` — 推理参数适配，需支持 per-provider 手动覆盖
- `ChatToResponsesStreamTransformer` — SSE 流式转换，已验证可用
- `ProvidersView` / `ProviderFormView` — 供应商 UI，需扩展字段

### 需要移除或替换的部分
- `CodexRouterDB` — 整个模块已写完但未接入，当前 TOML 直读模式足够用，移除以减少维护负担
- `MenuBarView.swift` — 未被使用，AppDelegate 用 NSMenu 构建菜单

## 功能设计

### 1. Codex 配置管理 (~/.codex/config.toml)

参考 EchoBird 写入规范的 13 行 config.toml：

```toml
model_provider = "custom"
model = "<model_id>"
model_reasoning_effort = "high"
disable_response_storage = true

[model_providers.custom]
name = "<provider_name>"
base_url = "http://127.0.0.1:15721/v1"
wire_api = "responses"
experimental_bearer_token = "<api_key>"
```

关键点：
- `base_url` 始终指向本地代理 `127.0.0.1:15721/v1`
- `wire_api` 始终设为 `"responses"`（Codex 用 Responses API 与代理通信）
- `experimental_bearer_token` 存放上游 API Key（参考 cc-switch 的做法）
- 模型目录 JSON 文件（`model_catalog_json` 字段）自动注入

### 2. 模型目录自定义

**参照 cc-switch 实现** (`cc-switch/src-tauri/src/codex_config.rs`):

```
用户模型配置 → ModelCatalog JSON 文件 → config.toml 注入字段
```

流程：
1. 用户在 `ProviderFormView` 中为每个供应商配置模型列表（slug/id、display_name、context_window）
2. `ModelCatalogService.generateModelCatalogJSON()` 从 Codex 内置模板（`gpt-5.5`）克隆结构，替换模型条目
3. 写入 `~/.codex/<provider-id>-model-catalog.json`
4. 在 `config.toml` 中添加/更新 `model_catalog_json = "<provider-id>-model-catalog.json"`
5. Codex 启动时读取该文件，在模型选择器中显示自定义 display_name

**注意**：参考 cc-switch，生成模型目录时清除 `additional_speed_tiers`、`availability_nux`、`upgrade` 等 OpenAI 专属字段。

### 3. 思考强度配置

增强 `ReasoningRectifier`，支持 per-provider 手动配置：

在 `ProviderFormView` 中新增推理配置子表单：
- `supportsThinking` — 是否支持推理（布尔值）
- `thinkingParam` — 推理参数名（thinking / enable_thinking / reasoning）
- `effortValueMode` — 努力值表达方式（deepseek: 直接数值 / openrouter: reasoning.effort 对象 / standard: reasoning_effort 字符串）
- `outputFormat` — 推理输出格式（reasoning_content / reasoning_details / think_tags）

这些配置存储在 `[model_providers.custom]` 节中，代理服务器在转发时读取并应用。参照 cc-switch 的 `CodexChatReasoningConfig` 结构。

### 4. 供应商管理界面

增强 `ProviderFormView`：
- 基本信息：ID、名称、BaseURL、Wire API (responses/chat)
- API Key 字段（保存到 macOS Keychain，TOML 中写入 experimental_bearer_token）
- 推理配置折叠区域
- 模型列表编辑器（可增删模型，每行：slug、显示名称、上下文窗口）

## 实现计划

### Phase 1: Codex 启动保障

修改文件：
- `CodexConfigService.swift` — 确保 `applyProvider` 写入规范的 config.toml，生成模型目录 JSON，注入 model_catalog_json 字段
- 验证点：执行 `codex` 命令不报配置错误

### Phase 2: 模型接入与显示

修改文件：
- 新增 `ModelCatalogService.swift` — 模型目录 JSON 生成和写入
- `CodexConfigService.swift` — 模型目录字段自动管理
- `ProvidersView.swift` / `ProviderFormView.swift` — 模型列表编辑器
- 验证点：`codex model` 列出自定义模型，显示名称正确

### Phase 3: 模型正确调用

修改文件：
- `ReasoningRectifier.swift` — per-provider 手动配置覆盖
- `CodexConfigService.swift` — 推理配置存入 TOML，RequestHandler 读取应用
- 验证点：Codex 使用第三方模型完成一次完整的代码生成对话

### Phase 4: UI 优化

修改文件：
- `ProvidersView.swift` / `ProviderFormView.swift` — 完善表单布局、错误提示
- 移除未使用的 `MenuBarView.swift` 和 `CodexRouterDB/` 模块

## 技术决策

| 决策 | 选择 | 理由 |
|------|------|------|
| 数据存储 | TOML 文件直读直写 | 现有实现已稳定，Codex 原生格式，无需 DB 同步 |
| DB 模块 | 移除 | 已写完但完全未接入，增加维护复杂度 |
| API Key 存储 | TOML experimental_bearer_token | 与 cc-switch 一致，Codex 原生支持 |
| 模型目录 | 静态 JSON 文件 | 与 cc-switch 一致，Codex 原生支持 |
| 代理端口 | 15721 | 现有默认值，与 EchoBird (53682) 和 cc-switch (5000+) 区分 |

## 参考实现对照

| 功能 | cc-switch 文件 | EchoBird 文件 | CodexAdaptor 文件 |
|------|---------------|---------------|-------------------|
| config.toml 写入 | `codex_config.rs:prepare_codex_provider_live_config()` | 私有 core 的 `config_manager.rs` | `CodexConfigService.swift` |
| 模型目录生成 | `codex_config.rs:codex_model_catalog_from_specs()` | N/A | 新增 `ModelCatalogService.swift` |
| 推理配置 | `provider.rs:CodexChatReasoningConfig` | N/A | `ReasoningConfig.swift` + `ReasoningRectifier.swift` |
| API 格式转换 | `transform_codex_chat.rs` | 私有 core 的 `protocol_converter.rs` | `ChatToResponsesTransformer.swift` + `SSEStreamTransformer.swift` |
| SSE 流式转换 | `streaming_codex_chat.rs` | 私有 core 的 `stream_handler.rs` | `SSEStreamTransformer.swift` |
