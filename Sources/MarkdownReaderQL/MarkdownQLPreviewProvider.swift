import AppKit
import os.log
import QuickLookUI
import MarkdownReaderKit
import WebKit

private let logger = Logger(subsystem: "com.markdownreader.app.QuickLook", category: "PreviewProvider")

@MainActor
final class MarkdownQLPreviewProvider: NSViewController, QLPreviewingController {
    private var webView: WKWebView!
    private var navigationDelegate: QLNavigationDelegate?

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    nonisolated func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping @Sendable (Error?) -> Void) {
        let keyExists = UnsafeMutablePointer<DarwinBoolean>.allocate(capacity: 1)
        defer { keyExists.deallocate() }
        let enabled = CFPreferencesGetAppBooleanValue(
            "com.markdownreader.enableQuickLookPreview" as CFString,
            "com.markdownreader.app" as CFString,
            keyExists
        )
        let isEnabled = keyExists.pointee.boolValue ? enabled : true

        guard isEnabled else {
            handler(NSError(domain: "com.markdownreader.app.QuickLook", code: 1, userInfo: [NSLocalizedDescriptionKey: "Quick Look preview is disabled"]))
            return
        }

        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                content = try String(contentsOf: url, encoding: .utf8)
            } catch {
                logger.error("Failed to read file: \(error)")
                handler(error)
                return
            }
        }

        logger.info("File loaded, length: \(content.count)")

        let isDark = detectDarkMode()
        let theme = PresetThemes.defaultTheme(for: isDark ? .dark : .light)
        let themeColors = ThemeColors.from(theme)
        let (inlineCSS, inlineJS) = loadInlineResources()

        logger.info("Inline CSS length: \(inlineCSS.count), JS length: \(inlineJS.count)")

        let finalCSS = inlineCSS.isEmpty ? Self.fallbackCSS : inlineCSS

        // 注意：baseURL 传 nil 而非 url，因为 render() 会将相对路径转为 mr:/// URL，
        // 而 QL 扩展的 WKWebView 没有注册 mr:// scheme handler，导致资源加载失败。
        // 传 nil 后相对路径保持原样，由 WKWebView 的 baseURL（loadHTMLString 设置）解析。
        let html = MarkdownHTMLService.buildPreviewHTML(
            content: content,
            themeCSS: themeColors.cssCustomProperties + themeColors.codeHighlightCSS,
            inlineCSS: finalCSS,
            inlineJS: inlineJS,
            contentPadding: 20,
            baseURL: nil,
            isDark: isDark
        )

        logger.info("HTML generated, length: \(html.count)")

        let baseURL = url.deletingLastPathComponent()

        let weakSelf = self
        DispatchQueue.main.async {
            guard let webView = weakSelf.webView else {
                logger.error("webView is nil — viewDidLoad not called yet")
                handler(NSError(domain: "com.markdownreader.app.QuickLook", code: 2, userInfo: [NSLocalizedDescriptionKey: "WebView not initialized"]))
                return
            }

            // 重入保护：如果上一次预览的 handler 还未被调用，先强制完成
            weakSelf.navigationDelegate?.forceCompleteIfPending()

            let navDelegate = QLNavigationDelegate { error in
                handler(error)
            }
            weakSelf.navigationDelegate = navDelegate
            webView.navigationDelegate = navDelegate

            // 设置背景色匹配主题，避免白屏闪烁
            if isDark {
                webView.underPageBackgroundColor = NSColor(red: 0.094, green: 0.094, blue: 0.102, alpha: 1.0)
            }

            webView.loadHTMLString(html, baseURL: baseURL)

            // 保障：如果 2 秒内 didFinish 未触发（例如 CSS 字体子请求阻止了完成事件），
            // 仍然调用 handler 让 Quick Look 显示已有内容
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                navDelegate.forceCompleteIfPending()
            }
        }
    }

    nonisolated private static let fallbackCSS = """
    body {
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
        max-width: 980px;
        margin: 0 auto;
        padding: 20px;
        line-height: 1.6;
        color: #24292e;
    }
    h1, h2, h3, h4, h5, h6 { margin-top: 24px; margin-bottom: 16px; font-weight: 600; line-height: 1.25; }
    h1 { font-size: 2em; border-bottom: 1px solid #eaecef; padding-bottom: 0.3em; }
    h2 { font-size: 1.5em; border-bottom: 1px solid #eaecef; padding-bottom: 0.3em; }
    code { background: rgba(27,31,35,.05); border-radius: 3px; font-size: 85%; padding: 0.2em 0.4em; }
    pre { background: #f6f8fa; border-radius: 6px; padding: 16px; overflow: auto; }
    pre code { background: none; padding: 0; font-size: 100%; }
    blockquote { border-left: 4px solid #dfe2e5; padding: 0 1em; color: #6a737d; margin: 0; }
    table { border-collapse: collapse; width: 100%; }
    th, td { border: 1px solid #dfe2e5; padding: 6px 13px; }
    img { max-width: 100%; }
    a { color: #0366d6; text-decoration: none; }
    """
}

