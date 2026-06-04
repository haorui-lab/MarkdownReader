# 查找替换功能开发总结

## 概述

为 MarkdownReader 添加 VSCode 风格的查找替换功能。从方案讨论到实现再到 Bug 修复，经历了多轮迭代。

## 功能规格

### 已实现功能

| 功能 | 状态 | 说明 |
|------|------|------|
| 查找面板 | ✅ | VSCode 风格浮动面板，锚定文档区域右上角顶部 |
| Cmd+F 打开 | ✅ | 菜单快捷键 + Notification 通信 |
| Esc 关闭 | ✅ | onKeyPress 处理 |
| 文本查找 | ✅ | Raw 模式搜索 NSTextView 内容，Rendered 模式搜索源 Markdown |
| 大小写敏感 | ✅ | Aa 按钮切换 |
| 全词匹配 | ✅ | W* 按钮切换，使用 `\b` 边界 |
| 正则搜索 | ✅ | .* 按钮切换，无效正则静默失败显示无结果 |
| 匹配计数 | ✅ | 实时显示 "3/15" 格式，无匹配时红色边框提示 |
| 上/下导航 | ✅ | ▲▼ 按钮 + Cmd+G / Cmd+Shift+G |
| 替换当前 | ✅ | 仅 Raw 模式可用 |
| 全部替换 | ✅ | 仅 Raw 模式可用，从后向前替换避免偏移问题 |
| 搜索高亮 | ✅ | Raw 模式下用 NSTextStorage backgroundColor 高亮 |
| 主题色跟随 | ✅ | 面板背景、边框、按钮颜色跟随当前主题 |
| 替换行展开/收起 | ✅ | ▶/▼ 按钮控制 |
| 三语本地化 | ✅ | 英文/简中/繁中，12 个 L10n 键 |

### 未实现功能

| 功能 | 优先级 | 说明 |
|------|--------|------|
| Rendered 模式高亮 | P2 | 受 Textual API 限制，无法在渲染视图中高亮匹配文本 |
| 正则反向引用替换 | P3 | 替换支持 $1 等反向引用 |
| 文件名搜索 | P2 | 在目录树中搜索文件名 |
| 全文搜索 | P3 | 在所有 Markdown 文件中搜索内容 |

## 架构设计

### 文件结构

```
新增文件：
├── ViewModels/FindReplaceViewModel.swift    # 搜索状态 + NSRegularExpression 逻辑
├── Views/FindReplaceBar.swift               # VSCode 风格浮动面板 UI
└── docs/find-replace-design.md              # 设计文档

修改文件：
├── App/MarkdownReaderApp.swift              # 查找菜单 + 4 个 Notification.Name
├── ViewModels/AppViewModel.swift             # isFindBarVisible 状态
├── Views/ContentView.swift                  # 目录切换清除选中
├── Views/DetailView.swift                   # 查找替换逻辑核心
├── Views/RawMarkdownView.swift              # 透传参数
├── Views/SyntaxHighlightedEditor.swift      # TextViewSearchRef + 搜索高亮
└── Services/LocalizationService.swift       # 12 个 L10n 键
```

### 数据流

```
用户输入搜索文本
  → FindReplaceViewModel.performSearch()  # NSRegularExpression 匹配
  → DetailView.performSearch()            # 分派到 Raw/Rendered 模式
    → Raw: TextViewSearchRef.reapplySearchHighlights()  # NSTextStorage 高亮
    → Rendered: DocumentViewModel.requestScrollToLine()  # 行号跳转
```

### 关键类

- **FindReplaceViewModel**: `@MainActor @Observable`，管理搜索状态、NSRegularExpression 匹配、匹配导航
- **TextViewSearchRef**: `@MainActor final class`，管理 NSTextView 搜索高亮/选择/替换
- **FindReplaceBar**: SwiftUI View，浮动面板 UI

### 通信机制

- 菜单 → ViewModel：`Notification.Name`（.findInDocument, .findNext, .findPrevious, .findAndReplace）
- ViewModel → View：`@Observable` 状态绑定
- 搜索输入 → 搜索执行：`.onChange(of: findReplaceViewModel.searchText)`

## Bug 修复记录

### Bug 1：查找替换面板拉伸到全窗口高度

**原因**：FindReplaceBar 的 frame 使用了 `maxHeight: .infinity`
**修复**：移除 `maxHeight: .infinity`，让面板自然大小

