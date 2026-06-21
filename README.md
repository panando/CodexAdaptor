# CodexAdaptor

**A lightweight macOS menu bar proxy for connecting custom model providers to OpenAI Codex.**

Intercepts Codex's Responses API calls and translates them to any upstream provider's Chat Completions API — works with DeepSeek, OpenRouter, local models, and more.

[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![Swift 5.9+](https://img.shields.io/badge/swift-5.9+-orange?logo=swift)](https://swift.org)
[![macOS 14+](https://img.shields.io/badge/platform-mOS%2014%2B-black?logo=apple)](https://developer.apple.com/macos/)
[![Version](https://img.shields.io/badge/version-0.1.3-green)](VERSION)

[Install](#install) ·
[Quickstart](#quickstart) ·
[Features](#features) ·
[Configuration](#configuration) ·
[Build from Source](#build-from-source) ·
[Contributing](#contributing)

**English** ·
[中文](README.zh.md)

---

## Why CodexAdaptor?

OpenAI Codex CLI connects to a fixed set of providers by default. If you want to use DeepSeek, OpenRouter, a local model, or any other OpenAI-compatible API, there's no built-in way to do it.

CodexAdaptor sits between Codex and your chosen provider, automatically translating the wire protocol so Codex "thinks" it's talking to OpenAI — while your requests actually go wherever you want.

## Install

### macOS App (Recommended)

Download the `.dmg` from [Releases](https://github.com/panando/CodexAdaptor/releases), drag **CodexAdaptor** to Applications, and launch it. The app lives in your menu bar — no terminal required.

### Fixing the "damaged app" Message

Current releases are ad-hoc signed because CodexAdaptor does not have an Apple Developer ID certificate yet. The app is not notarized, so macOS Gatekeeper may show:

> "CodexAdaptor" is damaged and can't be opened. You should move it to the Trash.

This does not mean the app bundle is actually damaged. It usually means macOS attached a quarantine flag to the downloaded app.

**Option 1: Open from System Settings**

1. Try launching **CodexAdaptor** from Applications.
2. Open **System Settings → Privacy & Security**.
3. Scroll to the Security section.
4. If macOS shows a blocked **CodexAdaptor** message, click **Open Anyway**.
5. Confirm the prompt and launch the app again.

**Option 2: Remove the quarantine flag in Terminal**

If Option 1 does not appear or does not work, run:

```bash
sudo xattr -dr com.apple.quarantine /Applications/CodexAdaptor.app
```

Terminal will ask for your macOS password. Password characters are not displayed while you type; this is normal.

If your app is not in `/Applications`, type `sudo xattr -dr com.apple.quarantine ` with a trailing space, then drag `CodexAdaptor.app` from Finder into Terminal and press Enter.

Only run this command for apps downloaded from a source you trust. If CodexAdaptor gets a Developer ID certificate in the future, releases will be signed and notarized.

### Build from Source

Requires macOS 14+ and Swift 5.9+.

```bash
git clone https://github.com/panando/CodexAdaptor.git
cd codex-adapter
./build.sh
```

The script builds the release binary, creates a `.app` bundle, and packages a `.dmg` in one step. Output appears in the project root.

## Quickstart

1. **Launch CodexAdaptor** — it appears as an icon in your menu bar
2. **Click the icon → Configure** to open the settings window
3. **Go to Providers tab → click +** to add a provider (name, base URL, API key)
4. **Add models** to the provider (model slug must match the upstream API exactly)
5. **Go to Server tab → select your provider** — this writes the config to `~/.codex/config.toml`
6. **Click "Start Service"** — the proxy begins listening on `127.0.0.1:15721`
7. **Launch Codex** — it connects through the proxy automatically

## Features

### Multi-Provider Support

Add as many providers as you need — DeepSeek, OpenRouter, SiliconFlow, local models, or any OpenAI-compatible API. Switch between them from the Server tab without editing config files manually.

### Wire Protocol Translation

Transparently converts between Codex's Responses API and the upstream provider's Chat Completions API. Supports both streaming and non-streaming responses.

### Reasoning Model Support

Handles `thinking`/`reasoning` parameters across different providers with per-provider configuration:
- **Thinking parameter**: `thinking` (DeepSeek/Kimi/GLM), `enable_thinking` (SiliconFlow/Qwen), `reasoning_split` (MiniMax), or auto-detect
- **Effort mapping**: Maps Codex's effort levels to provider-specific values (e.g., DeepSeek's `max` ↔ OpenRouter's `xhigh`)
- **Output normalization**: Converts `reasoning_content`, `reasoning_details`, or `reasoning` fields into a unified format for Codex

### Plugin Enhancements (Codex App)

Via CDP (Chrome DevTools Protocol) injection into the Codex Electron app:
- **Plugin Entry Unlock**: Force the Plugins navigation button visible for all auth modes
- **Plugin Marketplace Unlock**: Expand marketplace plugin listings under API Key mode
- **Force Plugin Install**: Unblock disabled install buttons for restricted plugins

### Native macOS Menu Bar App

Built with SwiftUI — not Electron. Runs as a lightweight menu bar app with:
- Start/stop service with one click
- Configuration window with sidebar navigation
- Real-time log viewer with filtering and export
- Bilingual UI (English / Chinese)

### Automatic Config Management

- Writes `~/.codex/config.toml` with the correct `base_url`, `model_provider`, `wire_api`, and bearer token
- Creates automatic backups before every config change (`config.toml.bak.codexadaptor`)
- Generates per-provider model catalog files that Codex reads to populate its model selector

## Configuration

All configuration is managed through the app's GUI. Files are stored under `~/.codex/`:

| File | Purpose |
|------|---------|
| `~/.codex/config.toml` | Codex main config — rewritten automatically when you switch providers |
| `~/.codex/providers.json` | CodexAdaptor metadata — upstream URLs, reasoning configs, model catalogs |
| `~/.codex/<provider-id>-model-catalog.json` | Per-provider model list for Codex's model selector |
| `~/.codex/config.toml.bak.codexadaptor` | Automatic backup before each config change |
| `~/.codex/logs/proxy.log` | Application logs |

## Architecture

```
Codex CLI
    │
    ▼ (Responses API)
┌─────────────────────┐
│   CodexAdaptor      │
│   127.0.0.1:15721   │
│                     │
│  ┌───────────────┐  │
│  │ Hummingbird   │  │  ← HTTP proxy server
│  │ Server        │  │
│  └───────┬───────┘  │
│          │          │
│  ┌───────▼───────┐  │
│  │ SSE           │  │  ← Protocol translation
│  │ Transformer   │  │     (Responses ↔ Chat Completions)
│  └───────┬───────┘  │
│          │          │
│  ┌───────▼───────┐  │
│  │ CDP           │  │  ← Plugin injection into
│  │ Injector      │  │     Codex Electron app
│  └───────────────┘  │
└─────────┬───────────┘
          │
          ▼ (Chat Completions API)
   Upstream Provider
  (DeepSeek / OpenRouter / ...)
```

## Build from Source

### Prerequisites

- macOS 14.0+ (Sonoma)
- Swift 5.9+
- Xcode Command Line Tools

### One-Click Build

```bash
./build.sh
```

Produces:
- `CodexAdaptor.app` — macOS application bundle
- `CodexAdaptor-<version>.dmg` — disk image for distribution

### Development Build

```bash
swift build                    # Debug build
swift build -c release         # Release build
swift test                     # Run tests
```

## Contributing

Contributions are welcome! Here's how to get started:

1. Fork this repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Make your changes
4. Build and test (`swift build && swift test`)
5. Commit and push
6. Open a Pull Request

Please open an issue first for large changes to discuss the approach.

## Acknowledgments

This project builds on ideas and code from the following projects:

- **[cc-switch](https://github.com/nicepkg/cc-switch)** — The original local proxy approach for routing Codex to custom providers. CodexAdaptor's proxy architecture and config management are heavily inspired by cc-switch.
- **[EchoBird](https://github.com/nicepkg/EchoBird)** — Additional proxy patterns and provider abstraction techniques that informed CodexAdaptor's design.
- **[CodexPlusPlus](https://github.com/nicepkg/CodexPlusPlus)** — CDP-based plugin injection implementation for the Codex Electron app. CodexAdaptor's plugin entry unlock and force install features are ported from CodexPlusPlus's Rust/Tauri codebase.

## Related Projects

**[APIBypass](https://github.com/panando/APIBypass)** — A universal API proxy toolkit for bypassing provider restrictions. CodexAdaptor is planned to be integrated into APIBypass as a specialized module in the future. Follow the APIBypass project for updates.

## License

[MIT](LICENSE)
