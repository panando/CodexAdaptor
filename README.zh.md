# CodexAdaptor

**一个轻量级的 macOS 菜单栏代理，将自定义模型供应商连接到 OpenAI Codex。**

拦截 Codex 的 Responses API 调用，将其翻译为任意上游供应商的 Chat Completions API —— 支持 DeepSeek、OpenRouter、本地模型等。

[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![Swift 5.9+](https://img.shields.io/badge/swift-5.9+-orange?logo=swift)](https://swift.org)
[![macOS 14+](https://img.shields.io/badge/platform-mOS%2014%2B-black?logo=apple)](https://developer.apple.com/macos/)
[![Version](https://img.shields.io/badge/version-0.1.0-green)](VERSION)

[安装](#安装) ·
[快速开始](#快速开始) ·
[功能特性](#功能特性) ·
[配置说明](#配置说明) ·
[从源码构建](#从源码构建) ·
[参与贡献](#参与贡献)

[English](README.md) ·
**中文**

---

## 为什么需要 CodexAdaptor？

OpenAI Codex CLI 默认只能连接固定的供应商。如果你想使用 DeepSeek、OpenRouter、本地模型或其他任何兼容 OpenAI 的 API，没有内置的方式可以做到。

CodexAdaptor 位于 Codex 和你选择的供应商之间，自动转换通信协议，让 Codex "以为"自己在和 OpenAI 对话 —— 而实际上请求发送到了你指定的任何地方。

## 安装

### macOS 应用（推荐）

从 [Releases](https://github.com/panando/CodexAdaptor/releases) 下载 `.dmg` 文件，将 **CodexAdaptor** 拖入"应用程序"文件夹，启动即可。应用以菜单栏图标形式运行，无需终端。

### 从源码构建

需要 macOS 14+ 和 Swift 5.9+。

```bash
git clone https://github.com/panando/CodexAdaptor.git
cd codex-adapter
./build.sh
```

该脚本一键完成：编译 Release 二进制文件、创建 `.app` 应用包、打包 `.dmg` 安装镜像。输出文件位于项目根目录。

## 快速开始

1. **启动 CodexAdaptor** —— 菜单栏出现图标
2. **点击图标 → 配置** 打开设置窗口
3. **进入供应商标签页 → 点击 +** 添加供应商（名称、上游地址、API 密钥）
4. **为供应商添加模型** —— 模型标识必须与上游 API 完全一致
5. **进入服务器标签页 → 选择供应商** —— 自动写入 `~/.codex/config.toml`
6. **点击"启动服务"** —— 代理开始在 `127.0.0.1:15721` 监听
7. **启动 Codex** —— 自动通过代理连接

## 功能特性

### 多供应商支持

按需添加任意数量的供应商 —— DeepSeek、OpenRouter、SiliconFlow、本地模型或任何兼容 OpenAI 的 API。在服务器标签页一键切换，无需手动编辑配置文件。

### 通信协议转换

在 Codex 的 Responses API 和上游供应商的 Chat Completions API 之间透明转换。支持流式和非流式响应。

### 推理模型支持

针对不同供应商处理 `thinking`/`reasoning` 参数，支持按供应商配置：
- **思考参数**：`thinking`（DeepSeek/Kimi/GLM）、`enable_thinking`（SiliconFlow/Qwen）、`reasoning_split`（MiniMax），或自动检测
- **强度映射**：将 Codex 的推理强度级别映射到供应商特定值（如 DeepSeek 的 `max` ↔ OpenRouter 的 `xhigh`）
- **输出标准化**：将 `reasoning_content`、`reasoning_details` 或 `reasoning` 字段统一转换为 Codex 所需格式

### 插件增强（Codex 应用）

通过 CDP（Chrome DevTools Protocol）注入 Codex Electron 应用：
- **插件入口解锁**：强制显示插件导航按钮，不受认证模式限制
- **插件市场解锁**：API Key 模式下扩展插件市场列表
- **特殊插件强制安装**：解除因应用限制而被禁用的安装按钮

### 原生 macOS 菜单栏应用

基于 SwiftUI 构建 —— 非 Electron。以轻量级菜单栏应用形式运行：
- 一键启动/停止服务
- 侧边栏导航配置窗口
- 实时日志查看器，支持筛选和导出
- 双语界面（英文 / 中文）

### 自动配置管理

- 自动写入 `~/.codex/config.toml`，包含正确的 `base_url`、`model_provider`、`wire_api` 和 bearer token
- 每次写入前自动创建备份（`config.toml.bak.codexadaptor`）
- 生成每个供应商的模型目录文件，Codex 读取这些文件填充模型选择器

## 配置说明

所有配置通过应用 GUI 管理。文件存储在 `~/.codex/` 目录下：

| 文件 | 用途 |
|------|------|
| `~/.codex/config.toml` | Codex 主配置 —— 切换供应商时自动重写 |
| `~/.codex/providers.json` | CodexAdaptor 元数据 —— 上游地址、推理配置、模型目录 |
| `~/.codex/<provider-id>-model-catalog.json` | 每个供应商的模型列表，供 Codex 模型选择器使用 |
| `~/.codex/config.toml.bak.codexadaptor` | 每次更改前的自动备份 |
| `~/.codex/logs/proxy.log` | 应用日志 |

## 架构

```
Codex CLI
    │
    ▼ (Responses API)
┌─────────────────────┐
│   CodexAdaptor      │
│   127.0.0.1:15721   │
│                     │
│  ┌───────────────┐  │
│  │ Hummingbird   │  │  ← HTTP 代理服务器
│  │ Server        │  │
│  └───────┬───────┘  │
│          │          │
│  ┌───────▼───────┐  │
│  │ SSE           │  │  ← 协议转换
│  │ Transformer   │  │    (Responses ↔ Chat Completions)
│  └───────┬───────┘  │
│          │          │
│  ┌───────▼───────┐  │
│  │ CDP           │  │  ← 插件注入 Codex
│  │ Injector      │  │    Electron 应用
│  └───────────────┘  │
└─────────┬───────────┘
          │
          ▼ (Chat Completions API)
   上游供应商
  (DeepSeek / OpenRouter / ...)
```

## 从源码构建

### 环境要求

- macOS 14.0+（Sonoma）
- Swift 5.9+
- Xcode 命令行工具

### 一键构建

```bash
./build.sh
```

输出：
- `CodexAdaptor.app` —— macOS 应用包
- `CodexAdaptor-<version>.dmg` —— 分发用磁盘镜像

### 开发构建

```bash
swift build                    # Debug 构建
swift build -c release         # Release 构建
swift test                     # 运行测试
```

## 参与贡献

欢迎贡献！开始步骤：

1. Fork 本仓库
2. 创建功能分支（`git checkout -b feature/my-feature`）
3. 进行修改
4. 构建并测试（`swift build && swift test`）
5. 提交并推送
6. 发起 Pull Request

重大更改请先开 Issue 讨论方案。

## 致谢

本项目借鉴了以下项目的思路和代码：

- **[cc-switch](https://github.com/nicepkg/cc-switch)** —— 将 Codex 路由到自定义供应商的本地代理方案。CodexAdaptor 的代理架构和配置管理深受 cc-switch 启发。
- **[EchoBird](https://github.com/nicepkg/EchoBird)** —— 额外的代理模式和供应商抽象技术，为 CodexAdaptor 的设计提供了参考。
- **[CodexPlusPlus](https://github.com/nicepkg/CodexPlusPlus)** —— Codex Electron 应用的 CDP 插件注入实现。CodexAdaptor 的插件入口解锁和强制安装功能移植自 CodexPlusPlus 的 Rust/Tauri 代码。

## 相关项目

**[APIBypass](https://github.com/panando/APIBypass)** —— 通用 API 代理工具包，用于绕过供应商限制。CodexAdaptor 计划未来集成到 APIBypass 中，作为其专用模块。欢迎关注 APIBypass 项目获取更新。

## 许可证

[MIT](LICENSE)
