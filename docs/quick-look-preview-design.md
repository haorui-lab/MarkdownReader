# Quick Look 预览功能 — 技术方案

> 本文档记录 MarkdownReader 为 `.md` 文件提供 Finder Quick Look 空格预览的技术方案。

## 1. 结论

**技术上完全可行。** 通过 macOS 的 Quick Look Preview Extension（App Extension），MarkdownReader 可以在 Finder 中为 `.md` 文件提供渲染后的 Markdown 预览，包括 Mermaid 图表、KaTeX 公式、代码高亮等完整功能。

用户在「设置 → 通用」中可开关此功能，默认启用。关闭后系统回退到默认纯文本预览。

## 2. 方案选择

### 2.1 渲染方案：完整 WKWebView 渲染（非纯 HTML）

| 方案 | 复杂度 | 渲染质量 | Mermaid/KaTeX | 选择 |
|------|--------|----------|---------------|------|
| 纯 HTML 回复（内联 CSS） | 低 | 中 | ❌ | |
| QLPreviewProvider + WKWebView | 高 | 高 | ✅ | ✅ |
| 生成预览文件 + QLThumbnailProvider | 中 | 低 | ❌ | |

选择完整 WKWebView 方案，理由：
- 项目核心渲染逻辑（`MarkdownHTMLService` + `WKWebView` + `mr:///` URL Scheme）可直接复用
- Quick Look 预览效果与主应用一致，用户体验统一
- Mermaid 图表、KaTeX 公式是 Markdown 文档的常见内容，预览不应缺失

### 2.2 设置共享方案：CFPreferences（非 App Group）

| 方案 | 需要配置 | 适用场景 | 选择 |
|------|----------|----------|------|
| App Group + UserDefaults(suiteName:) | entitlements + 开发者账户 | Mac App Store | |
| CFPreferencesGetAppBooleanValue | 零配置 | ad-hoc 签名 | ✅ |

选择 CFPreferences，理由：
- 当前项目无 entitlements 文件，使用 ad-hoc 签名，CFPreferences 零配置即可工作
- Extension 只需读取一个 Bool 值，CFPreferences 完全满足
- 未来如需上 Mac App Store，迁移到 App Group 只需改一行代码

```swift
// Extension 中读取主应用设置
let appIdentifier = "com.markdownreader.app"
let enabled = CFPreferencesGetAppBooleanValue(
    "com.markdownreader.enableQuickLookPreview" as CFString,
    appIdentifier as CFString,
    nil
)
```

## 3. 核心架构

### 3.1 Target 拆分

当前 `Package.swift` 只有单一 `executableTarget`，需拆分为 3 个 target：

```
MarkdownReaderKit (library target)     ← 共享代码
MarkdownReader (executable target)     ← 主应用
MarkdownReaderQL (executable target)   ← Quick Look Extension
```

### 3.2 Extension 在 .app 包中的位置

```
MarkdownReader.app/
  Contents/
    MacOS/MarkdownReader               # 主应用可执行文件
    Extensions/
      MarkdownReaderQL.appex/          # Quick Look Extension
        Contents/
          MacOS/MarkdownReaderQL       # Extension 可执行文件
          Info.plist                   # Extension 配置
          Resources/                   # 共享资源 bundle
    Resources/                         # 主应用资源
    Info.plist                         # 主应用配置
```

### 3.3 设置开关行为

- **启用**（默认）：Extension 正常渲染 Markdown 并返回 WKWebView 预览
- **禁用**：Extension 抛出 `QLPreviewError.previewNotAvailable`，系统回退到默认纯文本预览

Extension 始终编译并包含在 .app 包中，设置只控制其行为，不控制其安装/卸载（macOS 无公开 API 动态注销 Extension）。

## 4. 关键技术挑战与解决方案

### 4.1 `mr:///` 自定义 URL Scheme

**问题**：当前 `buildFullHTML()` 生成的 HTML 依赖 `mr:///` 自定义 URL Scheme 加载所有资源（CSS、JS、字体），该 Scheme 通过 `WKURLSchemeHandler` 注册。Extension 运行在独立进程中，主应用的 Scheme Handler 不可用。

**解决方案**：Extension 注册自己的 `WKURLSchemeHandler`（方案 2c）。

`MarkdownURLSchemeHandler` 代码可直接复用，但需解决资源搜索路径问题：

```swift
// 主应用中：Bundle.main 指向 MarkdownReader.app
// Extension 中：Bundle.main 指向 MarkdownReaderQL.appex

// Extension 中定位主 app 的资源
let appBundleURL = Bundle.main.bundleURL
    .deletingLastPathComponent()  // Extensions/
    .deletingLastPathComponent()  // Contents/
    .appendingPathComponent("Resources")
```

或更灵活——将 `MarkdownURLSchemeHandler.resolveResourceURL` 改为接受 `resourceSearchPaths` 参数，由调用方传入不同路径。

### 4.2 Extension 内存限制

