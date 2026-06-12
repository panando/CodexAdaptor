import Foundation
import SwiftUI

public extension Notification.Name {
    static let LocalizationServiceDidChange = Notification.Name("LocalizationServiceDidChange")
}

/// Runtime language-switching localization service.
/// Views that observe this service will re-render when the language changes.
/// Non-SwiftUI code can observe `Notification.Name.LocalizationServiceDidChange`.
public final class LocalizationService: ObservableObject {
    public static let shared = LocalizationService()

    @Published public var language: String {
        didSet {
            UserDefaults.standard.set(language, forKey: "codexadaptor.language")
            NotificationCenter.default.post(name: .LocalizationServiceDidChange, object: nil)
        }
    }

    private init() {
        self.language = UserDefaults.standard.string(forKey: "codexadaptor.language") ?? "en"
    }

    public var isChinese: Bool { language == "zh" }
}

// MARK: - Localized strings

/// All user-facing strings in English and Chinese.
public enum L10n {
    // Sidebar
    static var server: String { lang("Server", "服务器") }
    static var providers: String { lang("Providers", "模型供应商") }
    static var logs: String { lang("Logs", "日志") }
    static var help: String { lang("Help", "帮助") }
    static var about: String { lang("About", "关于") }
    static var selectSection: String { lang("Select a section", "请选择左侧导航") }

    // Providers
    static var noProviders: String { lang("No Providers", "暂无供应商") }
    static var addProviderHint: String { lang("Click + to add a provider.", "点击 + 添加模型供应商") }
    static var active: String { lang("Active", "当前") }
    static var addProvider: String { lang("Add Provider", "添加供应商") }
    static var editProvider: String { lang("Edit Provider", "编辑供应商") }
    static var edit: String { lang("Edit", "编辑") }
    static var deleteProvider: String { lang("Delete Provider", "删除供应商") }
    static var switchSuccess: String { lang("Switched to", "已切换到") }
    static var saved: String { lang("Provider saved", "供应商已保存") }
    static var deleted: String { lang("Provider deleted", "供应商已删除") }
    static var deleteConfirmTitle: String { lang("Delete Provider", "删除供应商") }
    static func deleteConfirmMsg(_ name: String) -> String { lang("Delete provider \"\(name)\"?", "确定删除供应商「\(name)」？") }
    static var deleteCannotUndo: String { lang("This cannot be undone.", "此操作不可撤销。") }
    static var deleteBtn: String { lang("Delete", "删除") }
    static var cannotDeleteActive: String { lang("Cannot delete active provider", "不可删除当前使用的供应商") }
    static var editProviderTooltip: String { lang("Edit provider", "编辑供应商") }
    static var deleteProviderTooltip: String { lang("Delete provider", "删除供应商") }

