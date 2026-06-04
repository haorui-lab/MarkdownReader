# 查找替换功能 — 技术设计文档

> 版本：1.0 | 日期：2026-06-04 | 状态：设计确认，待实现

## 1. 概述

实现 VSCode 风格的浮动查找替换面板，锚定在文档区域右上角。一期覆盖基础查找替换功能，二期补充 Rendered 模式高亮和正则反向引用替换。

## 2. 功能分期

### 一期（当前）

| 功能 | Raw 模式 | Rendered 模式 |
|------|---------|-------------|
| 文本查找 | ✅ 带高亮 | ✅ 跳转定位（无高亮） |
| 大小写敏感 (Aa) | ✅ | ✅ |
| 全词匹配 (W*) | ✅ | ✅ |
| 正则搜索 (.*) | ✅ | ✅ |
| 匹配计数 (3/15) | ✅ | ✅ |
| 上/下导航 | ✅ | ✅ |
| 替换当前 | ✅ | ❌ 按钮灰化 |
| 全部替换 | ✅ | ❌ 按钮灰化 |
| 搜索高亮 | ✅ NSTextStorage 背景色 | ❌ |
| 主题色跟随 | ✅ | ✅ |
| 快捷键 | ✅ | ✅ |

### 二期（后续）

| 功能 | 说明 |
|------|------|
| Rendered 模式搜索高亮 | 在渲染视图中高亮匹配文本（需研究 Textual API 或自定义渲染） |
| 正则反向引用替换 | 替换时支持 `$1`、`$2` 等捕获组引用 |

## 3. UI 设计

### 3.1 布局

```
┌─────────────────────────────────────────────────────────┐
│ ▼  🔍 [搜索框________________] 3/15  [Aa][W*][.*] ▲ ▼ ✕ │
│    🔄 [替换框________________] [替换] [全部替换]          │
└─────────────────────────────────────────────────────────┘
```

### 3.2 视觉规格

| 属性 | 值 |
|------|-----|
| 位置 | `overlay(alignment: .topTrailing)`，右上角 |
| 宽度 | 400pt，固定 |
| 圆角 | 8pt（四角） |
| 阴影 | `shadow(color: .black.opacity(0.2), radius: 16, y: 6)` |
| 背景 | `themeColors.surface` + 0.95 opacity |
| 边框 | `themeColors.border`，1pt |
| 搜索框 | 等宽字体，焦点时 `themeColors.accent` 边框 |
| 匹配计数 | 搜索框内右对齐，无匹配时 `themeColors.danger` |
| 按钮 | `.plain` 样式，激活时 `themeColors.accent` 边框 |
| ▼/▶ | 展开/收起替换行 |

### 3.3 交互

- 打开面板时搜索框自动获取焦点
- 输入时实时搜索（防抖 100ms）
- Enter → 查找下一个，Shift+Enter → 查找上一个
- Esc → 关闭面板
- 无文档时面板不显示

## 4. 快捷键

| 快捷键 | 功能 |
|--------|------|
| Cmd+F | 打开查找面板（已打开时聚焦搜索框） |
| Cmd+G | 查找下一个 |
| Cmd+Shift+G | 查找上一个 |
| Cmd+Option+F | 打开查找面板并展开替换行 |
| Esc | 关闭面板 |
| Enter | 查找下一个（搜索框焦点时） |
| Shift+Enter | 查找上一个（搜索框焦点时） |

## 5. 技术设计

### 5.1 关键技术决策

| 决策项 | 选择 | 原因 |
|--------|------|------|
| `usesFindBar` | **设为 false** | 否则 Cmd+F 会触发原生 Find Bar，无法拦截 |
| 搜索实现 | **NSRegularExpression + 手动管理** | 需要匹配计数/索引，原生 API 不提供 |
| 高亮方式 | **NSTextStorage.addAttribute(.backgroundColor)** | 与语法高亮的 .foregroundColor/.font 不冲突 |
| 高亮/语法冲突 | **reapplyHighlights 后重新叠加搜索高亮** | 语法高亮会 setAttributes 全文本重置 |
| SwiftUI ↔ NSTextView 通信 | **弱引用 ref 类**（复用 MarkdownScrollViewRef 模式） | 已有成熟模式 |
| 替换后处理 | **重新应用语法高亮 + 重新叠加搜索高亮** | replace 改变文本后范围失效 |

