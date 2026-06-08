import Foundation
import Markdown

enum MarkdownHTMLService {

    struct RenderResult {
        let html: String
        let headings: [HeadingInfo]
    }

    struct HeadingInfo {
        let id: String
        let level: Int
        let title: String
        let lineNumber: Int
    }

    static func render(_ markdown: String, baseURL: URL? = nil) -> RenderResult {
        let preprocessed = preprocess(markdown)
        let doc = Markdown.Document(parsing: preprocessed)
        var formatter = CustomHTMLFormatter(baseURL: baseURL)
        formatter.visit(doc)
        return RenderResult(
            html: formatter.result,
            headings: formatter.headings
        )
    }

    static func buildFullHTML(content: String, themeCSS: String, contentPadding: CGFloat, baseURL: URL?, isDark: Bool = true) -> String {
        let renderResult = render(content, baseURL: baseURL)

        let baseURLAttr = baseURL != nil ? " data-base-url=\"\(baseURL!.path.addingXMLAttributeEscapes)\"" : ""

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <link rel="stylesheet" href="mr:///css/markdown.css">
            <link rel="stylesheet" href="mr:///css/scroll.css">
            <link rel="stylesheet" href="mr:///css/katex.min.css">
            <style id="mr-theme-style">\(themeCSS)</style>
            <style>
            :root { --content-padding: \(contentPadding)px; }
            </style>
        </head>
        <body>
            <div class="markdown-preview"\(baseURLAttr)>
                <div id="mr-content">
                    \(renderResult.html)
                </div>
            </div>
            <script src="mr:///js/mermaid.min.js"></script>
            <script src="mr:///js/katex.min.js"></script>
            <script src="mr:///js/prism-core.min.js"></script>
            <script src="mr:///js/prism-autoloader.min.js"></script>
            <script>
            Prism.plugins.autoloader.languages_path = 'mr:///js/';
            </script>
            <script src="mr:///js/markdown-reader.js" data-is-dark="\(isDark)"></script>
        </body>
        </html>
        """
    }

    private static func preprocess(_ content: String) -> String {
        var result = content
        result = stripYAMLFrontMatter(result)
        return result
    }

    private static func stripYAMLFrontMatter(_ content: String) -> String {
        let pattern = #"^---\s*\n[\s\S]*?\n---\s*\n"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return content }
        let range = NSRange(content.startIndex..., in: content)
        return regex.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: "")
    }
}

private struct CustomHTMLFormatter: MarkupWalker {
    var result = ""
    var headings: [MarkdownHTMLService.HeadingInfo] = []
    private var headingCounter = 0
    private let baseURL: URL?

    init(baseURL: URL? = nil) {
        self.baseURL = baseURL
    }

    /// 将相对路径转换为 mr:// 绝对路径，使其通过 URLSchemeHandler 加载
    private func resolveRelativeURL(_ path: String) -> String {
        guard !path.isEmpty else { return path }
        // 已经是绝对 URL 的不做转换
        if path.hasPrefix("http://") || path.hasPrefix("https://") ||
           path.hasPrefix("mr://") || path.hasPrefix("data:") ||
           path.hasPrefix("/") || path.hasPrefix("#") ||
           path.hasPrefix("mailto:") {
            return path
        }
        // 相对路径：基于 baseURL 转为 mr:// 绝对路径
        if let baseURL = baseURL {
            let absoluteURL = baseURL.appendingPathComponent(path)
            return "mr:///" + absoluteURL.path
        }
        return path
    }

    mutating func visitDocument(_ document: Markdown.Document) {
        for child in document.children {
            visit(child)
        }
    }

    mutating func visitHeading(_ heading: Heading) {
        headingCounter += 1
        let id = "heading-\(headingCounter)"
        let lineNumber = heading.range?.lowerBound.line ?? 0
        let title = heading.plainText

        headings.append(MarkdownHTMLService.HeadingInfo(
            id: id,
            level: heading.level,
            title: title,
            lineNumber: lineNumber
        ))

        result += "<h\(heading.level) id=\"\(id)\" data-line=\"\(lineNumber)\">"
        descendInto(heading)
        result += "</h\(heading.level)>\n"
    }

    mutating func visitParagraph(_ paragraph: Paragraph) {
        let lineNumber = paragraph.range?.lowerBound.line ?? 0
        result += "<p data-line=\"\(lineNumber)\">"
        descendInto(paragraph)
        result += "</p>\n"
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        let language = codeBlock.language ?? ""
        let languageClass = language.isEmpty ? "" : " class=\"language-\(language.htmlEscaped)\""
        let lineNumber = codeBlock.range?.lowerBound.line ?? 0
        result += "<pre data-line=\"\(lineNumber)\"><code\(languageClass)>\(codeBlock.code.htmlEscaped)</code></pre>\n"
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        let lineNumber = blockQuote.range?.lowerBound.line ?? 0
        result += "<blockquote data-line=\"\(lineNumber)\">\n"
        descendInto(blockQuote)
        result += "</blockquote>\n"
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) {
        let lineNumber = unorderedList.range?.lowerBound.line ?? 0
        result += "<ul data-line=\"\(lineNumber)\">\n"
        descendInto(unorderedList)
        result += "</ul>\n"
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) {
        let lineNumber = orderedList.range?.lowerBound.line ?? 0
        result += "<ol data-line=\"\(lineNumber)\">\n"
        descendInto(orderedList)
        result += "</ol>\n"
    }

    mutating func visitListItem(_ listItem: ListItem) {
        if let checkbox = listItem.checkbox {
            result += "<li class=\"task-list-item\">"
            result += "<input type=\"checkbox\" disabled=\"\""
            if checkbox == .checked {
                result += " checked=\"\""
            }
            result += " /> "
        } else {
            result += "<li>"
        }
        descendInto(listItem)
        result += "</li>\n"
    }

    mutating func visitTable(_ table: Table) {
        let lineNumber = table.range?.lowerBound.line ?? 0
        result += "<table data-line=\"\(lineNumber)\">\n<thead>\n<tr>\n"
        for cell in table.head.cells {
            let align = alignmentAttr(table.columnAlignments[cell.indexInParent])
            result += "<th\(align)>"
            descendInto(cell)
            result += "</th>\n"
        }
        result += "</tr>\n</thead>\n"
        let bodyRows = Array(table.body.rows)
        if !bodyRows.isEmpty {
            result += "<tbody>\n"
            for row in bodyRows {
                result += "<tr>\n"
                for cell in row.cells {
                    let align = alignmentAttr(table.columnAlignments[cell.indexInParent])
                    result += "<td\(align)>"
                    descendInto(cell)
                    result += "</td>\n"
                }
                result += "</tr>\n"
            }
            result += "</tbody>\n"
        }
        result += "</table>\n"
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        let lineNumber = thematicBreak.range?.lowerBound.line ?? 0
        result += "<hr data-line=\"\(lineNumber)\" />\n"
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) {
        result += html.rawHTML
        result += "\n"
    }

    mutating func visitText(_ text: Text) {
        result += text.string.htmlEscaped
    }

    mutating func visitStrong(_ strong: Strong) {
        result += "<strong>"
        descendInto(strong)
        result += "</strong>"
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) {
        result += "<em>"
        descendInto(emphasis)
        result += "</em>"
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) {
        result += "<del>"
        descendInto(strikethrough)
        result += "</del>"
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        result += "<code>\(inlineCode.code.htmlEscaped)</code>"
    }

    mutating func visitLink(_ link: Link) {
        let rawDestination = link.destination?.htmlEscaped ?? ""
        let destination = resolveRelativeURL(rawDestination)
        let title = link.title != nil ? " title=\"\(link.title!.htmlEscaped)\"" : ""
        result += "<a href=\"\(destination)\"\(title)>"
        descendInto(link)
        result += "</a>"
    }

    mutating func visitImage(_ image: Image) {
        let rawSource = image.source?.htmlEscaped ?? ""
        let source = resolveRelativeURL(rawSource)
        let title = image.title != nil ? " title=\"\(image.title!.htmlEscaped)\"" : ""
        let alt = image.plainText.htmlEscaped
        result += "<img src=\"\(source)\" alt=\"\(alt)\"\(title) />"
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) {
        result += "\n"
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) {
        result += "<br />\n"
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) {
        result += inlineHTML.rawHTML
    }

    private func alignmentAttr(_ alignment: Table.ColumnAlignment?) -> String {
        switch alignment {
        case .left: return " align=\"left\""
        case .center: return " align=\"center\""
        case .right: return " align=\"right\""
        case nil: return ""
        }
    }
}

extension String {
    var htmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    var addingXMLAttributeEscapes: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
