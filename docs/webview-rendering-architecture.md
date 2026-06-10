# WebView 渲染架构方案

> 本文档记录 MarkdownReader 从 Textual 原生渲染迁移到 WebView 渲染的技术方案，包括方案选型、性能分析、主题移植策略和迁移路径。

## 1. 背景与动机

当前 MarkdownReader 使用 Textual（gonzalezreal/textual）作为 Markdown 渲染引擎。Textual 是 SwiftUI 原生的文本渲染库，但在以下方面存在局限：

| 问题 | 严重程度 | 说明 |
|------|---------|------|
| 无 Mermaid 图表支持 | 🔴 高 | README 明确列为后续计划，Textual 架构无法实现 |
| 滚动同步不精确 | 🔴 高 | 当前使用 `lineNumber * avgLineHeight` 估算，长文档偏差大 |
| 跨段落文本选择失败 | 🟡 中 | SwiftUI Text 仅支持单 block 内选择 |
| GFM 渲染偏差 | 🟡 中 | Textual 使用 Foundation AttributedString 解析器，非完整 GFM 合规 |
| 大文档渲染延迟 | 🟡 中 | StructuredText 不支持懒加载，100KB+ 文件有明显延迟 |

## 2. 方案选型

### 2.1 候选方案对比

经过对 6 种方案的深度评估：

| 维度 | A: cmark-gfm+WebView | B: markdown-it+WebView | C: marked+WebView | D: remark/unified | E: 原生MarkdownView | 当前 Textual |
|------|----------------------|------------------------|-------------------|-------------------|---------------------|-------------|
| GFM 保真度 | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ |
| 解析速度 | ⭐⭐⭐⭐⭐ (<5ms) | ⭐⭐⭐⭐ (~10ms) | ⭐⭐⭐⭐⭐ (~5ms) | ⭐⭐ (~50ms) | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ |
| Mermaid 支持 | ✅ | ✅ | ⚠️ 需手动 | ⚠️ | ❌ | ❌ |
| LaTeX 支持 | ✅ KaTeX | ✅ KaTeX 插件 | ✅ 可选 | ✅ | ✅ 原生 | ⚠️ .math 扩展 |
| 滚动精度 | ⭐⭐⭐⭐⭐ sourcepos | ⭐⭐⭐ DOM 遍历 | ⭐⭐⭐ DOM 遍历 | ⭐⭐⭐ | ⭐⭐ 估算 | ⭐⭐ 估算 |
| 文本选择 | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐ 单 block | ⭐⭐ 单 block |
| 迁移成本 | **中** | 高 | 高 | 极高 | 高 | - |
| 内存 | ~80MB | ~80MB | ~80MB | ~80MB | ~10-20MB | ~10-20MB |

### 2.2 推荐方案：cmark-gfm 混合架构 + 原生 SwiftUI WebView

**核心思路**：解析在 Swift 侧，渲染在 WebView 侧。

```
Markdown 源码
      │
      ├──→ cmark-gfm (Swift/C) ──→ AST
      │       ├── OutlineService（100% 复用，从原始 Markdown 提取标题）
      │       └── HTML 输出（注入 heading id + data-line + data-sourcepos）
      │                              │
      │                              ▼
      └──→ WebPage (@Observable) ──→ WebView (SwiftUI 原生)
              ├── loadHTMLString(html, baseURL:)  ← 内容注入
              ├── callJavaScript()               ← JS 通信
              ├── webViewScrollPosition           ← 滚动同步
              ├── URLSchemeHandler                ← 本地资源加载
              └── findNavigator                   ← 查找功能
```

### 2.3 选型理由

