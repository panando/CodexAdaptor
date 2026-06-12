# v0.1.0

Initial release of CodexAdaptor — a lightweight macOS menu bar proxy for connecting custom model providers to OpenAI Codex.

## Highlights

### Multi-Provider Proxy

- Routes Codex requests to any OpenAI-compatible API (DeepSeek, OpenRouter, SiliconFlow, local models, etc.)
- Transparent Responses API ↔ Chat Completions protocol translation
- Streaming and non-streaming response support

### Reasoning Model Support

- Per-provider `thinking` parameter configuration (DeepSeek, Kimi, GLM, SiliconFlow, Qwen, MiniMax)
- Effort level mapping across providers (e.g., DeepSeek `max` ↔ OpenRouter `xhigh`)
- Output field normalization (`reasoning_content`, `reasoning_details`, `reasoning`)

### Codex Plugin Enhancements (via CDP)

- **Plugin Entry Unlock** — force the Plugins button visible for all auth modes
- **Plugin Marketplace Unlock** — expand marketplace listings under API Key mode
- **Force Plugin Install** — unblock disabled install buttons for restricted plugins

### Native macOS App

- SwiftUI menu bar app (not Electron)
- Sidebar-based configuration window
- Real-time log viewer with filtering and export
- Bilingual UI (English / Chinese)
- One-click build script for `.app` and `.dmg` packaging

### Automatic Config Management

- Writes `~/.codex/config.toml` with correct provider settings
- Auto-backup before every config change
- Per-provider model catalog generation for Codex's model selector

## Requirements

- macOS 14.0+ (Sonoma)
- Swift 5.9+ (for building from source)
