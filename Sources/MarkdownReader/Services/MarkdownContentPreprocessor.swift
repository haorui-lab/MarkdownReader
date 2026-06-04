import Foundation

/// Markdown 内容预处理器
///
/// 在传给 Textual StructuredText 渲染之前，对 Markdown 源码进行预处理，
/// 解决 Foundation Markdown 解析器的已知限制。
enum MarkdownContentPreprocessor {
    /// 对 Markdown 内容执行全部预处理步骤
    static func preprocess(_ content: String) -> String {
        var result = content
        result = stripYAMLFrontMatter(result)
        result = convertLinkedImages(result)
        result = convertHTMLImageTags(result)
        result = convertHTMLAnchorTags(result)
        result = convertHTMLSupSubTags(result)
        return result
    }

    /// 转换链接图片：`[![alt](img_url)](link_url "title")` → `![alt](img_url)`
    ///
    /// Foundation 的 `AttributedString(markdown:)` 解析器在处理嵌套链接图片时，
    /// 只保留外层 `link` 属性，内层 `imageURL` 被丢弃。
    static func convertLinkedImages(_ content: String) -> String {
        let pattern = #"\[!\[([^\]]*)\]\(([^)]+)\)\]\(([^)\s]+)(?:\s+"[^"]*")?\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return content }
        let range = NSRange(content.startIndex..., in: content)
        return regex.stringByReplacingMatches(in: content, range: range, withTemplate: "![$1]($2)")
    }

    /// 剥离 YAML Front Matter（`---` 包裹的头部）
    static func stripYAMLFrontMatter(_ content: String) -> String {
        let pattern = #"^---\s*\n[\s\S]*?\n---\s*\n"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return content }
        let range = NSRange(content.startIndex..., in: content)
        return regex.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: "")
    }

    /// 转换 HTML img 标签：`<img src="url" alt="text">` → `![text](url)`
    static func convertHTMLImageTags(_ content: String) -> String {
        let pattern = #"<img\s+[^>]*src=["']([^"']+)["'][^>]*(?:alt=["']([^"']*)["'])?[^>]*\/?>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return content
        }
        let range = NSRange(content.startIndex..., in: content)
        return regex.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: "![$2]($1)")
    }

    /// 转换 HTML a 标签：`<a href="url">text</a>` → `[text](url)`
    static func convertHTMLAnchorTags(_ content: String) -> String {
        let pattern = #"<a\s+[^>]*href=["']([^"']+)["'][^>]*>([^<]*)<\/a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return content
        }
        let range = NSRange(content.startIndex..., in: content)
        return regex.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: "[$2]($1)")
    }

    /// 转换 HTML sup/sub 标签为 PUA 标记字符
    ///
    /// Foundation Markdown 不支持 `<sup>`/`<sub>`，将其替换为 Unicode PUA 字符，
    /// 供 SupSubMarkupParser 后处理时识别并应用格式。
    ///
    /// 标记映射（与 SupSubMarkupParser 保持同步）：
    /// - `<sup>...</sup>` → U+E000...U+E001
    /// - `<sub>...</sub>` → U+E002...U+E003
    static func convertHTMLSupSubTags(_ content: String) -> String {
        var result = content

        let supPattern = #"<sup(?:\s[^>]*)?>(.*?)</sup>"#
        if let regex = try? NSRegularExpression(pattern: supPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let range = NSRange(result.startIndex..., in: result)
            for match in regex.matches(in: result, range: range).reversed() {
                guard let cRange = Range(match.range(at: 1), in: result),
                      let fRange = Range(match.range, in: result) else { continue }
                result.replaceSubrange(fRange, with: "\u{E000}\(result[cRange])\u{E001}")
            }
        }

        let subPattern = #"<sub(?:\s[^>]*)?>(.*?)</sub>"#
        if let regex = try? NSRegularExpression(pattern: subPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let range = NSRange(result.startIndex..., in: result)
            for match in regex.matches(in: result, range: range).reversed() {
                guard let cRange = Range(match.range(at: 1), in: result),
                      let fRange = Range(match.range, in: result) else { continue }
                result.replaceSubrange(fRange, with: "\u{E002}\(result[cRange])\u{E003}")
            }
        }

        return result
    }
}
