# Markdown Reader v2.1.11

修复关闭窗口后无法重新打开文件/目录的问题。

## 🐛 修复

### 🔲 关闭窗口后无法重新打开文件/目录
修复窗口关闭后，通过「打开最近使用」菜单或 Dock 重新打开文件/目录时，文件加载到 ViewModel 但窗口不可见、内容不显示的问题。

- **根因**：关闭窗口时 SwiftUI 仅隐藏而非销毁窗口，ContentView 仍可接收 `.openFile`/`.openDirectory` 通知，但此时主窗口处于隐藏状态，加载结果用户看不到；且窗口关闭后 `selectedFileURL` 可能与旧值相同，仅靠 `onChange(of:)` 不会触发加载
- **修复**：
  - 新增 `ensureWindowVisible()`，处理 `.openFile`/`.openDirectory` 通知前先检查并激活隐藏的主窗口（`setIsVisible` + `makeKeyAndOrderFront` + `NSApp.activate`）
  - `openFile` 路径改为显式调用 `loadFile(at:)` 兜底加载，不再仅依赖 `selectedFileURL` 变化触发；`loadFile` 内部幂等判断避免重复加载

## 🖥️ 系统要求

- macOS 26 (Tahoe) 或更高版本
- Apple Silicon 原生支持

---

感谢使用 Markdown Reader！如有问题或建议，欢迎在 GitHub Issues 反馈。
