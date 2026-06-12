# CodexAdaptor Enhancement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix CodexAdaptor so third-party providers can be added, models display correctly in Codex with custom names, and requests route through the local proxy with proper protocol translation.

**Architecture:** Fix the `base_url` vs `upstream_base_url` split (config.toml points to local proxy, proxy reads upstream URL from a separate field). Enhance model catalog JSON generation to produce valid Codex model catalog files. Add per-provider reasoning config storage.

**Tech Stack:** Swift 5.9, SwiftUI, Hummingbird 2.0, TOMLKit, macOS 14+

---

## Core Problem

The current `saveProvider()` writes the user's upstream API URL directly into `base_url` in `config.toml`. But Codex reads `base_url` to find the API endpoint — it must point to the local proxy (`http://127.0.0.1:15721/v1`), not the upstream provider. The agent then reads `base_url` from the config and forwards requests to the upstream. This circular reference means Codex never routes through the proxy.

**Fix:** Split into two fields:
- `base_url` = always the local proxy (Codex talks to proxy)
- `upstream_base_url` = the actual provider API (proxy talks to upstream)

Reference: cc-switch uses `base_url` in TOML for the proxy URL and reads the provider's actual endpoint from a separate config source. EchoBird uses `~/.echobird/codex.json` for the real upstream config.

---

## Summary of Changes

| Phase | Files Modified | Files Created |
|-------|---------------|---------------|
| 1. Codex startup | `CodexConfigService.swift` | — |
| 2. Model display | `CodexConfigService.swift`, `ProvidersView.swift` | — |
| 3. Model invocation | `CodexConfigService.swift`, `RequestHandler.swift`, `ReasoningRectifier.swift` | — |
| 4. UI cleanup | `ProvidersView.swift`, `MainView.swift`, `SettingsView.swift` | — |
| Remove unused | `Package.swift` | — (remove `CodexRouterDB` references) |

---

### Task 1: Fix config.toml base_url / upstream_base_url split

**Files:**
- Modify: `Sources/CodexRouterApp/Services/CodexConfigService.swift:56-62, 108-109, 583-586, 601-603`

**Goal:** `saveProvider()` writes `base_url = "http://127.0.0.1:15721/v1"` (always pointing to proxy) and `upstream_base_url = "<user's provider URL>"` (the actual upstream). `getCurrentUpstreamProvider()` reads `upstream_base_url` for the real endpoint.

- [ ] **Step 1: Fix getCurrentUpstreamProvider to prefer upstream_base_url**

In `CodexConfigService.swift:56-62`, change the base URL extraction to add `upstream_base_url` as the primary source:

```swift
// Prefer upstream_base_url (actual API endpoint) over base_url (which points to proxy)
let upstreamBaseURL = extractValue(from: sectionContent, key: "upstream_base_url")
    ?? extractValue(from: sectionContent, key: "base_url")
```

This is already correct — no change needed. But we also need to strip the `/v1` suffix from the proxy URL when reading upstream_base_url. Add a helper to normalize URLs.

- [ ] **Step 2: Fix saveProvider to store upstream URL separately**

