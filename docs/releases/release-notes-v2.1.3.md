# Markdown Reader v2.1.3

修复保存操作重入问题，完善另存为面板行为。

## 🐛 修复

### 💾 保存操作重入问题
- 修复快捷键 Cmd+S 可能重复触发保存操作的问题
- 新增 `isSaving` 状态检查，保存中时不再重复执行保存
- 新增 `isSavePanelShowing` 状态检查，保存面板显示时不再重复触发

### 📂 另存为面板重复弹窗
- 修复新建文件首次保存时可能重复弹出另存为面板的问题
- 新增面板显示状态保护，确保同时只弹出一个保存面板

### 📄 另存为文件类型
- 另存为面板新增 `allowsOtherFileTypes`，允许保存为非 `.md` 扩展名的文件

## 🖥️ 系统要求

- macOS 26 (Tahoe) 或更高版本
- Apple Silicon 原生支持

---

感谢使用 Markdown Reader！如有问题或建议，欢迎在 GitHub Issues 反馈。