Quick Look Extension 约有 50MB 内存限制。加载 mermaid.min.js（~3MB）+ katex + prism 全套可能接近限制。

**缓解措施**：
- 优先加载核心渲染 JS
- Mermaid 按需加载（检测到 mermaid 代码块时才加载）
- 大文件场景下可能需禁用 Mermaid 渲染

### 4.3 Extension 启动时间

系统对 Extension 启动有超时要求。冷启动 WKWebView + 加载 JS 如果太慢会被杀。

**缓解措施**：
- 保持 Extension 入口轻量，延迟加载非必要资源
- 预渲染基础 HTML 结构，减少 WKWebView 初始加载量

### 4.4 主题适配

Extension 需要知道当前系统深色/浅色模式来选择主题 CSS。

```swift
// Extension 中检测外观模式（NSApp 可能不可用）
let isDark = NSAppearance.currentAppearance?
    .bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
```

### 4.5 SPM + App Extension 调试

纯脚本组装 .appex 后，Xcode 无法直接 attach debugger 到 Extension 进程。

**缓解措施**：
- 使用 `NSLog` 调试
- 或在开发阶段引入 Xcode 项目文件（.xcodeproj）进行调试

## 5. 实施步骤

| # | 步骤 | 关键产出 | 依赖 |
|---|------|----------|------|
| 1 | Package.swift 拆 3 target | `MarkdownReaderKit`（library）+ `MarkdownReader`（executable）+ `MarkdownReaderQL`（executable） | 无 |
| 2 | 抽离共享代码到 Kit | `MarkdownHTMLService`、`MarkdownURLSchemeHandler`、`OutlineService`、`ThemeColors`、`ThemeDefinition`、`L10n` 等 | 步骤 1 |
| 3 | 创建 QL Extension 入口 | `MarkdownQLPreviewProvider` 实现 `QLPreviewProvider`，注册 `WKURLSchemeHandler` | 步骤 2 |
| 4 | 适配资源路径 | `MarkdownURLSchemeHandler.resolveResourceURL` 支持从主 app bundle 搜索资源 | 步骤 2 |
| 5 | Extension Info.plist | `QLPreviewExtension` + `QLSupportedContentTypes` = `[net.daringfireball.markdown]` | 步骤 3 |
| 6 | SettingsModel 新增属性 | `enableQuickLookPreview: Bool`，默认 `true` | 无 |
| 7 | GeneralSettingsView 新增区段 | 放在「默认打开程序」和「命令行工具」之间 | 步骤 6 |
| 8 | 本地化 3 个 key × 3 语言 | Quick Look 标题/描述/开关文字 | 步骤 7 |
| 9 | Extension 读取设置 | `CFPreferencesGetAppBooleanValue` 读取主应用 UserDefaults | 步骤 3 |
| 10 | 改造 build-app.sh | 编译 Extension → 创建 .appex bundle → 放入 `Contents/Extensions/` → 签名 | 步骤 3 |

## 6. 设置项设计

### 6.1 位置

通用设置页面，放在「默认打开程序」和「命令行工具」之间：

```
通用设置页面：
├─ 界面语言
├─ 默认显示模式
├─ 启动时重新打开上次位置
├─ 在侧边栏显示隐藏文件
├─ 在侧边栏显示非 Markdown 文件
├─ ────────────────
├─ 默认打开程序      ← 已有
├─ Quick Look 预览   ← 新增，默认选中
├─ ────────────────
├─ 命令行工具        ← 已有
```

### 6.2 SettingsModel 新增

```swift
// Keys 枚举
static let enableQuickLookPreview = "com.markdownreader.enableQuickLookPreview"

// 属性
var enableQuickLookPreview: Bool {
    didSet { defaults.set(enableQuickLookPreview, forKey: Keys.enableQuickLookPreview) }
}

// init 中
self.enableQuickLookPreview = defaults.object(forKey: Keys.enableQuickLookPreview) as? Bool ?? true
```

### 6.3 本地化 Key

| Key | 英文 | 简体中文 | 繁体中文 |
|-----|------|----------|----------|
| `settingsGeneralQuickLookTitle` | Quick Look Preview | Quick Look 预览 | Quick Look 預覽 |
| `settingsGeneralQuickLookDesc` | Enable Markdown rendering in Finder Quick Look (press Space to preview). | 在 Finder 中按空格键预览 Markdown 文件的渲染效果。 | 在 Finder 中按空白鍵預覽 Markdown 檔案的渲染效果。 |
| `settingsGeneralQuickLookEnabled` | Enable Quick Look preview | 启用 Quick Look 预览 | 啟用 Quick Look 預覽 |

## 7. Extension 核心代码结构

### 7.1 Extension 入口

**注意：实际实现与初版方案有以下差异：**