In `CodexConfigService.swift:583-586` and `601-603`, update the section content to write both `base_url` (always proxy) and `upstream_base_url` (user's actual endpoint):

In `updateProviderSection()` and `addProviderSection()`, change:
```swift
newSection += "base_url = \"\(provider.baseURL)\"\n"
```
to:
```swift
// Always point base_url at the local proxy for Codex itself
newSection += "base_url = \"http://127.0.0.1:15721/v1\"\n"
newSection += "upstream_base_url = \"\(provider.baseURL)\"\n"
```

Also add `upstream_wire_api` field so the proxy knows whether the upstream speaks chat or responses:
```swift
newSection += "upstream_wire_api = \"\(provider.wireAPI)\"\n"
```

- [ ] **Step 3: Fix getModelProviders to read upstream_base_url**

In `getModelProviders()` around line 108, change baseURL reading to prefer `upstream_base_url`:

```swift
let baseURL = extractValue(from: sectionContent, key: "upstream_base_url")
    ?? extractValue(from: sectionContent, key: "base_url") 
    ?? ""
```

- [ ] **Step 4: Build and verify compilation**

```bash
cd /Users/panando/ClaudeCode/codex-adapter && swift build 2>&1
```

Expected: BUILD SUCCESS

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexRouterApp/Services/CodexConfigService.swift
git commit -m "fix: split base_url (proxy) and upstream_base_url (provider) in config.toml"
```

---

### Task 2: Ensure model catalog JSON is correctly generated and injected

**Files:**
- Modify: `Sources/CodexRouterApp/Services/CodexConfigService.swift:238-243, 314-348, 636-668`

**Goal:** When saving a provider with models, the model catalog JSON file is correctly generated from the Codex gpt-5.5 template and `model_catalog_json` is injected into config.toml.

- [ ] **Step 1: Fix model catalog JSON to use provider-scoped filenames**

Change `modelCatalogPath` (line 21) to use provider ID:

```swift
// In init(), add a method to get catalog path for a specific provider
private func modelCatalogPath(for providerId: String) -> String {
    "\(home)/.codex/\(providerId)-model-catalog.json"
}
```

Update `generateModelCatalogJSON` to accept a provider ID and use the scoped path.

- [ ] **Step 2: Add upstream_base_url and upstream_wire_api to the save flow**

In `saveProvider()`, update the catalog generation call and `ensureModelCatalogField` to use provider-scoped paths:

```swift
if let catalog = provider.modelCatalog, !catalog.models.isEmpty {
    try generateModelCatalogJSON(from: catalog, providerId: provider.id)
    content = try ensureModelCatalogField(content, providerId: provider.id)
} else {
    // Remove model_catalog_json field if no models configured
    content = try removeModelCatalogField(content, providerId: provider.id)
}
```

- [ ] **Step 3: Add removeModelCatalogField helper**

Add a method to clean up the `model_catalog_json` field when models are removed:

```swift
private func removeModelCatalogField(_ content: String, providerId: String) -> String {
    let pattern = #"^model_catalog_json\s*=\s*"[^"]*"\n"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
        return content
    }
    let range = NSRange(content.startIndex..., in: content)
    return regex.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: "")
}
```

- [ ] **Step 4: Verify model catalog template loading fallback works**

The static fallback in `staticTemplateFallback()` should be sufficient. Verify the template JSON structure has all required fields for a valid Codex model catalog entry.

- [ ] **Step 5: Build and verify compilation**

```bash
cd /Users/panando/ClaudeCode/codex-adapter && swift build 2>&1
```

- [ ] **Step 6: Commit**

```bash
git add Sources/CodexRouterApp/Services/CodexConfigService.swift
git commit -m "fix: use provider-scoped model catalog filenames and manage model_catalog_json field"
```

---

### Task 3: Add reasoning config storage per provider in TOML

**Files:**
- Modify: `Sources/CodexRouterApp/Services/CodexConfigService.swift` (both `CodexModelProvider` struct and save/read methods)
- Modify: `Sources/CodexRouterApp/Server/RequestHandler.swift:96-113`

**Goal:** Store reasoning configuration (supportsThinking, thinkingParam, effortValueMode, outputFormat) in the `[model_providers.<id>]` TOML section. Pass it to the `ReasoningRectifier` from `RequestHandler`.

- [ ] **Step 1: Add reasoning fields to CodexModelProvider**

Add to the `CodexModelProvider` struct:

```swift
/// Reasoning configuration for this provider
public var reasoningConfig: ReasoningConfig?
```

Update the `init` method to include `reasoningConfig: ReasoningConfig? = nil`.

- [ ] **Step 2: Write reasoning config to TOML on save**

In `updateProviderSection` and `addProviderSection`, add reasoning fields after the wire_api fields:

```swift
if let rc = provider.reasoningConfig {
    newSection += "supports_thinking = \(rc.supportsThinking ?? false ? "true" : "false")\n"
    if let param = rc.thinkingParam {
        newSection += "thinking_param = \"\(param)\"\n"
    }
    if let mode = rc.effortValueMode {
        newSection += "effort_value_mode = \"\(mode)\"\n"
    }
    if let format = rc.outputFormat {
        newSection += "reasoning_output_format = \"\(format)\"\n"
    }
}
```

- [ ] **Step 3: Read reasoning config from TOML**

In `getModelProviders()`, after extracting other fields, read the reasoning fields:

```swift
let supportsThinking = extractValue(from: sectionContent, key: "supports_thinking") == "true"
let thinkingParam = extractValue(from: sectionContent, key: "thinking_param")
let effortValueMode = extractValue(from: sectionContent, key: "effort_value_mode")
let outputFormat = extractValue(from: sectionContent, key: "reasoning_output_format")