    // Provider form
    static var basicInfo: String { lang("Basic Information", "基本信息") }
    static var providerName: String { lang("Provider Name", "供应商名称") }
    static var providerNamePrompt: String { lang("e.g. DeepSeek, OpenRouter", "例如：DeepSeek、OpenRouter") }
    static var baseURL: String { lang("Base URL", "接口地址") }
    static var apiConfig: String { lang("API Configuration", "API 配置") }
    static var wireProtocol: String { lang("Wire Protocol", "通信协议") }
    static var chatCompletions: String { lang("Chat Completions", "Chat Completions") }
    static var responsesAPI: String { lang("Responses API", "Responses API") }
    static var apiKey: String { lang("API Key (Bearer Token)", "API 密钥") }
    static var apiKeyPrompt: String { lang("sk-... or leave empty", "sk-... 或留空") }
    static var reasoningConfig: String { lang("Reasoning Configuration", "推理配置") }
    static var overrideReasoning: String { lang("Override Reasoning Defaults", "覆盖默认推理设置") }
    static var autoDetect: String { lang("Auto-Detect from URL", "从 URL 自动检测") }
    static var enableThinking: String { lang("Enable Thinking (Reasoning)", "启用思考模式") }
    static var thinkingDesc: String { lang("Inject a thinking parameter so Codex can request deep reasoning from the model.", "注入思考参数，使 Codex 可向模型请求深度推理。") }
    static var parameterName: String { lang("Parameter Name", "参数名") }
    static var enableEffort: String { lang("Enable Reasoning Effort", "启用推理强度") }
    static var effortDesc: String { lang("Forward Codex's effort level (low/medium/high/xhigh/max) to the upstream.", "将 Codex 的努力程度（低/中/高/极高/最大）转发至上游。") }
    static var effortParam: String { lang("Effort Parameter", "强度参数") }
    static var valueMapping: String { lang("Value Mapping", "值映射") }
    static var outputFormat: String { lang("Output Format", "输出格式") }
    static var outputFormatDesc: String { lang("How the upstream returns reasoning text. The proxy normalizes it for Codex.", "上游返回推理文本的方式，代理会标准化为 Codex 所需格式。") }
    static var reasoningAutoDetectFooter: String { lang("Auto-detection is used when no override is set. The proxy infers parameters from the provider name and base URL.", "不覆盖时使用自动检测。代理会根据供应商名称和接口地址推断参数。") }
    static var customModels: String { lang("Custom Models", "自定义模型") }
    static var addModel: String { lang("Add Model", "添加模型") }
    static var editModel: String { lang("Edit Model", "编辑模型") }
    static var removeModel: String { lang("Remove Model", "移除模型") }
    static var modelFooter: String { lang("These models appear in Codex's model selector under this provider.", "这些模型会出现在 Codex 的模型选择器中。") }
    static var cancel: String { lang("Cancel", "取消") }
    static var save: String { lang("Save", "保存") }
    static var reasoningEffort: String { lang("reasoning_effort — top-level (DeepSeek, OpenAI)", "reasoning_effort — 顶层字段（DeepSeek、OpenAI）") }
    static var reasoningEffortNested: String { lang("reasoning.effort — nested (OpenRouter)", "reasoning.effort — 嵌套对象（OpenRouter）") }
    static var standardPassthrough: String { lang("Standard — passthrough", "标准 — 直接传递") }
    static var deepseekClamp: String { lang("DeepSeek — max/xhigh → max", "DeepSeek — max/xhigh → max") }
    static var openrouterMap: String { lang("OpenRouter — max → xhigh", "OpenRouter — max → xhigh") }
    static var lowHighBinary: String { lang("Low/High — binary", "低/高 — 二值化") }
    static var reasoningContent: String { lang("reasoning_content — single string", "reasoning_content — 单字符串") }
    static var reasoningDetails: String { lang("reasoning_details — array of parts", "reasoning_details — 部件数组") }
    static var reasoningGeneric: String { lang("reasoning — generic field", "reasoning — 通用字段") }
    static var auto: String { lang("auto — no transformation", "auto — 不做转换") }
    static var thinkingNone: String { lang("none — skip", "none — 跳过") }
    static var thinkingDeepSeek: String { lang("thinking — DeepSeek / Kimi / GLM", "thinking — DeepSeek / Kimi / GLM") }
    static var thinkingSiliconFlow: String { lang("enable_thinking — SiliconFlow / Qwen", "enable_thinking — SiliconFlow / Qwen") }
    static var thinkingMiniMax: String { lang("reasoning_split — MiniMax", "reasoning_split — MiniMax") }

    // Model editor
    static var modelSlug: String { lang("Model Slug", "模型标识") }
    static var modelSlugPrompt: String { lang("deepseek-chat", "deepseek-chat") }
    static var modelSlugDesc: String { lang("API model identifier. Must match the upstream provider's model name exactly.", "API 模型标识符，必须与上游供应商的模型名完全一致。") }
    static var displayName: String { lang("Display Name", "显示名称") }
    static var displayNamePrompt: String { lang("DeepSeek Chat", "DeepSeek Chat") }
    static var displayNameDesc: String { lang("Name shown in Codex's model picker. Optional — uses the slug if empty.", "Codex 模型选择器中显示的名称。可选 — 留空则使用模型标识。") }
    static var contextWindow: String { lang("Context Window", "上下文窗口") }
    static var contextWindowPrompt: String { lang("128000", "128000") }
    static var contextWindowDesc: String { lang("Max context tokens. Common values: 4K, 8K, 32K, 128K, 1M.", "最大上下文 token 数。常见值：4K、8K、32K、128K、1M。") }
    static var add: String { lang("Add", "添加") }
    static func removeModelConfirm(_ name: String) -> String { lang("Remove model \"\(name)\"?", "确定移除模型「\(name)」？") }
    static var removeModelDesc: String { lang("The model will no longer appear in Codex's model selector.", "该模型将不再出现在 Codex 的模型选择器中。") }
    static var remove: String { lang("Remove", "移除") }

