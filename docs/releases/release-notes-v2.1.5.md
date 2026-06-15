# Markdown Reader v2.1.5

新增 GitHub 风格 emoji shortcode 支持。

## ✨ 新增

### 😀 GitHub 风格 emoji shortcode 支持
- 新增 EmojiService，在 Markdown 渲染时将 `:emoji:` 短代码自动替换为 Unicode emoji 字符
- 包含 240+ emoji shortcode 映射，覆盖以下分类：
  - 笑脸与情感（:smile: :laughing: :heart_eyes: 等）
  - 手势与人物（:+1: :-1: :clap: :pray: 等）
  - 动物与自然（:dog: :cat: :unicorn: :dragon: 等）
  - 天气与天体（:sun: :moon: :rainbow: :fire: 等）
  - 食物与饮料（:coffee: :beer: :pizza: :cake: 等）
  - 运动与活动（:soccer: :basketball: :trophy: 等）
  - 旅行与地点（:car: :airplane: :rocket: 等）
  - 物品与符号（:bulb: :gift: :bomb: 等）
  - 符号与标志（:white_check_mark: :x: :100: 等）
- 支持 `:smile:` `:rocket:` `:+1:` `:-1:` 等常见 GitHub emoji 语法
- 正则使用 lookahead/lookbehind 避免误匹配时间格式（如 `10:30`）
- 在代码区域保护之后执行替换，确保代码块内不会误替换

## 🖥️ 系统要求

- macOS 26 (Tahoe) 或更高版本
- Apple Silicon 原生支持

---

感谢使用 Markdown Reader！如有问题或建议，欢迎在 GitHub Issues 反馈。