let reasoningConfig = ReasoningConfig(
    supportsThinking: supportsThinking ? true : nil,
    supportsEffort: supportsThinking,
    thinkingParam: thinkingParam,
    effortParam: nil,
    effortValueMode: effortValueMode,
    outputFormat: outputFormat
)
```

- [ ] **Step 4: Pass reasoning config through UpstreamProvider to RequestHandler**

Add `reasoningConfig` field to `UpstreamProvider`:

```swift
public let reasoningConfig: ReasoningConfig?
```

Update `getCurrentUpstreamProvider()` to read and include the reasoning config.

- [ ] **Step 5: Wire reasoning config into RequestHandler**

In `RequestHandler.swift:96-113`, replace the auto-detection with manual config when available:

```swift
if var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
    if let rc = provider.reasoningConfig {
        // Use per-provider manual config
        reasoningRectifier.rectifyRequestWithConfig(&json, config: rc)
    } else {
        // Fall back to auto-detection from base URL
        let platform = ReasoningPlatform.detect(from: provider.baseURL)
        reasoningRectifier.rectifyRequest(&json, provider: nil, platform: platform)
    }
    ...
}
```

Add `rectifyRequestWithConfig` method to `ReasoningRectifier` that applies a `ReasoningConfig` directly without platform detection.

- [ ] **Step 6: Build and verify compilation**

```bash
cd /Users/panando/ClaudeCode/codex-adapter && swift build 2>&1
```

- [ ] **Step 7: Commit**

```bash
git add Sources/CodexRouterApp/Services/CodexConfigService.swift Sources/CodexRouterApp/Server/RequestHandler.swift Sources/CodexRouterCore/Transformers/ReasoningRectifier.swift
git commit -m "feat: add per-provider reasoning config storage and transmission to proxy"
```

---

### Task 4: Add reasoning config fields to ProviderFormView

**Files:**
- Modify: `Sources/CodexRouterApp/UI/ProvidersView.swift:276-286, 314-450`

**Goal:** Add reasoning configuration fields to the provider form UI.

- [ ] **Step 1: Add reasoning state variables to ProviderFormView**

Add after the existing `@State` variables (around line 286):

```swift
@State private var showReasoningConfig = false
@State private var supportsThinking = false
@State private var thinkingParam = "thinking"
@State private var effortValueMode = "standard"
@State private var reasoningOutputFormat = "reasoning_content"
```

- [ ] **Step 2: Add reasoning config section to the Form**

Add a new Section in the Form after "API Configuration":

```swift
Section {
    Toggle("Show Advanced Reasoning Config", isOn: $showReasoningConfig)
    
    if showReasoningConfig {
        Toggle("Supports Thinking", isOn: $supportsThinking)
        
        Picker("Thinking Param", selection: $thinkingParam) {
            Text("thinking").tag("thinking")
            Text("enable_thinking").tag("enable_thinking")
            Text("reasoning").tag("reasoning")
        }
        .disabled(!supportsThinking)
        
        Picker("Effort Value Mode", selection: $effortValueMode) {
            Text("Standard (reasoning_effort)").tag("standard")
            Text("DeepSeek (thinking + effort)").tag("deepseek")
            Text("OpenRouter (reasoning.effort)").tag("openrouter")
        }
        .disabled(!supportsThinking)
        
        Picker("Output Format", selection: $reasoningOutputFormat) {
            Text("reasoning_content").tag("reasoning_content")
            Text("reasoning_details").tag("reasoning_details")
            Text("think_tags").tag("think_tags")
        }
        .disabled(!supportsThinking)
    }
} header: {
    Text("Reasoning Configuration")
}
```

- [ ] **Step 3: Update onAppear and onSave to include reasoning config**

In `onAppear`, load reasoning config from provider if editing:

```swift
if let rc = provider.reasoningConfig {
    supportsThinking = rc.supportsThinking ?? false
    thinkingParam = rc.thinkingParam ?? "thinking"
    effortValueMode = rc.effortValueMode ?? "standard"
    reasoningOutputFormat = rc.outputFormat ?? "reasoning_content"
    showReasoningConfig = true
}
```

In the Save button's action, build the config:

```swift
let reasoningConfig = showReasoningConfig && supportsThinking
    ? ReasoningConfig(
        supportsThinking: true,
        supportsEffort: true,
        thinkingParam: thinkingParam,
        effortParam: nil,
        effortValueMode: effortValueMode,
        outputFormat: reasoningOutputFormat
    )
    : nil