private final class QLNavigationDelegate: NSObject, WKNavigationDelegate, @unchecked Sendable {
    private let completionHandler: @Sendable (Error?) -> Void
    private var handled = false

    init(completionHandler: @escaping @Sendable (Error?) -> Void) {
        self.completionHandler = completionHandler
    }

    func forceCompleteIfPending() {
        guard !handled else { return }
        handled = true
        logger.info("Navigation delegate timeout — forcing handler completion")
        completionHandler(nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !handled else { return }
        handled = true
        logger.info("WebView didFinish navigation")
        completionHandler(nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard !handled else { return }
        handled = true
        logger.error("WebView didFail: \(error)")
        completionHandler(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard !handled else { return }
        handled = true
        logger.error("WebView didFailProvisionalNavigation: \(error)")
        completionHandler(error)
    }
}

private func detectDarkMode() -> Bool {
    if Thread.isMainThread {
        return NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    } else {
        return UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }
}

private func loadInlineResources() -> (css: String, js: String) {
    let resourceURL = resolveResourceURL()

    logger.info("resolveResourceURL: \(resourceURL?.path ?? "nil")")
    logger.info("Bundle.main.bundleURL: \(Bundle.main.bundleURL.path)")
    logger.info("Bundle.main.resourceURL: \(Bundle.main.resourceURL?.path ?? "nil")")

    var css = ""
    var js = ""

    for name in ["markdown.css", "scroll.css", "katex.min.css"] {
        if let url = resourceURL?.appendingPathComponent("css/\(name)"),
           let data = try? Data(contentsOf: url),
           let content = String(data: data, encoding: .utf8) {
            css += content + "\n"
        } else {
            logger.warning("Failed to load CSS: \(name)")
        }
    }

    let jsFiles = ["mermaid.min.js", "katex.min.js", "prism-core.min.js", "prism-autoloader.min.js", "markdown-reader.js"]
    for name in jsFiles {
        if let url = resourceURL?.appendingPathComponent("js/\(name)"),
           let data = try? Data(contentsOf: url),
           let content = String(data: data, encoding: .utf8) {
            js += (name == "markdown-reader.js") ? (content + "\n") : (content + ";\n")
        } else {
            logger.warning("Failed to load JS: \(name)")
        }
    }

    return (css: css, js: js)
}

private func resolveResourceURL() -> URL? {
    let searchPaths: [URL] = [
        // .appex/Contents/Resources/MarkdownReader_MarkdownReader.bundle/Resources/
        Bundle.main.resourceURL?.appendingPathComponent("MarkdownReader_MarkdownReader.bundle").appendingPathComponent("Resources"),
        // .appex/Contents/Resources/MarkdownReader_MarkdownReader.bundle/Contents/Resources/
        Bundle.main.resourceURL?.appendingPathComponent("MarkdownReader_MarkdownReader.bundle").appendingPathComponent("Contents").appendingPathComponent("Resources"),
        // .appex/Contents/Resources/
        Bundle.main.resourceURL,
        // 主 app: MyApp.app/Contents/Resources/（从 .appex 向上导航）
        Bundle.main.bundleURL
            .deletingLastPathComponent()  // PlugIns/
            .deletingLastPathComponent()  // Contents/
            .appendingPathComponent("Resources"),
        // 主 app: MyApp.app/Contents/Resources/MarkdownReader_MarkdownReader.bundle/Resources/
        Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources")
            .appendingPathComponent("MarkdownReader_MarkdownReader.bundle")
            .appendingPathComponent("Resources"),
    ].compactMap { $0 }

    for path in searchPaths {
        let cssPath = path.appendingPathComponent("css/markdown.css")
        if FileManager.default.fileExists(atPath: cssPath.path) {
            logger.info("Found resources at: \(path.path)")
            return path
        }
    }

    logger.error("No resource path found")
    return nil
}
