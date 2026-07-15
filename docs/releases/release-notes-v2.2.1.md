# Markdown Reader v2.2.1

修复多窗口场景下 Cmd+N 后目录内文件切换失效与编辑器残留内容反写的问题。

## 🐛 修复

### Cmd+N 后目录内文件切换失效与编辑器残留内容反写
修复多窗口改造后三处系统性回归根因，统一文件切换事务到 `WindowSession`。

- **根因1**：Cmd+N 创建 Untitled 后未释放此前真实文件的所有权，导致窗口同时持有旧文件 + Untitled，再次选择该文件被误判为幂等、无反应
  - 修复：`createNewUntitled` 现记录并释放 `previousRealFileURL` 所有权，保留根目录所有权
- **根因2**：`requestFileSelection` 幂等判断仅检查「本窗口持有」，无法处理残留所有权
  - 修复：同时校验持有 + `currentFileURL` + `selectedFileURL` 三者一致；持有但非当前文档时强制重新声明所有权以自愈
- **根因3**：`SyntaxHighlightedEditor.updateNSView` 在文件身份变化时未阻止 first responder 把上一个文件内容反写回 ViewModel
  - 修复：新增 `EditorSyncPolicy` 纯逻辑，将 `contentVersion` 与 `fileDidChange` 一并视为强制覆盖条件
- **弹窗竞态**：脏 Untitled 保存确认从视图层移至 `openFileInDirectoryWindow`，决策通过前不改 `selectedFileURL`，消除双重加载与弹窗竞态；删除 `ContentView.handleFileSwitchWithUnsavedChanges`，视图层仅响应已确认的选中项变化
- **程序化清空**：`DocumentViewModel` 在 `createUntitledFile` / `discardUntitledFile` / `clearSelection` 等处递增 `contentVersion`，强制编辑器采用空内容

## ✅ 测试

- 新增 `SyntaxHighlightedEditorSyncTests` 覆盖编辑器同步策略
- 扩展 `DirectoryWindowNavigationTests` 与 `NewFileAndSaveFlowTests`，覆盖 Cmd+N 释放所有权、干净/脏 Untitled 往返切换、保存取消/失败等回归路径
- 全部 129 个测试通过

## 🖥️ 系统要求

- macOS 26 (Tahoe) 或更高版本
- Apple Silicon 原生支持

---

感谢使用 Markdown Reader！如有问题或建议，欢迎在 GitHub Issues 反馈。
