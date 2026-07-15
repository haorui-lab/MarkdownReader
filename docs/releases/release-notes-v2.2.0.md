# MarkdownReader v2.2.0 — 多窗口支持

## 概述

MarkdownReader 从单窗口架构升级为 Word 式多窗口。每个窗口拥有独立的文件、目录、编辑、查找、大纲、面板和 Undo 状态；应用级能力保持共享且只执行一次。

## 主要变更

### 多窗口架构

- **WindowSession**：每个窗口拥有独立的 AppViewModel、DocumentViewModel、FileTreeViewModel、CommandPaletteViewModel 和 WindowUndoStore
- **WindowCoordinator**：应用级协调器，管理窗口注册表、资源所有权和路由决策
- **WindowRoutingEngine**：纯逻辑路由引擎，决策顺序为 owner → preferred blank → any blank → create

### 资源所有权

- 同一 Markdown 文件只允许一个所有者窗口
- 再次打开同一文件时激活已有窗口，不创建重复实例
- 目录窗口点击已被另一窗口持有的文件时，目录窗口选择不变，激活所有者窗口，文件行显示「已在另一窗口打开」

### 窗口级命令路由

- 菜单命令经 FocusedValues 路由到焦点窗口，不广播
- 新增 `.openPanel` 命令，OpenPanel 改为窗口级 sheet
- 拖拽、PDF 导出、红绿灯操作均作用于所属窗口

### Undo 隔离

- 每窗口独立 WindowUndoStore，替代全局 UndoManagerProvider
- 通过 ObjC associated object 绑定到 NSWindow
- 删除全部 `nonisolated(unsafe)` 全局可变状态

### 统一打开路由

- 所有打开入口（Finder、Open Recent、OpenPanel、命令面板、拖拽、链接点击）经 `WindowCoordinator.enqueue(OpenRequest)` 统一路由
- 冷启动队列，external 请求优先于 restore

### 应用级服务

- WebViewWarmupService：幂等预热，首次调用创建 WebPage
- AppStartupCoordinator：幂等启动服务（预热 + 更新检查），启动优先级 external > restore > blank
- 只有最后活动窗口更新 lastOpenedFile/Directory

### 关闭与退出

- ApplicationTerminationCoordinator：串行处理脏 Untitled session
- applicationShouldTerminate 返回 .terminateLater
- Dock 重开：有注册窗口激活最后一个，无则创建空白窗口

## 已知限制

- 人工 GUI 回归测试待在非 headless 环境完成
- 完整窗口会话恢复不在本次范围
- 未保存确认 alert、`moveItem` 的 NSOpenPanel 仍为应用级 modal（多窗口下阻塞所有窗口），待后续改为窗口级 sheet

## 系统要求

- macOS 26.0+
- Apple Silicon (arm64)
