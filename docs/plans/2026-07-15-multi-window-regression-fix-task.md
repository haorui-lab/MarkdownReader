# 多窗口回归问题修复任务说明

## 任务背景

MarkdownReader 完成多窗口改造后，窗口级命令路由和目录内文件导航出现系统性回归，当前已确认的用户可见问题包括：

1. 打开按钮、`File > Open` 和 `Cmd+O` 无响应；
2. `Cmd+P` 无响应；
3. 导出 PDF 无响应；
4. 目录窗口点击尚未打开的 Markdown 文件时错误创建新窗口，而不是在当前目录窗口打开；
5. 新建文件按钮、菜单和 `Cmd+N` 无响应。

审计表明，这些问题不是相互独立的功能缺陷，而是多窗口命令分发、资源所有权和窗口生命周期迁移不完整造成的同源回归。修复时不得逐项恢复全局 `NotificationCenter` 广播，也不得仅增加 `isKeyWindow` 判断规避问题。

## 权威输入

实施时必须以以下文档为准：

- 产品行为：`docs/multi-window-requirements.md`
- 技术架构：`docs/plans/2026-07-14-multi-window-design.md`
- 原始实施计划：`docs/plans/2026-07-14-multi-window-implementation-plan.md`

若本文与上述文档发生冲突，以产品需求和技术设计为优先；本文负责限定本次回归修复范围。

## 已确认根因

### 1. FocusedValues 使用方式错误

`MarkdownReaderCommands`、`SidebarView`、`WelcomeView`、`DetailView` 等位置在按钮回调或普通方法内部临时声明 `@FocusedValue`。这些临时 property wrapper 无法稳定获得 SwiftUI 焦点环境，导致 `WindowCommandTarget` 通常为 `nil`，命令静默成为 no-op。

`DetailView` 和 `WebViewMarkdownView` 还会再次发布同一个 `focusedSceneValue`，存在用无 session 的临时 target 覆盖 `WindowSceneHost` 正确 target 的风险。

### 2. 目录内导航错误复用外部打开规则

目录树点击调用了通用 `WindowRoutingEngine`。该引擎只允许空白窗口复用，因此已承载根目录的窗口点击无 owner 文件时会得到 `.createWindow`，与“目录内文件始终在当前目录窗口切换”的产品规则冲突。

### 3. 新建和保存流程迁移不完整

- 脏 Untitled 状态下执行新建文件会直接返回，没有进入“保存 / 不保存 / 取消”流程；
- Untitled 执行保存时，`DocumentViewModel.save()` 只返回失败结果，上层没有继续进入 Save As；
- 菜单、快捷键和窗口按钮尚未统一到一个完整的窗口级操作入口。

## 修复范围

### 一、重建窗口级命令路由

1. `MarkdownReaderCommands` 在 `Commands` 结构体级声明并读取 `@FocusedValue(\.windowCommandTarget)`，禁止在按钮 closure 内临时创建。
2. `WindowSceneHost` 作为 `windowCommandTarget` 的唯一 scene 级发布点。
3. Sidebar、Welcome、TitleBar、文件右键菜单等本窗口内控件直接调用明确的 `WindowSession`、ViewModel 或注入 action，不通过 FocusedValues 反向查找所属窗口。
4. `DetailView` 和 `WebViewMarkdownView` 显式接收本 session 的 `WindowCommandTarget`，注册 PDF、查找、重新加载、缩放等 handler；视图退出或能力不可用时清理 handler，避免残留回调指向旧视图。
5. 当没有焦点窗口或命令在当前状态不可用时，菜单项应禁用，不允许静默点击无响应。
6. 一并恢复和验证所有使用相同通道的命令：
   - New File、Open、Save、Save As、Export PDF；
   - Command Palette；
   - Sidebar、Settings、显示模式切换；
   - Find、Find Next、Find Previous、Find and Replace；
   - Reload、Zoom In、Zoom Out、Zoom Reset。

### 二、实现目录窗口专用文件切换事务