1. **GFM 保真度最高** — cmark-gfm 是 GitHub 官方参考实现，表格、strikethrough、autolinks、task lists、footnotes 与 GitHub 渲染完全一致
2. **解析性能最优** — C 解析器 <5ms（小文件），<50ms（50KB 文件），比 JS 方案快 70 倍
3. **精确滚动同步** — `data-sourcepos` 属性提供源码-渲染双向映射，配合 `webViewScrollPosition` 实现像素级定位
4. **依赖最少** — swift-cmark 是 Textual 的传递依赖（swift-markdown → swift-cmark），无需新增外部依赖
5. **原生 SwiftUI WebView** — macOS 26 的 `WebView` + `WebPage` API 消除了 NSViewRepresentable 样板代码

### 2.4 不选择其他方案的原因

- **markdown-it / marked**：JS 解析不如 cmark-gfm 快且合规；无 sourcepos 精确滚动同步；XSS 需额外处理
- **remark/unified**：过度工程，包体大（>500KB），速度慢，配置复杂，不符合阅读器的简洁需求
- **原生 MarkdownView**（HumanInterfaceDesign）：不支持 Mermaid，这是硬伤

## 3. 部署目标：macOS 26+

### 3.1 原生 SwiftUI WebView API

WWDC25 发布了全新的 `WebView` + `WebPage` SwiftUI 原生 API：

| 能力 | API |
|------|-----|
| 显示网页内容 | `WebView(url:)` 或 `WebView(page)` |
| 加载/控制/通信 | `WebPage`（`@Observable` 类） |
| 加载 HTML | `page.load(html:baseURL:)` |
| JS 通信 | `page.callJavaScript()` |
| 自定义 URL Scheme | `URLSchemeHandler` 协议 |
| 滚动同步 | `webViewScrollPosition` 修饰符 + `onScrollGeometryChange` |
| 查找 | `findNavigator` 修饰符 |
| 导航控制 | `WebPage.NavigationDeciding` 协议 |
| 导航事件监听 | `currentNavigationEvent`（Observable） |

### 3.2 与 NSViewRepresentable 方案的对比

| 维度 | NSViewRepresentable + WKWebView | 原生 SwiftUI WebView |
|------|------|------|
| WebView 包装 | ~150 行样板代码 | 0 行（SwiftUI 原生） |
| JS 通信 | `evaluateJavaScript` + `WKScriptMessageHandler` | `page.callJavaScript()` + 闭包 |
| 滚动同步 | 自研 IntersectionObserver | `webViewScrollPosition` 修饰符 |
| 生命周期 | 手动 Coordinator | SwiftUI 自动管理 |
| ViewModel 集成 | 需桥接 | `WebPage` 是 `@Observable`，直接绑定 |

### 3.3 选择 macOS 26+ 的理由

- MarkdownReader 目标用户是开发者，macOS 升级率高
- 消除 NSViewRepresentable 样板代码的开发和维护成本远大于少量用户损失
- `WebPage` 的 `@Observable` 集成与项目现有 ViewModel 模式完美对齐
- `webViewScrollPosition` 是 Apple 官方滚动同步方案，比自研方案更可靠

## 4. 性能分析

### 4.1 与 Textual 的性能对比

| 场景 | Textual | WebView | 差异 |
|------|---------|---------|------|
| 1KB 小文件首次渲染 | ~5ms | ~20ms（热）/ ~120ms（冷） | 无感（热）/ 可优化（冷） |
| 50KB 中文件 | ~50ms | ~25ms | WebView 快 25ms |
| 200KB 大文件 | ~300ms+ | ~40ms | WebView 快 260ms+ |
| 1MB+ 巨文件 | ~2s+ | ~80ms | WebView 快 1.9s+（碾压） |

### 4.2 小文件性能优化：WebView 预热

App 启动时创建一个隐藏的 WebPage，预加载 HTML 模板 + highlight.js。切换文件时只需调用 `callJavaScript('replaceContent(html)')`，跳过冷启动。

**预期效果**：小文件首次渲染从 ~120ms 降至 ~15-20ms，在人类感知阈值（~50ms）以内。

### 4.3 结论

**小文件输在毫秒级（无感），大文件赢在秒级（显著），功能全面胜出。** 完全迁移 WebView，不需要双引擎。

