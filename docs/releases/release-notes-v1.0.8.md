# Markdown Reader v1.0.8

修复 macOS .app 打包后 Bundle.module 无法找到依赖资源 bundle 导致启动崩溃的问题。

## 🔧 修复

### 📦 Bundle.module 资源路径修补
- SPM 生成的 `resource_bundle_accessor.swift` 使用 `Bundle.main.bundleURL` 查找资源 bundle，但 macOS .app 的资源位于 `Contents/Resources/`，导致运行时找不到 Textual 和 swiftui-math 的资源 bundle 而崩溃
- 修补为 `Bundle.main.resourceURL`，使路径正确解析到 `Contents/Resources/`
- 同时修复本地构建脚本 (`build-app.sh`) 和 CI 发布工作流 (`release.yml`)

## 🖥️ 系统要求

- macOS 15.0 (Sequoia) 或更高版本
- Apple Silicon / Intel 均支持

---

感谢使用 Markdown Reader！如有问题或建议，欢迎在 GitHub Issues 反馈。
