# Quick Look 预览功能 — 技术方案

> 本文档记录 MarkdownReader 为 `.md` 文件提供 Finder Quick Look 空格预览的技术方案。
> 最后更新：2026-06-08（实现后修订版）

## 1. 结论

**已实现并验证。** 通过 macOS 的 Quick Look Preview Extension（App Extension），MarkdownReader 在 Finder 中为 `.md` 文件提供渲染后的 Markdown 预览，包括 Mermaid 图表、KaTeX 公式、代码高亮等完整功能。

用户在「设置 → 通用」中可开关此功能，默认启用。关闭后系统回退到默认纯文本预览。

## 2. 方案选择

### 2.1 渲染方案：View-based WKWebView（非 Data-based）

| 方案 | 复杂度 | 渲染质量 | Mermaid/KaTeX | 选择 |
|------|--------|----------|---------------|------|
| Data-based (QLPreviewProvider) | 中 | 中 | ❌ | |
| **View-based (NSViewController + QLPreviewingController)** | 高 | 高 | ✅ | ✅ |
| 生成预览文件 + QLThumbnailProvider | 中 | 低 | ❌ | |

选择 View-based 方案，理由：
- macOS 26 上 data-based preview（`QLPreviewProvider`）不被 `pluginkit` 识别注册
- 所有已知的第三方 QL Extension（XMind 等）均使用 view-based 方案
- 支持 WKWebView 完整渲染能力
- `QLPreviewingController.preparePreviewOfFile(at:completionHandler:)` 提供文件 URL，可直接读取

### 2.2 设置共享方案：CFPreferences（非 App Group）

| 方案 | 需要配置 | 适用场景 | 选择 |
|------|----------|----------|------|
| App Group + UserDefaults(suiteName:) | entitlements + 开发者账户 | Mac App Store | |
| **CFPreferencesGetAppBooleanValue** | 零配置 | ad-hoc 签名 | ✅ |

```swift
// Extension 中读取主应用设置
let enabled = CFPreferencesGetAppBooleanValue(
    "com.markdownreader.enableQuickLookPreview" as CFString,
    "com.markdownreader.app" as CFString,
    nil
)
```

### 2.3 入口点方案：C Wrapper + 手动链接

SPM 的 `executableTarget` 生成普通可执行文件（入口 `_main`），但 App Extension 必须使用 `_NSExtensionMain` 作为入口点。`_NSExtensionMain` 在 AppKit 中，负责读取 `Info.plist` 的 `NSExtensionPrincipalClass` 并实例化。

**解决方案**：
1. `Package.swift` 中 QL target 使用 `.target`（非 `.executableTarget`），SPM 只编译不链接
2. 在 `build-app.sh` 中用 C wrapper 提供 `main()` → `NSExtensionMain()`，再用 `clang` 手动链接所有 .o 文件

```c
// C wrapper: main.c
extern int NSExtensionMain(int argc, char **argv);
int main(int argc, char **argv) {
    return NSExtensionMain(argc, argv);
}
```

## 3. 核心架构

### 3.1 Target 拆分

```
MarkdownReaderKit (target, library)      ← 共享代码
MarkdownReader (executableTarget)         ← 主应用
MarkdownReaderQL (target, not executable) ← Quick Look Extension（build-app.sh 手动链接）
```

### 3.2 Extension 在 .app 包中的位置

⚠️ **必须放在 `Contents/PlugIns/`**，不是 `Contents/Extensions/`。macOS 只扫描 `PlugIns` 目录。

```
MarkdownReader.app/
  Contents/
    MacOS/MarkdownReader                    # 主应用可执行文件
    PlugIns/
      MarkdownReaderQL.appex/              # Quick Look Extension
        Contents/
          MacOS/MarkdownReaderQL            # Extension 可执行文件（手动链接）
          Info.plist                        # Extension 配置
          Resources/
            MarkdownReader_MarkdownReader.bundle/  # CSS/JS/字体资源
    Resources/                              # 主应用资源
    Info.plist                              # 主应用配置（含 CFBundlePlugIns）
```

### 3.3 设置开关行为

- **启用**（默认）：Extension 正常渲染 Markdown 并返回 WKWebView 预览
- **禁用**：Extension 的 `preparePreviewOfFile` 返回错误，系统回退到默认纯文本预览

Extension 始终编译并包含在 .app 包中，设置只控制其行为（通过 CFPreferences 读取主应用的 `enableQuickLookPreview` 值）。

