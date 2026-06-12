# Markdown Reader v2.1.2

修复行内 `$$` 数学公式渲染问题，官网帮助页更新。

## 🐛 修复

### 📐 行内 `$$` 公式渲染为 display 模式
- 修复行内 `$$...$$` 数学公式被错误渲染为块级 display 模式的问题
- `preprocessBlockMath` 正则改为仅匹配独占一行的 `$$...$$`（真正的块级公式）
- 新增 `preprocessInlineDoubleMath` 处理行内 `$$...$$`，正确渲染为 display 模式行内公式
- JS 渲染器读取 `data-display` 属性决定 KaTeX `displayMode` 参数

## 📝 变更

- 官网首页功能区新增命令面板卡片
- 官网帮助页和 i18n 添加命令面板内容
- 修复官网帮助页功能区 HTML 闭合标签错误

## 🖥️ 系统要求

- macOS 26 (Tahoe) 或更高版本
- Apple Silicon 原生支持

---

感谢使用 Markdown Reader！如有问题或建议，欢迎在 GitHub Issues 反馈。