### 5.2 文件改动清单

| # | 文件 | 改动说明 |
|---|------|----------|
| 1 | `FindReplaceBar.swift` (新建) | SwiftUI 浮动面板组件 |
| 2 | `FindReplaceViewModel.swift` (新建) | 搜索状态 + NSRegularExpression 搜索逻辑 + 匹配管理 |
| 3 | `SyntaxHighlightedEditor.swift` | ① `usesFindBar = false` ② 新增 `TextViewSearchRef` 弱引用类 |
| 4 | `DetailView.swift` | 在 `documentContentView` 上添加 overlay |
| 5 | `MarkdownReaderApp.swift` | Find 菜单组 + 快捷键 + Notification.Name |
| 6 | `AppViewModel.swift` | `isFindBarVisible` 状态 + `toggleFindBar()` 方法 |
| 7 | `L10n` | 约 12 个本地化键 |

### 5.3 搜索高亮与语法高亮的共存

**问题**：`MarkdownSyntaxHighlighter.applyHighlights` 每次调用都会 `setAttributes(defaultAttrs, range: fullRange)` 重置所有属性，覆盖搜索高亮。

**解决方案**：在 `SyntaxHighlightedEditor.Coordinator.reapplyHighlights()` 末尾，重新叠加搜索高亮：

```swift
// reapplyHighlights() 现有代码结束后：
if let searchRef = parent.searchRef {
    searchRef.reapplySearchHighlights()
}
```

`TextViewSearchRef` 持有当前搜索的匹配范围列表，`reapplySearchHighlights()` 用 `.backgroundColor` 重新着色。

### 5.4 两种模式的搜索策略

#### Raw 模式

1. 搜索源：`textView.string`
2. 通过 `TextViewSearchRef` 弱引用访问 NSTextView
3. 用 `NSRegularExpression` 执行搜索，收集所有匹配范围
4. 高亮：`textStorage.addAttribute(.backgroundColor, value: highlightColor, range: matchRange)`
5. 导航：`textView.setSelectedRange(matchRange)` + `textView.scrollRangeToVisible(matchRange)`
6. 替换：`textStorage.replaceCharacters(in: currentMatch, with: replacementText)`，然后重新搜索 + 高亮

#### Rendered 模式

1. 搜索源：`documentViewModel.content`（源 Markdown 文本）
2. 用 `NSRegularExpression` 执行搜索，收集所有匹配范围
3. 将字符偏移转换为行号
4. 导航：通过已有的 `scrollToLineRequest` 机制跳转
5. 替换按钮灰化（渲染视图只读）

### 5.5 新增类设计

#### `TextViewSearchRef`

```swift
@MainActor
final class TextViewSearchRef {
    weak var textView: HighlightableTextView?
    private var matchRanges: [NSRange] = []

    /// 应用搜索高亮（在语法高亮之后调用）
    func reapplySearchHighlights()

    /// 清除搜索高亮
    func clearSearchHighlights()

    /// 跳转到指定匹配项
    func selectMatch(at index: Int)

    /// 执行替换
    func replaceCurrentMatch(with text: String) -> Bool

    /// 执行全部替换
    func replaceAll(with text: String) -> Int
}
```

#### `FindReplaceViewModel`

```swift
@MainActor
@Observable
final class FindReplaceViewModel {
    var searchText: String = ""
    var replaceText: String = ""
    var isCaseSensitive: Bool = false
    var isWholeWord: Bool = false
    var isRegularExpression: Bool = false
    var currentMatchIndex: Int = 0
    var totalMatchCount: Int = 0
    var isReplaceExpanded: Bool = false

    /// 执行搜索
    func performSearch(in text: String)

    /// 导航到下一个/上一个匹配
    func goToNextMatch()
    func goToPreviousMatch()

    /// 替换操作（仅 Raw 模式）
    func replaceCurrent()
    func replaceAll()
}
```