### 3.4 沙盒 Entitlements（关键！）

macOS **不加载**没有 `com.apple.security.app-sandbox` entitlement 的 App Extension。

```xml
<!-- scripts/MarkdownReaderQL.entitlements -->
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-only</key>
    <true/>
</dict>
```

签名时必须指定 entitlements：
```bash
codesign --force --entitlements scripts/MarkdownReaderQL.entitlements --sign "$IDENTITY" MarkdownReaderQL.appex
```

⚠️ 主 app 签名**不能使用 `--deep`**，否则会覆盖 Extension 的 entitlements。

## 4. 关键技术挑战与解决方案

### 4.1 SPM 不支持 App Extension 入口点

**问题**：SPM 的 `executableTarget` 生成 `_main` 入口点，App Extension 需要 `_NSExtensionMain`。`@_cdecl("main")` 在 release 模式下与 SPM 的 `command-line-aliases-file` 冲突。`-e _NSExtensionMain` linker flag 导致 Swift 模块加载失败。

**解决方案**：将 QL target 改为 `.target`（非 executable），在 `build-app.sh` 中用 C wrapper + clang 手动链接。

### 4.2 `mr:///` 自定义 URL Scheme

**问题**：主应用使用 `mr:///` 自定义 URL Scheme（通过 `WKURLSchemeHandler`）加载资源，Extension 运行在独立进程中无法使用。

**解决方案**：Extension 使用 `buildPreviewHTML()` 方法，将 CSS/JS 内联到 HTML 中，不依赖 `mr:///`。

### 4.3 Extension 资源搜索路径

**问题**：Extension 中 `Bundle.main` 指向 `.appex` bundle，资源在 `MarkdownReader_MarkdownReader.bundle/Resources/` 下。

**解决方案**：`resolveResourceURL()` 搜索多个路径：
1. `Bundle.main.resourceURL/MarkdownReader_MarkdownReader.bundle/Resources`
2. `Bundle.main.resourceURL`
3. 主 app 的 `Contents/Resources`（通过 `Bundle.main.bundleURL` 导航）

### 4.4 Extension 内存限制

Quick Look Extension 约有 50MB 内存限制。

**缓解措施**：
- 优先加载核心渲染 JS
- Mermaid 按需加载（检测到 mermaid 代码块时才加载）
- 大文件场景下可能需禁用 Mermaid 渲染

### 4.5 主题适配

```swift
let isDark = NSAppearance.currentDrawing()
    .bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
```

## 5. 实施步骤（已完成）

| # | 步骤 | 状态 |
|---|------|------|
| 1 | Package.swift 拆 3 target | ✅ |
| 2 | 抽离共享代码到 MarkdownReaderKit | ✅ |
| 3 | 创建 QL Extension 入口（view-based） | ✅ |
| 4 | buildPreviewHTML() 内联 CSS/JS | ✅ |
| 5 | Extension Info.plist（NSExtensionAttributes + PlugIns 目录） | ✅ |
| 6 | SettingsModel 新增 enableQuickLookPreview | ✅ |
| 7 | GeneralSettingsView 新增 Quick Look 区段 | ✅ |
| 8 | 本地化 3 key × 3 语言 | ✅ |
| 9 | CFPreferences 读取主应用设置 | ✅ |
| 10 | build-app.sh 手动链接 Extension + entitlements | ✅ |
| 11 | 沙盒 entitlements 文件 | ✅ |
| 12 | NSExtensionMain C wrapper 入口 | ✅ |

## 6. 设置项设计

### 6.1 位置

通用设置页面，放在「默认打开程序」和「命令行工具」之间：

```
通用设置页面：
├─ 界面语言
├─ 默认显示模式
├─ 渲染宽度
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

// init 中（默认 true）
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

```swift
// Sources/MarkdownReaderQL/MarkdownQLPreviewProvider.swift
import AppKit
import QuickLookUI
import MarkdownReaderKit
import WebKit

@MainActor
final class MarkdownQLPreviewProvider: NSViewController, QLPreviewingController {
    private var webView: WKWebView!

    override func loadView() { view = NSView() }