    // Server
    static var proxyServer: String { lang("Proxy Server", "代理服务器") }
    static var proxyPort: String { lang("Proxy Port", "代理端口") }
    static var proxyURL: String { lang("Proxy URL", "代理地址") }
    static var restartToApply: String { lang("Requires restart to apply", "重启后生效") }
    static var autoConfigured: String { lang("Auto-configured", "自动配置") }
    static var runtimeStatus: String { lang("Runtime Status", "运行状态") }
    static var running: String { lang("Running", "运行中") }
    static var stopped: String { lang("Stopped", "已停止") }
    static var portLabel: String { lang("Port:", "端口：") }
    static var status: String { lang("Status", "状态") }
    static var activeProvider: String { lang("Active Provider", "当前供应商") }
    static var configFiles: String { lang("Configuration Files", "配置文件") }
    static var configDesc: String { lang("Codex reads provider/model from this file at startup. The proxy rewrites base_url to localhost automatically.", "Codex 启动时从此文件读取供应商/模型信息。代理自动将 base_url 重写为 localhost。") }
    static var proxyMetadata: String { lang("Proxy Metadata", "代理元数据") }
    static var metadataDesc: String { lang("Stores upstream URLs, reasoning configs, and model catalogs. Managed by this app; do not edit manually.", "存储上游地址、推理配置和模型目录。由此应用管理，请勿手动编辑。") }

    // Logs
    static var filter: String { lang("Filter...", "筛选...") }
    static var autoScroll: String { lang("Auto-scroll", "自动滚动") }
    static var copyAll: String { lang("Copy All", "复制全部") }
    static var copied: String { lang("Copied!", "已复制！") }
    static var exportBtn: String { lang("Export...", "导出...") }
    static var clearBtn: String { lang("Clear", "清空") }
    static var entries: String { lang("entries", "条") }
    static var exportLogs: String { lang("Export Logs", "导出日志") }

    // Menu bar
    static var configure: String { lang("Configure", "配置") }
    static var startServer: String { lang("Start Service", "启动服务") }
    static var stopServer: String { lang("Stop Service", "停止服务") }
    static var quit: String { lang("Quit", "退出") }
    static var quitShort: String { lang("Quit", "退出") }
    static var serverRunning: String { lang("Running (", "运行中（") }
    static var serverStopped: String { lang("Stopped", "已停止") }
    static var serverStarting: String { lang("Starting...", "启动中...") }
    static var runningWithPort: String { lang("Running", "运行中") }