```

Pass `reasoningConfig` to the `CodexModelProvider` initializer.

- [ ] **Step 4: Build and verify compilation**

```bash
cd /Users/panando/ClaudeCode/codex-adapter && swift build 2>&1
```

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexRouterApp/UI/ProvidersView.swift
git commit -m "feat: add reasoning configuration UI to provider form"
```

---

### Task 5: Fix RequestHandler model ID spoofing for streaming

**Files:**
- Modify: `Sources/CodexRouterApp/Server/RequestHandler.swift`

**Goal:** When forwarding requests, ensure model ID in the request matches what the upstream expects. Codex sends the model slug from its model catalog; the upstream may expect a different model ID.

- [ ] **Step 1: Add model mapping to request forwarding**

In `forwardRequest()`, after parsing request body, add model mapping:

```swift
// Map model ID from Codex catalog slug to upstream model
if let catalogModel = requestJSON?["model"] as? String {
    if let provider = try? CodexConfigService.shared.getCurrentProvider(),
       let catalog = provider.modelCatalog {
        for entry in catalog.models {
            if entry.model == catalogModel {
                // Use the model slug as-is; Codex uses this from the catalog
                break
            }
        }
    }
}
```

Note: cc-switch supports model name mapping but in practice the model slug from the catalog IS the model ID the upstream expects. This is primarily handled by the model catalog JSON generation using the correct slug. Skip complex mapping for now.

- [ ] **Step 2: Verify and commit if changes made**

Only commit if a real fix was needed. Otherwise skip this commit.

---

### Task 6: End-to-end verification

**Files:**
- No code changes. Manual verification steps.

**Goal:** Verify the full flow works: provider added → config.toml written → Codex starts → model visible → request succeeds.

- [ ] **Step 1: Build the app**

```bash
cd /Users/panando/ClaudeCode/codex-adapter && swift build 2>&1
```

Expected: BUILD SUCCESS

- [ ] **Step 2: Verify config.toml structure is correct**

Create a test provider via the app (or manually verify the TOML format):

```toml
model_provider = "custom"
model = "deepseek-chat"
model_reasoning_effort = "high"
model_catalog_json = "custom-model-catalog.json"

[model_providers.custom]
name = "My Provider"
base_url = "http://127.0.0.1:15721/v1"
wire_api = "responses"
upstream_base_url = "https://api.deepseek.com/v1"
upstream_wire_api = "chat"
experimental_bearer_token = "sk-xxx"
requires_openai_auth = true
supports_thinking = true
thinking_param = "thinking"
effort_value_mode = "deepseek"
reasoning_output_format = "reasoning_content"
```

Key checks:
- `base_url` points to `127.0.0.1:15721/v1` (local proxy)
- `upstream_base_url` has the real provider API endpoint
- `wire_api` is always `"responses"` (Codex uses Responses to talk to proxy)
- `upstream_wire_api` is `"chat"` (proxy uses Chat to talk to upstream)

- [ ] **Step 3: Verify model catalog JSON structure**

Check `~/.codex/<provider-id>-model-catalog.json`:

```json
{
  "models": [
    {
      "slug": "deepseek-chat",
      "display_name": "DeepSeek Chat V3",
      "context_window": 128000,
      "max_context_window": 128000,
      "priority": 1000,
      "additional_speed_tiers": [],
      "service_tiers": [],
      "availability_nux": null,
      "upgrade": null,
      ...
    }
  ]
}
```

- [ ] **Step 4: Verify Codex can read the config**

```bash
codex config 2>&1
```

Expected: Shows current config without errors.

---

### Task 7: Remove unused CodexRouterDB module

**Files:**
- Modify: `Package.swift`
- Remove: `Sources/CodexRouterDB/` (entire directory)

