# Markdown Reader v2.1.4

修复保存后内容回退和文件监控误触发刷新的问题。

## 🐛 修复

### ↩️ 保存后内容回退
- 修复保存操作后编辑器内容被旧值覆盖的问题
- 当 NSTextView 为第一响应者时，以编辑器内容为准同步回 SwiftUI binding
- 防止 `isDirty` 变化触发 SwiftUI 重渲染，用旧 content 值覆盖编辑器当前内容

### 🔄 保存后文件监控误触发刷新
- 修复保存后 FSEventStream 延迟回调可能误判为外部修改的问题
- 当磁盘内容与内存一致时仅同步快照，避免不必要的文件刷新
- 覆盖保存后 isSaving 已重置但快照已更新的场景

### 🧹 清理
- 删除误提交的 Untitled.md 测试文件

## 🖥️ 系统要求

- macOS 26 (Tahoe) 或更高版本
- Apple Silicon 原生支持

---

感谢使用 Markdown Reader！如有问题或建议，欢迎在 GitHub Issues 反馈。
