# v0.1.1

UI overhaul for the provider editor and configuration window, plus a critical provider deletion fix.

## Highlights

### Provider Editor Redesign

- Standalone resizable window (780x820) instead of a fixed-size sheet
- Model editor with columnar layout — model alias, model name, and context window fields are directly editable inline
- Model field descriptions shown once in the column header, not repeated per row
- Placeholder hints (e.g., "DeepSeek Chat", "deepseek-chat") instead of pre-filled editable values
- Equal-width fields so context window is no longer cramped
- Larger bordered buttons for add/confirm/cancel/delete actions

### Form Layout Fixes

- Replaced `.formStyle(.grouped)` with custom section layout for proper field alignment
- Added labels above all input fields (provider name, base URL, API key)
- Wire protocol picker changed to horizontal segmented control
- Reasoning config toggles: smaller switch style, placed before label text
- Reasoning sub-modules cleaned up — removed box backgrounds, using Dividers instead

### Configuration Window

- Sidebar reordered: Providers above Server
- Default tab changed to Providers on window open
- Menu bar reordered: Configure → Start/Stop → Quit
- Debug port description moved to its own line below the input

### Bug Fixes

- Fixed provider deletion — TOMLKit `nil` assignment was a no-op; now uses `remove(at:)` correctly

## Requirements

- macOS 14.0+ (Sonoma)
- Swift 5.9+ (for building from source)

---

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