## 5. 迁移成本评估

### 5.1 受影响文件分析

| 文件 | 行数 | Textual 耦合度 | 可复用比例 | 替换量 | 复杂度 |
|------|------|---------------|-----------|--------|--------|
| RenderedMarkdownView.swift | 231 | 深度 | ~10% | 全部 body + 滚动基础设施 | 高 |
| SupSubMarkupParser.swift | 317 | 完全 | ~5% | 整个文件 → cmark-gfm HTML 生成器 | 高 |
| ThemeColors.swift | 195 | 1 处 | **~60%** | highlighterTheme → CSS 变量映射 | 中 |
| DetailView.swift | 495 | 1 行 | **~98%** | 删除 .textual 修饰符 | 低 |
| OutlineService.swift | 84 | 无 | **100%** | 不变 | 无 |
| MarkdownSyntaxHighlighter.swift | 729 | 独立 | **100%** | 保留（Raw 模式仍在用） | 无 |

**净效果**：SupSubMarkupParser 的 317 行 Textual 绑定代码 → ~100 行 cmark-gfm HTML 生成器 + ~50 行 URLSchemeHandler。代码量减少。

### 5.2 渐进迁移路径

| 阶段 | 内容 | 风险 |
|------|------|------|
| Phase 0 | 将最低部署目标提升到 macOS 26 | 低 |
| Phase 1 | 新建 `WebPage` + `WebView`，加载 cmark-gfm 生成的 HTML | 低 |
| Phase 2 | 迁移主题系统（CSS 变量映射） | 中 |
| Phase 3 | 滚动同步（`webViewScrollPosition` + JS heading 定位） | 低 |
| Phase 4 | 集成 Mermaid + KaTeX | 低 |
| Phase 5 | 移除 Textual 依赖 | 低 |

## 6. 关键技术实现方案

### 6.1 Heading ID + data-line 注入

cmark-gfm 默认输出 `<h1>Title</h1>` 无 id 属性。解法：

- **推荐：后处理注入** — 遍历 AST 获取标题列表，用正则在 HTML 中匹配并注入 `id="heading-1"` 和 `data-line="42"`
- **更优：自定义 MarkupVisitor** — 用 swift-markdown 的 `MarkupVisitor` 协议自定义 HTML 渲染，完全控制输出

### 6.2 主题桥接：ThemeColors → CSS Custom Properties

```css
:root {
  --surface: #18181a;
  --ink: #e8e8e3;
  --accent: #339cff;
  --success: #40c977;
  --danger: #fa423e;
  --bg-elevated: #1f1f22;
  --bg-subtle: #1a1a1c;
  --bg-muted: #1c1c1f;
  --fg-secondary: rgba(232, 232, 227, 0.75);
  --fg-muted: rgba(232, 232, 227, 0.55);
  --accent-hover: #4db0ff;
  --accent-soft: rgba(51, 156, 255, 0.20);
  --border: rgba(232, 232, 227, 0.06);
  --border-subtle: rgba(232, 232, 227, 0.04);
}
```

现有 5 色 + 12 个派生 token → CSS 变量一对一映射，**60% 主题代码直接复用**。

### 6.3 滚动同步双向方案

- **大纲→渲染**：JS `document.getElementById('heading-N').scrollIntoView()` — 精确到像素
- **渲染→大纲**：`webViewScrollPosition` 修饰符（macOS 26 原生）或 `IntersectionObserver` + `callJavaScript()` 回调 → 高亮对应大纲项
- **源码→渲染**：`data-line` 属性 + JS 二分查找最近 heading

### 6.4 增量更新（不丢滚动位置）

```javascript
function replaceContent(html) {
  document.getElementById('content').innerHTML = html;
  Prism.highlightAll();  // 仅重新高亮代码块
}
```

仅在切换文件（baseURL 变化）时才做完整页面重载。

## 7. MPE 主题移植

