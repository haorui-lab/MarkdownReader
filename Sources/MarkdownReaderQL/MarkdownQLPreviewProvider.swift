import QuickLookUI
import MarkdownReaderKit

@objc(MarkdownQLPreviewProvider)
final class MarkdownQLPreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let enabled = CFPreferencesGetAppBooleanValue(
            "com.markdownreader.enableQuickLookPreview" as CFString,
            "com.markdownreader.app" as CFString,
            nil
        )

        guard enabled else {
            throw CocoaError(.userCancelled)
        }

        let content = try String(contentsOf: request.fileURL, encoding: .utf8)
        let isDark = detectDarkMode()

        let theme = PresetThemes.defaultTheme(for: isDark ? .dark : .light)
        let themeColors = ThemeColors.from(theme)

        let (inlineCSS, inlineJS) = loadInlineResources()

        let html = MarkdownHTMLService.buildPreviewHTML(
            content: content,
            themeCSS: themeColors.cssCustomProperties + themeColors.codeHighlightCSS,
            inlineCSS: inlineCSS,
            inlineJS: inlineJS,
            contentPadding: 20,
            baseURL: request.fileURL,
            isDark: isDark
        )

        let htmlData = html.data(using: String.Encoding.utf8)!
        return QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 800, height: 600)) { _ in
            htmlData
        }
    }
}

private func detectDarkMode() -> Bool {
    let appearance = NSAppearance.currentDrawing()
    return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
}

private func loadInlineResources() -> (css: String, js: String) {
    let resourceURL = resolveResourceURL()

    var css = ""
    var js = ""

    for name in ["markdown.css", "scroll.css", "katex.min.css"] {
        if let url = resourceURL?.appendingPathComponent("css/\(name)"),
           let data = try? Data(contentsOf: url),
           let content = String(data: data, encoding: .utf8) {
            css += content + "\n"
        }
    }

    let jsFiles = ["mermaid.min.js", "katex.min.js", "prism-core.min.js", "prism-autoloader.min.js", "markdown-reader.js"]
    for name in jsFiles {
        if let url = resourceURL?.appendingPathComponent("js/\(name)"),
           let data = try? Data(contentsOf: url),
           let content = String(data: data, encoding: .utf8) {
            if name == "markdown-reader.js" {
                js += content + "\n"
            } else {
                js += content + ";\n"
            }
        }
    }

    return (css: css, js: js)
}

private func resolveResourceURL() -> URL? {
    let searchPaths: [URL] = [
        Bundle.main.resourceURL?.appendingPathComponent("MarkdownReader_MarkdownReader.bundle").appendingPathComponent("Resources"),
        Bundle.main.resourceURL,
        Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources"),
    ].compactMap { $0 }

    for path in searchPaths {
        let cssPath = path.appendingPathComponent("css/markdown.css")
        if FileManager.default.fileExists(atPath: cssPath.path) {
            return path
        }
    }

    return nil
}
