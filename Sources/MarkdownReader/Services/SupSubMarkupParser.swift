import SwiftUI
import Textual

// MARK: - 上标/下标标记解析器

/// 在 Foundation Markdown 解析后对 `<sup>`/`<sub>` HTML 标签内容
/// 应用 baselineOffset 和缩放字号，实现上标/下标渲染。
///
/// **渲染管线**：
/// 1. 预处理（由 MarkdownContentPreprocessor 完成）：`<sup>text</sup>` → PUA 标记
/// 2. Foundation Markdown 解析生成 AttributedString
/// 3. 后处理：遍历 runs，移除 PUA 标记，对标记间文本应用格式
///
/// **为什么不用 SyntaxExtension？**
/// `SyntaxExtension.init` 依赖 internal 类型 `PatternTokenizer.Pattern`/`Token`，
/// 无法从 Textual 模块外部创建自定义扩展。因此直接实现 `MarkupParser` 协议。
@MainActor
struct SupSubMarkupParser: MarkupParser {

    // MARK: - Unicode PUA 标记字符

    private static let supStart = Character("\u{E000}")
    private static let supEnd = Character("\u{E001}")
    private static let subStart = Character("\u{E002}")
    private static let subEnd = Character("\u{E003}")

    // MARK: - 格式参数

    private static let fontScaleFactor: CGFloat = 0.7
    private static let supBaselineFactor: CGFloat = 0.35
    private static let subBaselineFactor: CGFloat = -0.15

    // MARK: - 属性

    let baseURL: URL?

    // MARK: - MarkupParser

    func attributedString(for input: String) throws -> AttributedString {
        let preprocessed = MarkdownContentPreprocessor.preprocess(input)
        let attributed = try AttributedString(
            markdown: preprocessed,
            including: \.textual,
            options: .init(),
            baseURL: baseURL
        )
        return applySupSubFormatting(attributed)
    }

    // MARK: - 后处理

    private enum MarkerMode {
        case normal
        case superscript
        case `subscript`
    }

    /// 遍历 AttributedString runs，找到 PUA 标记字符，
    /// 移除标记并对标记间文本应用 baselineOffset + 缩放字号。
    /// 跨 run 的 sup/sub 内容也能正确处理（currentMode 在 run 间保持状态）。
    private func applySupSubFormatting(_ attributed: AttributedString) -> AttributedString {
        var result = AttributedString()
        var currentMode: MarkerMode = .normal

        for run in attributed.runs {
            let text = String(attributed[run.range].characters)
            let attrs = run.attributes
            var buffer = ""

            for char in text {
                switch char {
                case Self.supStart:
                    flush(&result, buffer: &buffer, attributes: attrs, mode: currentMode)
                    currentMode = .superscript
                case Self.supEnd:
                    flush(&result, buffer: &buffer, attributes: attrs, mode: currentMode)
                    currentMode = .normal
                case Self.subStart:
                    flush(&result, buffer: &buffer, attributes: attrs, mode: currentMode)
                    currentMode = .subscript
                case Self.subEnd:
                    flush(&result, buffer: &buffer, attributes: attrs, mode: currentMode)
                    currentMode = .normal
                default:
                    buffer.append(char)
                }
            }

            flush(&result, buffer: &buffer, attributes: attrs, mode: currentMode)
        }

        return result
    }

    private func flush(
        _ result: inout AttributedString,
        buffer: inout String,
        attributes: AttributeContainer,
        mode: MarkerMode
    ) {
        guard !buffer.isEmpty else { return }

        var attrs = attributes
        switch mode {
        case .superscript:
            applySupFormatting(&attrs)
        case .subscript:
            applySubFormatting(&attrs)
        case .normal:
            break
        }

        result.append(AttributedString(buffer, attributes: attrs))
        buffer = ""
    }

    private func applySupFormatting(_ attrs: inout AttributeContainer) {
        let baseFontSize = resolveBaseFontSize(attrs.font)
        attrs.font = .system(size: baseFontSize * Self.fontScaleFactor)
        attrs.baselineOffset = baseFontSize * Self.supBaselineFactor
    }

    private func applySubFormatting(_ attrs: inout AttributeContainer) {
        let baseFontSize = resolveBaseFontSize(attrs.font)
        attrs.font = .system(size: baseFontSize * Self.fontScaleFactor)
        attrs.baselineOffset = baseFontSize * Self.subBaselineFactor
    }

    /// SwiftUI Font 是不透明类型，无法直接提取 point size。
    /// 使用 SwiftUI .body 默认字号（17pt）作为基准——这是 StructuredText 的默认字号。
    private func resolveBaseFontSize(_ font: Font?) -> CGFloat {
        17.0
    }
}