目录树和命令面板选择当前根目录内文件时，不得进入通用外部打开路由。统一执行以下规则：

1. 目标文件由其他窗口持有：
   - 保持当前目录窗口的选中项和文档不变；
   - 激活并前置 owner 窗口。
2. 目标文件无其他 owner：
   - 继续在当前目录窗口打开；
   - 为当前 session 声明目标文件所有权；
   - 释放此前在该目录窗口显示的文件所有权，但保留根目录所有权；
   - 更新文件树选择并加载文档。
3. 当前窗口已经持有目标文件：保持幂等，不重复加载或创建窗口。
4. 所有权声明、旧文件释放和选中项切换必须作为同一主线程事务完成；失败时不得留下错误 owner 或错误选中状态。
5. 命令面板选择目录内文件、键盘 Return 打开文件和 Markdown 页面内链应复用同一套窗口内导航规则。

### 三、修复新建、保存和导出流程

1. 所有 New File 入口统一调用同一个 `WindowSession` 操作。
2. 当前存在脏 Untitled 时，新建文件必须显示“保存 / 不保存 / 取消”：
   - 保存成功后创建新 Untitled；
   - 不保存时完整清理旧 Untitled 后创建新 Untitled；
   - 取消或保存失败时保持当前内容和窗口不变。
3. `Cmd+S` 保存 Untitled 时必须进入本窗口的 Save As 流程。
4. Save、Save As 和 Export PDF 面板必须附着到发起操作的 `session.window`，改为窗口级异步 sheet，不再使用应用级 `runModal()`。
5. 增加或恢复明确的 Save As 菜单入口，并验证所有权迁移、窗口标题、最近记录和文件树刷新。
6. 导出 PDF 必须同时验证菜单快捷键和标题栏按钮；导出期间不得抢夺或错误恢复其他窗口焦点。

### 四、修复审计发现的多窗口连带问题

1. 移除 Markdown 内链的全局 `.openLinkedMarkdownFile` 广播，改为 WebView 通过 closure 回传所属 session，再按目录内导航或外部打开规则处理。
2. 全屏进入/退出通知必须按所属 `NSWindow` 过滤，不得修改其他 session 的 `isFullScreen`。
3. `NSWindow.didBecomeKeyNotification` 必须更新 `WindowCoordinator` 的 MRU 和 `lastActiveWindowID`，保证最近位置记录、Dock 重开和窗口关闭回退正确。
4. 手动更新检查记录发起 session，更新 sheet 只附着到一个目标窗口；目标窗口关闭时回退到当前活动窗口。
5. 实现需求中遗漏的 `File > New Window` 与 `Cmd+Shift+N`。
6. 补全标准 Window 菜单：列出主窗口、激活目标窗口，并保留 Minimize、Zoom、Bring All to Front。
7. 清理已经失去调用方的窗口级 `Notification.Name` 和过时注释，避免后续代码误用旧广播通道。

## 主要涉及文件

- `Sources/MarkdownReader/App/MarkdownReaderApp.swift`
- `Sources/MarkdownReader/App/MarkdownReaderCommands.swift`
- `Sources/MarkdownReader/ViewModels/WindowSession.swift`
- `Sources/MarkdownReader/ViewModels/WindowCommandTarget.swift`
- `Sources/MarkdownReader/ViewModels/DocumentViewModel.swift`
- `Sources/MarkdownReader/ViewModels/FileTreeViewModel.swift`
- `Sources/MarkdownReader/ViewModels/CommandPaletteViewModel.swift`
- `Sources/MarkdownReader/Services/WindowCoordinator.swift`
- `Sources/MarkdownReader/Services/WindowRoutingEngine.swift`
- `Sources/MarkdownReader/Services/OpenPanelHelper.swift`
- `Sources/MarkdownReader/Views/WindowSceneHost.swift`
- `Sources/MarkdownReader/Views/WindowLifecycleBridge.swift`
- `Sources/MarkdownReader/Views/ContentView.swift`
- `Sources/MarkdownReader/Views/SidebarView.swift`
- `Sources/MarkdownReader/Views/WelcomeView.swift`
- `Sources/MarkdownReader/Views/DetailView.swift`
- `Sources/MarkdownReader/Views/WebViewMarkdownView.swift`
- `Sources/MarkdownReaderKit/Services/LocalizationService.swift`
- `Tests/MarkdownReaderTests/`