### 5.6 Notification 通信

新增 4 个 `Notification.Name`（遵循 `com.markdownreader.xxx` 命名规范）：

| 名称 | 常量名 | 用途 |
|------|--------|------|
| `com.markdownreader.findInDocument` | `.findInDocument` | Cmd+F — 打开查找面板 |
| `com.markdownreader.findNext` | `.findNext` | Cmd+G — 查找下一个 |
| `com.markdownreader.findPrevious` | `.findPrevious` | Cmd+Shift+G — 查找上一个 |
| `com.markdownreader.findAndReplace` | `.findAndReplace` | Cmd+Option+F — 打开查找+替换面板 |

### 5.7 本地化键

| 键名 | 英文 | 简中 | 繁中 |
|------|------|------|------|
| findBarSearchPlaceholder | Search | 搜索 | 搜尋 |
| findBarReplacePlaceholder | Replace | 替换 | 取代 |
| findBarFindNext | Find Next | 查找下一个 | 尋找下一個 |
| findBarFindPrevious | Find Previous | 查找上一个 | 尋找上一個 |
| findBarReplace | Replace | 替换 | 取代 |
| findBarReplaceAll | Replace All | 全部替换 | 全部取代 |
| findBarNoResults | No results | 无结果 | 無結果 |
| findBarCaseSensitive | Match Case | 区分大小写 | 區分大小寫 |
| findBarWholeWord | Match Whole Word | 全词匹配 | 全字匹配 |
| findBarRegularExpression | Use Regular Expression | 使用正则表达式 | 使用規則表達式 |
| findBarFind | Find | 查找 | 尋找 |
| findBarFindAndReplace | Find and Replace | 查找和替换 | 尋找和取代 |

## 6. 实现顺序

1. **FindReplaceViewModel** — 搜索状态和逻辑核心
2. **TextViewSearchRef** — NSTextView 搜索/高亮/替换接口
3. **SyntaxHighlightedEditor** — 集成 TextViewSearchRef，关闭 usesFindBar
4. **FindReplaceBar** — SwiftUI 浮动面板 UI
5. **DetailView** — 集成浮动面板 overlay
6. **AppViewModel + MarkdownReaderApp** — 状态管理 + 菜单命令
7. **L10n** — 本地化键
8. **测试验证** — 两种模式下的查找/替换/导航功能

## 7. 注意事项

- **`usesFindBar = false`**：关闭后 NSTextView 不再响应 responder chain 中的 Find 动作，所有查找替换操作均通过自定义 Notification + ViewModel 路径触发
- **语法高亮覆盖搜索高亮**：每次 `reapplyHighlights()` 会 `setAttributes(defaultAttrs, range: fullRange)` 重置所有属性，必须在末尾重新叠加搜索高亮
- **替换后需重新搜索**：`textStorage.replaceCharacters` 改变文本后，所有匹配范围失效，必须重新执行 `performSearch` 并重新高亮
- **正则搜索容错**：用户输入过程中正则可能不合法，`NSRegularExpression` 初始化会抛异常，需要 `try?` 静默失败并显示「无结果」
- **大文件性能**：搜索使用 `NSRegularExpression` 遍历全文本，对于超大文件（>1MB）可能需要限制搜索范围或添加防抖
- **Raw 视图始终存活**：`RawMarkdownView` 在 ZStack 中始终存在（opacity 控制显隐），因此 `TextViewSearchRef` 的弱引用始终有效
- **替换操作与 per-file UndoManager**：所有替换操作通过 `textStorage.replaceCharacters` 执行，自动记录到 per-file UndoManager，确保 Cmd+Z 可撤销
- **Esc 键处理**：SwiftUI `.onKeyPress(.escape)` 或 `focusable` + key event 处理，需确保不与 NSTextView 的 Esc 处理冲突