### Bug 2：搜索输入框输入一个字母后焦点跳到文档

**原因**：SyntaxHighlightedEditor 的 first-responder 管理在 Raw 模式切换时无条件调用 `window.makeFirstResponder(textView)`，抢占了搜索输入框的焦点
**修复**：添加 `isFindBarVisible` 条件守卫——查找面板可见时不抢占焦点

```swift
// 修复前
if isActive, let window = textView.window, window.firstResponder !== textView {
    DispatchQueue.main.async { window.makeFirstResponder(textView) }
}

// 修复后
if isActive, !isFindBarVisible, let window = textView.window, window.firstResponder !== textView {
    DispatchQueue.main.async { window.makeFirstResponder(textView) }
}
```

参数传播链：DetailView → RawMarkdownView → SyntaxHighlightedEditor

### Bug 3：查找面板位置不对（偏下而非在顶部）

**原因**：FindReplaceBar 作为 ZStack 的普通子视图，ZStack 默认对齐 `.center` 导致面板居中
**修复**：从 ZStack 子视图改为 `.overlay(alignment: .topTrailing)`，锚定在文档区域右上角顶部

### Bug 4：搜索 'http' 对每个 'h' 字符高亮（而非完整匹配）

**原因**：MarkdownSyntaxHighlighter 的 `applyHighlights()` 使用 `setAttributes()` 重置全文本属性，清掉了搜索高亮的 `.backgroundColor`。之后虽然重新叠加搜索高亮，但 `textStorage.endEditing()` 触发 `textDidChange` → `reapplyHighlights` 再次执行，覆盖搜索高亮。

**修复**（两部分）：

1. `reapplySearchHighlights()` 使用 `beginEditing/endEditing` 包裹批量更新，防止每次 `addAttribute` 单独触发 `textDidChange`：

```swift
func reapplySearchHighlights(matchRanges: [NSRange], currentIndex: Int) {
    guard let textView = textView, let textStorage = textView.textStorage else { return }
    // ...
    textStorage.beginEditing()
    for (index, range) in matchRanges.enumerated() {
        let color: NSColor = index == currentIndex ? currentMatchColor : highlightColor
        textStorage.addAttribute(.backgroundColor, value: color, range: range)
    }
    textStorage.endEditing()
}
```

2. `reapplyHighlights()` 中的搜索高亮叠加改为 `DispatchQueue.main.async` 延迟一帧执行，确保语法高亮的 `endEditing` 已完全完成：

```swift
// 重新叠加搜索高亮
if let searchRef = parent.searchRef, !searchRef.allMatchRanges().isEmpty {
    DispatchQueue.main.async {
        searchRef.reapplySearchHighlights(
            matchRanges: searchRef.allMatchRanges(),
            currentIndex: searchRef.currentMatchIndex
        )
    }
}
```

## 协作问题记录

### 无关代码注入问题

开发过程中，opencode 持续添加与查找替换无关的代码：
- `ImageAttachmentLoader.swift` — 图片加载功能
- `MarkdownContentPreprocessor.swift` — Markdown 预处理
- `SupSubMarkupParser.swift` — 上标/下标渲染
- `RenderedMarkdownView.swift` 修改 — 添加上述功能的调用
- `SidebarView.swift` / `FileRowView.swift` 修改 — 布局微调

这些代码本身可能是合理的功能，但与查找替换无关，不应在此任务中混入。每轮 Claude 清理后，opencode 下一轮又重新添加，形成死循环，持续 30+ 轮直到用户手动干预。

**教训**：多 Agent 协作时，每个 Agent 应严格限定在自己的任务范围内，不要"顺手"添加其他功能。

## 构建状态

构建通过 ✅

## 待用户测试

用户需要测试以下场景：
1. Cmd+F 打开查找面板，Esc 关闭
2. 输入搜索文本，验证高亮和匹配计数
3. 搜索 'http' 等完整单词，确认不是逐字符高亮
4. 切换大小写敏感/全词匹配/正则搜索
5. 上/下导航匹配项
6. 展开替换行，替换当前/全部替换
7. Rendered 模式下的行号跳转
8. 切换主题后面板颜色跟随

测试通过后，执行：
```bash
git add -A
git commit -m "feat: 添加 VSCode 风格查找替换功能"
```