### 7.1 来源

MPE（vscode-markdown-preview-enhanced）的主题系统来自 **crossnote** npm 包（版本 0.9.30）。crossnote 构建时将 LESS 编译为 CSS，发布到 npm 的是**已编译的 CSS 文件**，无需 lessc 编译步骤。

### 7.2 可移植主题清单

**预览主题（16 个）：**

| 主题 | 风格 |
|------|------|
| github-light | GitHub 风格（默认） |
| github-dark | GitHub Dark |
| one-dark | Atom One Dark |
| one-light | Atom One Light |
| atom-dark | Atom Dark |
| atom-light | Atom Light |
| atom-material | Atom Material |
| monokai | Monokai |
| solarized-dark | Solarized Dark |
| solarized-light | Solarized Light |
| night | Typora 风格 |
| medium | Medium 风格 |
| gothic | Gothic 风格 |
| newsprint | 新闻纸风格 |
| vue | Docsify Vue 风格 |
| none | 无样式 |

**代码高亮主题（24 个）：** 标准 Prism.js 主题（okaidia、darcula、twilight、one-dark、one-light 等），直接可用。

### 7.3 移植流程

```
1. 从 crossnote npm 包提取已编译的预览主题 CSS
   → 16 个 .css 文件，直接可用

2. 从 Prism.js 提取代码高亮主题 CSS
   → 24 个 .css 文件，直接可用

3. 选择器适配：MPE 用 .markdown-preview 包裹
   → WKWebView 中加 <div class="markdown-preview"> 即可

4. 主题切换逻辑：JS 动态替换 <link> 标签
```

### 7.4 双模式主题策略

两种主题模式并存，用户可自由选择：

| 模式 | 说明 | 主题数量 |
|------|------|---------|
| **MPE 预设主题** | 直接用 crossnote 编译好的 CSS，零修改，即开即用 | 16 预览 × 24 高亮 = 384 组合 |
| **MarkdownReader 自定义** | 保留现有 ThemeDefinition 5 色系统，生成 CSS 变量注入 WebView | 无限（5 色自由组合 + 对比度调节） |

### 7.5 许可证

MPE 使用 NCSA 许可证（类 MIT），保留版权声明即可合规使用。

## 8. 必须接受的代价

| 代价 | 影响 | 评估 |
|------|------|------|
| 内存增加 ~60MB | 阅读器通常单窗口 | 可接受 |
| 沙盒需增加 Outgoing Connections | App Store 审核无影响 | 可接受 |
| VoiceOver 支持 | WebKit DOM→AX 桥接 | 对阅读器够用，语义 HTML 标题导航甚至更好 |
| 首次渲染延迟 | WKWebView 冷启动 ~100ms | 用 WebView 预热策略缓解至 ~15-20ms |
| 最低部署目标提升到 macOS 26 | 排除旧系统用户 | 目标用户为开发者，升级率高 |

## 9. 参考项目

| 项目 | 技术方案 | 参考价值 |
|------|---------|---------|
| [MarkView](https://github.com/paulhkang94/markview) | cmark-gfm + WKWebView + Prism.js | 最完整的参考实现，含滚动同步、Mermaid、lint |
| [keitaoouchi/MarkdownView](https://github.com/keitaoouchi/MarkdownView) | markdown-it + WKWebView | 最成熟的 Swift WKWebView Markdown 库 |
| [HumanInterfaceDesign/MarkdownView](https://github.com/HumanInterfaceDesign/MarkdownView) | swift-cmark + tree-sitter 原生渲染 | 最优原生方案，但不支持 Mermaid |
| [WKMarkdownView](https://github.com/weihas/WKMarkdownView) | marked.js + WKWebView + KaTeX | 最轻量 WKWebView Markdown 组件 |
| [crossnote](https://github.com/shd101wyy/crossnote) | markdown-it + 主题系统 | MPE 主题的来源，已编译 CSS 直接可用 |
