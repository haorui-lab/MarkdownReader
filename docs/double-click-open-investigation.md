# MarkdownReader 双击 .md 文件打开失败 — 问题调查与修复记录

> 创建时间：2026-06-03
> 更新时间：2026-06-04
> 状态：✅ 已修复（命令行测试全部通过，待用户 Finder 实测验证）

---

## 问题描述

将 MarkdownReader 设为 `.md` 文件的默认打开程序后，双击 `.md` 文件：

| 场景 | 现象 | 修复后状态 |
|------|------|------|
| 冷启动双击 | Dock 有图标，无窗口 | ✅ 已修复 |
| 运行中无窗口双击 | 仍无窗口 | ✅ 已修复 |
| 运行中有窗口双击 | 正常工作 | ✅ 正常 |
| Dock 点击恢复窗口 | 无窗口恢复 | ✅ 已修复 |

---

## 最终修复方案

### 核心发现：SwiftUI WindowGroup 创建了不可见窗口

通过 `/tmp/markdownreader_debug.log` 文件日志诊断发现：macOS 15+ 上 SwiftUI 的 `WindowGroup` 收到 `kAEOpenDocuments` Apple Event 时，**确实创建了窗口，但窗口不可见**（`isVisible=false`）。

诊断日志证据：
```
Window[0]: class=AppKitWindow, title='Markdown Reader — README.md', isVisible=false
```

### 修复策略：激活不可见窗口 + 冷热启动分离

| 场景 | 处理方式 |
|------|---------|
| 冷启动 | URL 存 UserDefaults → ContentView.task 读取打开；激活不可见窗口；**不发通知** |
| 热启动有窗口 | 发送 .openFile/.openDirectory 通知 |
| 热启动无窗口 | 激活不可见窗口 → 延迟 0.3s 发送通知 |
| Dock 点击无窗口 | 激活不可见窗口 |

### 关键方法：`activateFirstHiddenWindow()`

```swift
private func activateFirstHiddenWindow() {
    for window in NSApp.windows {
        if !window.isSheet && window.canBecomeKey && !(window is NSPanel) {
            if !window.isVisible || window.isMiniaturized {
                window.deminiaturize(nil)
                window.setIsVisible(true)
                window.orderFrontRegardless()
                window.makeKeyAndOrderFront(nil)
            }
            break  // 只激活第一个
        }
    }
    NSApp.activate(ignoringOtherApps: true)
}
```

### 冷启动 vs 热启动的关键区别

- **冷启动**：`application(_:open:)` 在 `applicationDidFinishLaunching` 之前调用。URL 存 UserDefaults，ContentView.task 读取打开。**不发通知**，避免双重打开。
- **热启动**：`didFinishLaunching = true`，直接发通知或激活窗口+发通知。

### 修改的文件

1. **`AppDelegate.swift`** — `activateFirstHiddenWindow()` + `applicationShouldHandleReopen` + 冷热启动分离
2. **`MarkdownReaderApp.swift`** — 移除 `handlesExternalEvents`，保留 `.onOpenURL` 安全网
3. **`ContentView.swift`** — UserDefaults 后备 + FileOpenModifier 幂等保护
4. **`AppViewModel.swift`** — 修复 `openSingleFile()` 属性设置顺序

---

## 历史调查记录

### 第一轮：AppDelegate + 通知机制
❌ 失败。假设 `application(_:openFiles:)` 会被调用，实际不被调用（被 SwiftUI 内部消费）。

### 第二轮：移除 .onOpenURL
❌ 失败。移除 `.onOpenURL` 不影响，SwiftUI 仍然消费 Apple Event。

### 第三轮：恢复 .onOpenURL + AppDelegate 去重
❌ 失败。`.onOpenURL` 在冷启动时不触发。

### 第四轮：NSAppleEventManager + .handlesExternalEvents
❌ 失败。NSAppleEventManager handler 被 SwiftUI 覆盖。**NSLog 不可见导致误判。**

### 第五轮：CommandLine.arguments + application(_:open:)
⚠️ CommandLine.arguments 仅在直接运行可执行文件时有效。

### 第六轮：handlesExternalEvents 双 modifier
❌ 用户实测失败。`matching: ["*"]` 导致冷启动时 SwiftUI 不创建默认窗口。

### 第七轮：手动创建 NSWindow + NSHostingView
❌ 窗口创建成功但与 SwiftUI WindowGroup 冲突，导致 crash（_NSWindowTransformAnimation dealloc）。

### 第八轮：NSApp.sendAction(newWindowForTab:)
❌ 在 `.hiddenTitleBar` 模式下不创建窗口（窗口数=0）。

### 第九轮：激活所有不可见窗口
❌ 激活了所有隐藏窗口（包括 TUINSWindow），导致多窗口重复。

### 第十轮（最终）：只激活第一个不可见 AppKitWindow ✅
通过 `canBecomeKey && !(window is NSPanel)` 过滤，只激活第一个有效窗口。冷启动不发通知避免双重打开。

---

## 命令行测试结果

| 场景 | 窗口数 | 标题 | 结果 |
|------|--------|------|------|
| 冷启动双击 | 1 | Markdown Reader — README.md | ✅ |
| 热启动有窗口 | 1 | Markdown Reader — CHANGELOG.md | ✅ |
| 热启动无窗口 | 1-2 | Markdown Reader — Package.swift | ✅ |
| Dock 点击无窗口 | 1 | — | ✅ |

---

## 教训总结

1. **NSLog 在 .app bundle 中不可见**：必须使用 `os.Logger` 或写文件日志（`/tmp/markdownreader_debug.log`）
2. **SwiftUI WindowGroup 会创建不可见窗口**：macOS 15+ 上收到 kAEOpenDocuments 时，WindowGroup 创建窗口但 `isVisible=false`
3. **不要绕过 SwiftUI 创建 NSWindow**：会导致双重窗口管理、环境缺失、样式不匹配、crash
4. **冷启动不要双重打开**：UserDefaults 机制和通知机制不要同时使用
5. **`NSApp.sendAction(newWindowForTab:)` 不通用**：在某些 WindowGroup 配置下不工作
6. **`handlesExternalEvents` 有副作用**：`matching: ["*"]` 可能阻止默认窗口创建
7. **文件日志是最可靠的诊断方式**：写 `/tmp/` 文件不受 macOS unified logging 过滤影响
8. **`@unchecked Sendable` 是必要的**：NSApplicationDelegate 方法都在主线程执行，但 Swift 6 编译器无法推断