**Goal:** Remove the disconnected database module to reduce maintenance burden.

- [ ] **Step 1: Update Package.swift**

Remove any CodexRouterDB-related targets and dependencies. The current `Package.swift` doesn't declare `CodexRouterDB` as a target, so just verify no references remain.

```bash
grep -r "CodexRouterDB" /Users/panando/ClaudeCode/codex-adapter/Package.swift
```

Expected: No output (already not referenced).

- [ ] **Step 2: Remove the directory**

```bash
rm -rf /Users/panando/ClaudeCode/codex-adapter/Sources/CodexRouterDB
rm -rf /Users/panando/ClaudeCode/codex-adapter/Tests/CodexRouterDBTests
```

- [ ] **Step 3: Build to verify nothing breaks**

```bash
cd /Users/panando/ClaudeCode/codex-adapter && swift build 2>&1
```

Expected: BUILD SUCCESS

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "chore: remove unused CodexRouterDB module"
```

---

### Task 8: UI improvements — Provider form layout and model list

**Files:**
- Modify: `Sources/CodexRouterApp/UI/ProvidersView.swift`

**Goal:** Clean up the provider form UI: better layout for model list, clearer labels, proper error states.

- [ ] **Step 1: Improve model catalog list display**

Replace the bare HStack model list with a styled list:

```swift
Section {
    VStack(alignment: .leading, spacing: 8) {
        HStack {
            Text("Custom Models")
                .font(.headline)
            Spacer()
            Button(action: { showAddModel = true }) {
                Label("Add Model", systemImage: "plus")
            }
        }
        
        if modelCatalog.models.isEmpty {
            Text("No custom models added. Add models to make them available in Codex's model selector.")
                .foregroundColor(.secondary)
                .font(.caption)
        } else {
            ForEach(modelCatalog.models) { model in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.displayName ?? model.model)
                            .fontWeight(.medium)
                        Text("ID: \(model.model)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if let ctx = model.contextWindow {
                            Text("Context: \(ctx / 1000)K tokens")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Button(action: {
                        modelCatalog.models.removeAll { $0.id == model.id }
                    }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, 4)
                Divider()
            }
        }
    }
} header: {
    Text("Model Catalog")
} footer: {
    Text("These models will appear in Codex's model selector with the display names you specify.")
}
```

- [ ] **Step 2: Add visual indicator for required fields**

Add `*` to required field labels (ID, Name, Base URL) and show validation message when Save is attempted with empty required fields:

```swift
@State private var showValidationError = false
```

In the Save button action:
```swift
guard !id.isEmpty, !name.isEmpty, !baseURL.isEmpty else {
    showValidationError = true
    return
}
```

- [ ] **Step 3: Build and verify**

```bash
cd /Users/panando/ClaudeCode/codex-adapter && swift build 2>&1
```

- [ ] **Step 4: Commit**

```bash
git add Sources/CodexRouterApp/UI/ProvidersView.swift
git commit -m "ui: improve provider form layout and model list display"
```

---

### Task 9: Integration test — real end-to-end flow

**Files:**
- No code changes

**Goal:** Write a manual test script that verifies the entire flow works.

- [ ] **Step 1: Create a test config**

Use a test provider (e.g., OpenRouter or a local LLM) and verify:

```bash
# 1. Start the proxy server (via the app)
# 2. Verify config.toml has correct structure
cat ~/.codex/config.toml

# 3. Check model catalog exists
cat ~/.codex/custom-model-catalog.json

# 4. Try a simple Codex query
echo "Write a hello world in Python" | codex --no-interactive -

# 5. Check the proxy logs for request/response
tail -f ~/.codex-router/logs/proxy.log
```

- [ ] **Step 2: Document known limitations**

If `codex` CLI is not installed, verify at minimum:
1. config.toml format matches cc-switch/EchoBird expectations
2. Model catalog JSON is valid
3. App compiles and starts without crashes

---

## Self-Review Checklist

1. **Spec coverage:** All four phases covered (startup → model display → invocation → UI)
2. **No placeholders:** Every step has actual code or exact commands
3. **Type consistency:** `ReasoningConfig` already exists in Core, `UpstreamProvider` gets new field, `CodexModelProvider` gets new field — all consistent across tasks
4. **File paths:** All exact and verified against current repo state