    // Help
    static var helpTitle: String { lang("CodexAdaptor Help", "CodexAdaptor 帮助") }
    static var helpSubtitle: String { lang("A local proxy that enables custom model providers to work with OpenAI Codex CLI.", "一个本地代理，让自定义模型供应商能够与 OpenAI Codex CLI 配合使用。") }
    static var howItWorks: String { lang("How It Works", "工作原理") }
    static var howItWorksDesc: String { lang("CodexAdaptor intercepts Codex's Responses API calls and translates them to the upstream provider's Chat Completions API. The proxy runs locally on 127.0.0.1, forwarding requests and translating responses in real time.", "CodexAdaptor 拦截 Codex 的 Responses API 调用，并将其翻译为上游供应商的 Chat Completions API。代理在本地 127.0.0.1 上运行，实时转发请求并转换响应。") }
    static var setupGuide: String { lang("Setup Guide", "设置指南") }
    static var setup1: String { lang("Start the proxy server from the menu bar or the Server tab", "从菜单栏或服务器标签页启动代理服务器") }
    static var setup2: String { lang("Add a provider in the Providers tab — enter the name, upstream base URL, and API key", "在供应商标签页添加供应商 — 输入名称、上游接口地址和 API 密钥") }
    static var setup3: String { lang("Add models to the provider — specify the model slug as expected by the upstream API", "为供应商添加模型 — 指定与上游 API 匹配的模型标识") }
    static var setup4: String { lang("Select the provider in the Server tab — this updates ~/.codex/config.toml", "在服务器标签页中选择供应商 — 这将更新 ~/.codex/config.toml") }
    static var setup5: String { lang("Launch Codex — it will connect through the proxy automatically", "启动 Codex — 它会自动通过代理连接") }
    static var fileConfigDesc: String { lang("Codex's main configuration. CodexAdaptor sets model_provider, model, base_url (to localhost proxy), wire_api, model_catalog_json, and experimental_bearer_token here.", "Codex 的主配置文件。CodexAdaptor 在此设置 model_provider、model、base_url（指向本地代理）、wire_api、model_catalog_json 和 experimental_bearer_token。") }
    static var fileProvidersDesc: String { lang("CodexAdaptor's internal metadata. Stores upstream base URLs, reasoning config overrides, and model catalogs — separate from config.toml so Codex plugins are never affected.", "CodexAdaptor 的内部元数据。存储上游地址、推理配置覆盖和模型目录 — 与 config.toml 同目录，确保 Codex 插件不受影响。") }
    static var fileCatalogDesc: String { lang("Per-provider model catalog files. Generated from the Custom Models section in the provider editor. Codex reads these to populate its model selector.", "每个供应商的模型目录文件。由供应商编辑器中的自定义模型部分生成。Codex 读取这些文件以填充模型选择器。") }
    static var fileBackupDesc: String { lang("Automatic backup created before every config.toml write. Restore this file to undo CodexAdaptor's last config change.", "每次写入 config.toml 前自动创建的备份。恢复此文件可撤销 CodexAdaptor 的最后一次配置更改。") }

    // About
    static var aboutSubtitle: String { lang("A lightweight proxy for connecting custom model providers to OpenAI Codex.", "一个轻量级代理，用于将自定义模型供应商连接到 OpenAI Codex。") }
    static func version(_ ver: String) -> String { lang("Version \(ver)", "版本 \(ver)") }
    static var language: String { lang("Language", "语言") }
    static var english: String { lang("English", "英文") }
    static var chinese: String { lang("中文", "中文") }
    static var preferences: String { lang("Preferences", "偏好设置") }

    // Plugin unlock
    static var codexEnhancements: String { lang("Codex Enhancements", "Codex 增强") }
    static var pluginEntryUnlock: String { lang("Force Entry Unlock", "强制解锁入口") }
    static var pluginEntryUnlockDesc: String { lang("Force the Plugins button visible via auth spoofing.", "通过身份伪装强制显示插件入口按钮。") }
    static var pluginMarketplaceUnlock: String { lang("Plugin Marketplace Unlock", "插件市场解锁") }
    static var pluginMarketplaceUnlockDesc: String { lang("Expand marketplace requests under API Key mode to show full plugin list.", "API Key 模式下扩展插件市场请求，尽量显示完整插件列表。") }
    static var forcePluginInstall: String { lang("Force Plugin Install", "特殊插件强制安装") }
    static var forcePluginInstallDesc: String { lang("Unblock install buttons disabled due to app unavailability restrictions.", "解除应用不可用导致的前端安装禁用。") }
    static var codexDebugPort: String { lang("Codex Debug Port", "Codex 调试端口") }
    static var codexDebugPortDesc: String { lang("CDP remote debugging port for JS injection (requires Codex started with --remote-debugging-port).", "用于 JS 注入的 CDP 远程调试端口（Codex 需以 --remote-debugging-port 参数启动）。") }

    // General
    static var error: String { lang("Error", "错误") }
    static var success: String { lang("Success", "成功") }
    static var ok: String { lang("OK", "确定") }
    static var loading: String { lang("Loading...", "加载中...") }
    static var refresh: String { lang("Refresh", "刷新") }

    // MARK: - Implementation

    private static func lang(_ en: String, _ zh: String) -> String {
        LocalizationService.shared.isChinese ? zh : en
    }
}