1. `QLPreviewExtension`/`QLPreviewing` 协议不存在，正确模式是 `class ... : QLPreviewProvider, QLPreviewingController`
2. `QLPreviewReply` 的闭包参数返回 `Data`，不是 `QLPreviewReply` 对象上的 `write` 方法
3. 使用 `@objc` 标注类名，确保 Objective-C runtime 能找到 Principal Class
4. `mr:///` URL Scheme 在 data-based preview 中不可用，改为内联 CSS/JS 资源
5. `NSAppearance.currentAppearance` 已废弃，改用 `NSAppearance.currentDrawing()`

实际代码：

```swift
// Sources/MarkdownReaderQL/MarkdownQLPreviewProvider.swift
import QuickLookUI
import MarkdownReaderKit

@objc(MarkdownQLPreviewProvider)
final class MarkdownQLPreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        // 检查主应用设置（通过 CFPreferences 跨进程读取）
        let enabled = CFPreferencesGetAppBooleanValue(
            "com.markdownreader.enableQuickLookPreview" as CFString,
            "com.markdownreader.app" as CFString,
            nil
        )

        guard enabled else {
            throw CocoaError(.userCancelled)
        }

        let content = try String(contentsOf: request.fileURL, encoding: .utf8)
        let isDark = detectDarkMode()

        let theme = PresetThemes.defaultTheme(for: isDark ? .dark : .light)
        let themeColors = ThemeColors.from(theme)

        // 内联 CSS/JS 资源（mr:/// URL Scheme 在 data-based preview 中不可用）
        let (inlineCSS, inlineJS) = loadInlineResources()

        let html = MarkdownHTMLService.buildPreviewHTML(
            content: content,
            themeCSS: themeColors.cssCustomProperties + themeColors.codeHighlightCSS,
            inlineCSS: inlineCSS,
            inlineJS: inlineJS,
            contentPadding: 20,
            baseURL: request.fileURL,
            isDark: isDark
        )

        let htmlData = html.data(using: String.Encoding.utf8)!
        return QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 800, height: 600)) { _ in
            htmlData
        }
    }
}
```

### 7.2 资源内联策略

Extension 使用 `buildPreviewHTML` 而非 `buildFullHTML`，将 CSS/JS 内联到 HTML 中：

- `buildFullHTML`：主应用使用，CSS/JS 通过 `mr:///` URL Scheme 加载
- `buildPreviewHTML`：Extension 使用，CSS/JS 直接内联到 `<style>` 和 `<script>` 标签中

Extension 在运行时从 `MarkdownReader_MarkdownReader.bundle` 读取资源文件并内联。

        // 返回 HTML 预览
        return QLPreviewReply(dataOfContentType: .html) { writer in
            try writer.write(html.data(using: .utf8)!)
        }
    }
}
```

### 7.2 Extension Info.plist

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.markdownreader.app.QuickLook</string>
    <key>CFBundleName</key>
    <string>Markdown Reader Quick Look</string>
    <key>CFBundleDisplayName</key>
    <string>Markdown Reader Quick Look</string>
    <key>CFBundleVersion</key>
    <string>__VERSION__</string>
    <key>CFBundleShortVersionString</key>
    <string>__VERSION__</string>
    <key>CFBundlePackageType</key>
    <string>XPC!</string>
    <key>QLPreviewExtension</key>
    <dict>
        <key>QLSupportedContentTypes</key>
        <array>
            <string>net.daringfireball.markdown</string>
        </array>
        <key>QLSupportsSearchableItems</key>
        <false/>
    </dict>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.quicklook.preview</string>
        <key>NSExtensionPrincipalClass</key>
        <string>MarkdownQLExtension</string>
    </dict>
</dict>
</plist>
```

## 8. 风险评估

| 风险 | 影响 | 可能性 | 缓解 |
|------|------|--------|------|
| Extension 内存限制（~50MB） | Phase 2 加载大量 JS 可能 OOM | 中 | 按需加载 Mermaid，大文件场景降级 |
| Extension 启动超时 | 冷启动 WKWebView 太慢会被杀 | 低 | 保持入口轻量 |
| SPM 调试困难 | 无法 attach debugger | 高 | NSLog 调试或引入 Xcode 项目 |
| `mr:///` 资源路径在 Extension 中不同 | CSS/JS 无法加载 | 高 | 适配 resolveResourceURL 搜索路径 |
| Swift 6 严格并发 | Extension 入口需满足 Sendable | 低 | QLPreviewProvider 的 async 接口天然兼容 |
| CFPreferences 跨进程延迟 | 设置变更后 Extension 可能延迟读取 | 低 | UserDefaults 同步间隔通常 < 1s |

## 9. 预估工时

| 阶段 | 工时 | 说明 |
|------|------|------|
| Target 拆分 + 共享代码抽离 | 2-3 天 | 最大工作量，需仔细处理依赖关系 |
| Extension 入口 + 资源路径适配 | 1-2 天 | 核心功能开发 |
| 设置 UI + 本地化 | 0.5 天 | 简单 Toggle |
| build-app.sh 改造 | 1 天 | 脚本组装 .appex |
| 调试 + 修复 | 2-3 天 | SPM + Extension 调试困难 |
| **合计** | **7-10 天** | |
