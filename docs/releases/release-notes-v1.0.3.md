# Markdown Reader v1.0.3

新增自动更新功能，支持应用内检查更新、下载安装和一键重启。

## ✨ 新增

### 🔄 自动更新
- 启动时自动检查更新（延迟 2 秒，避免影响启动速度）
- 菜单栏「检查更新…」手动触发更新检查
- 更新弹窗显示版本号、Release Notes、下载进度
- 支持自动安装并重启（Sparkle 式体验）和手动安装两种模式
- 支持「跳过此版本」和「稍后提醒」

### 🌐 本地化
- 新增 18 个更新相关本地化键值（简中/繁中/英文）
- 新增复制路径本地化键值（简中/繁中/英文）

## 🔧 变更

- CI 发布流程新增 ZIP 打包，GitHub Release 同时上传 DMG 和 ZIP
- 发布说明文件移至 `docs/releases/` 目录

## 🖥️ 系统要求

- macOS 15.0 (Sequoia) 或更高版本
- Apple Silicon / Intel 均支持

---

感谢使用 Markdown Reader！如有问题或建议，欢迎在 GitHub Issues 反馈。
