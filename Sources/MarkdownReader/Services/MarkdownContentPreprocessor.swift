import Foundation

/// Markdown 内容预处理器
///
/// 在传给 Textual StructuredText 渲染之前，对 Markdown 源码进行预处理，
/// 解决 Foundation Markdown 解析器的已知限制。
enum MarkdownContentPreprocessor {
    static func preprocess(_ content: String) -> String {
        var result = content
        result = stripYAMLFrontMatter(result)
        result = convertLinkedImages(result)
        result = convertHTMLImageTags(result)
        result = convertHTMLAnchorTags(result)
        result = convertHTMLSupSubTags(result)
        return result
    }

    /// 转换链接图片：`[![alt](img_url)](link_url "title")` → `![alt](img_url#mr-link=link_url)`
    ///
    /// Foundation 的 `AttributedString(markdown:)` 解析器在处理嵌套链接图片时，
    /// 只保留外层 `link` 属性，内层 `imageURL` 被丢弃。
    /// 将 link_url 编码到 img_url 的 fragment 中（`#mr-link=` 前缀），
    /// ImageAttachmentLoader 会提取 fragment 恢复链接点击功能。
    static func convertLinkedImages(_ content: String) -> String {
        let pattern = #"\[!\[([^\]]*)\]\(([^)]+)\)\]\(([^)\s]+)(?:\s+"[^"]*")?\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return content }
        let range = NSRange(content.startIndex..., in: content)

        var result = content
        let matches = regex.matches(in: result, range: range)

        for match in matches.reversed() {
            guard let altRange = Range(match.range(at: 1), in: result),
                  let imgURLRange = Range(match.range(at: 2), in: result),
                  let linkURLRange = Range(match.range(at: 3), in: result),
                  let fullRange = Range(match.range, in: result) else { continue }

            let alt = String(result[altRange])
            let imgURL = String(result[imgURLRange])
            let linkURL = String(result[linkURLRange])

            let encodedLink = linkURL.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? linkURL
            let replacement = "![\(alt)](\(imgURL)#mr-link=\(encodedLink))"

            result.replaceSubrange(fullRange, with: replacement)
        }

        return result
    }

    static func stripYAMLFrontMatter(_ content: String) -> String {
        let pattern = #"^---\s*\n[\s\S]*?\n---\s*\n"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return content }
        let range = NSRange(content.startIndex..., in: content)
        return regex.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: "")
    }

    static func convertHTMLImageTags(_ content: String) -> String {
        let pattern = #"<img\s+[^>]*src=["']([^"']+)["'][^>]*(?:alt=["']([^"']*)["'])?[^>]*\/?>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return content
        }
        let range = NSRange(content.startIndex..., in: content)
        return regex.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: "![$2]($1)")
    }

    static func convertHTMLAnchorTags(_ content: String) -> String {
        let pattern = #"<a\s+[^>]*href=["']([^"']+)["'][^>]*>([^<]*)<\/a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return content
        }
        let range = NSRange(content.startIndex..., in: content)
        return regex.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: "[$2]($1)")
    }

    /// 转换 HTML sup/sub 标签为 PUA 标记字符（与 SupSubMarkupParser 配合）
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