具体修改范围应以失败测试和实际依赖为准，不得为本任务顺带重构无关模块。

## 测试要求

本任务必须采用测试先行方式。现有测试只验证了 `WindowCommandTarget.perform()` 等纯逻辑，未覆盖真实焦点环境和真实目录窗口状态，需要补充以下回归测试：

1. 命令分发：焦点窗口 A 执行命令只影响 A，窗口 B 不响应；无焦点 target 时菜单禁用。
2. 真实目录窗口：设置 `rootDirectory` 后点击无 owner 文件，断言在当前窗口打开且没有创建新窗口。
3. 所有权冲突：目标文件已在其他窗口打开时，当前目录窗口选择和文档不变，owner 被激活。
4. 所有权切换：目录窗口 A.md → B.md 后，B.md 归当前窗口，A.md 可被其他窗口重新打开。
5. 外部去重：目录窗口当前显示 A.md 时，从 Finder、Open Recent 或 OpenPanel 再次打开 A.md，只激活原窗口。
6. Untitled 保存：`Cmd+S` 进入 Save As；取消或写入失败保留原内容。
7. Untitled 新建：覆盖保存、不保存、取消三条分支。
8. PDF、查找、缩放、重新加载和显示模式切换均只作用于焦点窗口。
9. Markdown 内链只由来源窗口处理。
10. 窗口 A 全屏不改变窗口 B 状态。
11. 用户点击切换 key window 后，MRU、最后位置和关闭回退顺序正确。
12. `Cmd+Shift+N` 可连续创建至少 5 个空白窗口，Window 菜单可逐一激活。

如果 SwiftUI `Commands` 的焦点读取无法用普通 XCTest 可靠覆盖，应增加最小 UI harness 或 UI 测试；不得继续仅用直接调用 `target.perform()` 代替命令入口测试。

## 验收标准

- 打开按钮、菜单和 `Cmd+O` 均可用，面板附着到当前窗口；
- `Cmd+P` 可打开当前窗口的命令面板；
- 菜单和标题栏均可导出当前窗口文档的 PDF；
- 目录窗口点击未打开文件时在当前窗口切换，不创建新窗口；
- 点击已由其他窗口持有的文件时激活 owner，当前目录窗口状态不变；
- 新建文件按钮、菜单和 `Cmd+N` 均可用，脏 Untitled 不会丢失；
- `Cmd+S` 能保存普通文件，并能为 Untitled 打开本窗口 Save As；
- 保存、查找、缩放、显示模式、设置、Sidebar、重新加载和 PDF 均无跨窗口串扰；
- Markdown 内链、全屏状态、更新弹窗和最近活动窗口记录均按所属窗口工作；
- `Cmd+Shift+N` 和 Window 菜单满足多窗口需求；
- `swift build` 成功；
- `swift test` 全部通过；
- 完成双窗口、多目录窗口、最小化、全屏、关闭最后窗口后重开等人工回归矩阵；
- 不再存在按钮点击后因 target 为 `nil` 而静默 no-op 的路径。

## 不包含

- 同一文件同时在多个窗口编辑；
- 标签页、分屏或 Excel 式同文档多视图；
- 恢复上次退出时的完整窗口集合；
- 重做 Markdown 渲染、编辑器或主题系统；
- 与本次多窗口回归无关的 UI 改版或大规模重构。

## 交付物

1. 根因级代码修复；
2. 新增和修正的自动化回归测试；
3. 多窗口人工验证记录；
4. 必要的 `docs/multi-window-requirements.md`、设计文档和 `CHANGELOG.md` 状态更新。