    override func viewDidLoad() {
        super.viewDidLoad()
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: config)
        // ... 约束设置
    }

    nonisolated func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        // 1. 检查主应用设置
        let enabled = CFPreferencesGetAppBooleanValue(...)
        guard enabled else { handler(...); return }

        // 2. 读取文件、检测主题、内联资源
        // 3. 调用 MarkdownHTMLService.buildPreviewHTML()
        // 4. webView.loadHTMLString(html)
        handler(nil)
    }
}
```

### 7.2 C Wrapper（由 build-app.sh 自动生成）

```c
extern int NSExtensionMain(int argc, char **argv);
int main(int argc, char **argv) {
    return NSExtensionMain(argc, argv);
}
```

### 7.3 Extension Info.plist

```xml
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.markdownreader.app.QuickLook</string>
    <key>CFBundlePackageType</key>
    <string>XPC!</string>
    <key>CFBundleExecutable</key>
    <string>MarkdownReaderQL</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionAttributes</key>
        <dict>
            <key>QLIsDataBasedPreview</key>
            <false/>
            <key>QLSupportedContentTypes</key>
            <array>
                <string>net.daringfireball.markdown</string>
            </array>
            <key>QLSupportsSearchableItems</key>
            <false/>
        </dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.quicklook.preview</string>
        <key>NSExtensionPrincipalClass</key>
        <string>MarkdownReaderQL.MarkdownQLPreviewProvider</string>
    </dict>
</dict>
```

**关键点**：
- `QLIsDataBasedPreview` = `false`（view-based，非 data-based）
- `QLSupportedContentTypes` 和 `QLSupportsSearchableItems` 必须在 `NSExtensionAttributes` 子字典中
- `NSExtensionPrincipalClass` 使用模块前缀格式 `ModuleName.ClassName`

### 7.4 主应用 Info.plist 声明

```xml
<key>CFBundlePlugIns</key>
<array>
    <string>Contents/PlugIns/MarkdownReaderQL.appex</string>
</array>
```

## 8. 排错记录

实现过程中遇到的关键问题：

| 问题 | 症状 | 原因 | 解决方案 |
|------|------|------|----------|
| Extension 目录错误 | pluginkit 不注册 | `Contents/Extensions/` 不是 macOS 扫描目录 | 改为 `Contents/PlugIns/` |
| 入口点错误 | pluginkit 不注册 | SPM 生成 `_main`，App Extension 需要 `_NSExtensionMain` | C wrapper + 手动链接 |
| 缺少沙盒 entitlement | pluginkit 不注册 | macOS 不加载无沙盒的 App Extension | 添加 `MarkdownReaderQL.entitlements` |
| Data-based preview 不注册 | pluginkit 不显示 | macOS 26 不通过 pluginkit 注册 data-based QL extension | 改用 view-based |
| Info.plist 格式错误 | pluginkit 不注册 | `QLSupportedContentTypes` 需在 `NSExtensionAttributes` 子字典中 | 修正 plist 结构 |
| Principal Class 缺少模块前缀 | Extension 加载失败 | Swift 类需 `ModuleName.ClassName` 格式 | `MarkdownReaderQL.MarkdownQLPreviewProvider` |
| `--deep` 签名覆盖 entitlements | Extension 丢失沙盒 | `codesign --deep` 递归签名时忽略 entitlements | 先签 Extension（带 entitlements），再签主 app（不带 --deep） |

## 9. 风险评估

| 风险 | 影响 | 可能性 | 缓解 |
|------|------|--------|------|
| Extension 内存限制（~50MB） | 大文件 + Mermaid 可能 OOM | 中 | 按需加载 Mermaid |
| Extension 启动超时 | 冷启动太慢会被杀 | 低 | 保持入口轻量 |
| SPM 调试困难 | 无法 attach debugger | 高 | NSLog 调试 |
| CFPreferences 跨进程延迟 | 设置变更后 Extension 延迟读取 | 低 | 同步间隔 < 1s |
| Prism autoloader 不工作 | 非默认语言代码高亮缺失 | 中 | 预览场景可接受 |

## 10. 预估工时（实际）

| 阶段 | 预估 | 实际 | 说明 |
|------|------|------|------|
| Target 拆分 + 共享代码抽离 | 2-3 天 | 2 天 | |
| Extension 入口 + 资源路径适配 | 1-2 天 | 3 天 | 入口点问题排查耗时 |
| 设置 UI + 本地化 | 0.5 天 | 0.5 天 | |
| build-app.sh 改造 | 1 天 | 2 天 | 手动链接 + entitlements |
| 排错（注册问题） | - | 2 天 | 3 个关键问题逐个排查 |
| **合计** | **7-10 天** | **~9.5 天** | |
