import SwiftUI
import Textual
import WebKit

@MainActor
struct SupSubMarkupParser: MarkupParser {

    private static let supStart = Character("\u{E000}")
    private static let supEnd = Character("\u{E001}")
    private static let subStart = Character("\u{E002}")
    private static let subEnd = Character("\u{E003}")

    private static let fontScaleFactor: CGFloat = 0.7
    private static let supBaselineFactor: CGFloat = 0.35
    private static let subBaselineFactor: CGFloat = -0.15

    let baseURL: URL?

    func attributedString(for input: String) throws -> AttributedString {
        let preprocessed = MarkdownContentPreprocessor.preprocess(input)
        let attributed = try AttributedString(
            markdown: preprocessed,
            including: \.textual,
            options: .init(),
            baseURL: baseURL
        )
        let withLinks = restoreLinkedImageLinks(attributed)
        return applySupSubFormatting(withLinks)
    }

    /// 从 imageURL 的 fragment（`#mr-link=`）提取链接 URL 并设为 run 的 `link` 属性
    ///
    /// Foundation 解析 `![alt](img#mr-link=link)` 时只保留 `imageURL`，没有 `link`。
    /// Textual 的 `TextLinkInteraction` 通过 `run.link` 检测可点击链接，
    /// 因此需要在此手动将提取的链接 URL 写入 `link` 属性，同时清理 fragment。
    private func restoreLinkedImageLinks(_ attributed: AttributedString) -> AttributedString {
        var result = attributed
        for run in result.runs {
            guard let imageURL = run.imageURL,
                  let fragment = imageURL.fragment,
                  fragment.hasPrefix("mr-link=") else { continue }

            let encodedLink = String(fragment.dropFirst("mr-link=".count))
            let linkURL = encodedLink.removingPercentEncoding.flatMap { URL(string: $0) }

            // 清理 imageURL 的 fragment，保留纯图片 URL
            var components = URLComponents(url: imageURL, resolvingAgainstBaseURL: false)
            components?.fragment = nil
            let cleanImageURL = components?.url ?? imageURL

            result[run.range].imageURL = cleanImageURL
            if let linkURL {
                result[run.range].link = linkURL
            }
        }
        return result
    }

    private enum MarkerMode {
        case normal
        case superscript
        case `subscript`
    }

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

    private func resolveBaseFontSize(_ font: SwiftUI.Font?) -> CGFloat {
        17.0
    }
}

// MARK: - ImageAttachmentLoader

struct ImageAttachmentLoader: AttachmentLoader {
    private let baseURL: URL?

    init(baseURL: URL?) {
        self.baseURL = baseURL
    }

    func attachment(
        for url: URL,
        text: String,
        environment: ColorEnvironmentValues
    ) async throws -> some Attachment {
        let (imageURL, _) = Self.extractLinkFromFragment(url)
        let resolvedURL = URL(string: imageURL.absoluteString, relativeTo: baseURL) ?? imageURL
        let data = try await Self.fetchData(from: resolvedURL)

        if Self.isSVG(data: data) {
            guard let result = await Self.renderSVGWithWebKit(data: data) else {
                throw URLError(.cannotDecodeContentData)
            }
            return RasterImageAttachment(
                cgImage: result.cgImage,
                size: result.logicalSize,
                scale: result.scale,
                text: text
            )
        }

        guard let nsImage = NSImage(data: data) else {
            throw URLError(.cannotDecodeContentData)
        }
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw URLError(.cannotDecodeContentData)
        }
        let scale = CGFloat(cgImage.width) / nsImage.size.width
        return RasterImageAttachment(cgImage: cgImage, size: nsImage.size, scale: scale, text: text)
    }

    /// 从 URL fragment 提取链接图片的跳转 URL（格式：`#mr-link=encoded_url`）
    private static func extractLinkFromFragment(_ url: URL) -> (imageURL: URL, linkURL: URL?) {
        guard let fragment = url.fragment, fragment.hasPrefix("mr-link=") else {
            return (url, nil)
        }
        let encodedLink = String(fragment.dropFirst("mr-link=".count))
        let linkURL = encodedLink.removingPercentEncoding.flatMap { URL(string: $0) }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        let cleanURL = components?.url ?? url
        return (cleanURL, linkURL)
    }

    private static func isSVG(data: Data) -> Bool {
        guard let prefix = String(data: data.prefix(500), encoding: .utf8) else { return false }
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("<svg") || trimmed.contains("<svg ")
            || (trimmed.hasPrefix("<?xml") && trimmed.contains("<svg"))
    }

    struct SVGRenderResult {
        let cgImage: CGImage
        let logicalSize: CGSize
        let scale: CGFloat
    }

    @MainActor
    private static func renderSVGWithWebKit(data: Data) async -> SVGRenderResult? {
        guard let svgString = String(data: data, encoding: .utf8) else { return nil }
        let svgSize = parseSVGSize(from: svgString)
        let renderScale: CGFloat = 2.0
        let frameSize = CGSize(width: svgSize.width * renderScale, height: svgSize.height * renderScale)
        let webView = WKWebView(frame: CGRect(origin: .zero, size: frameSize))
        let html = """
        <!DOCTYPE html><html><head><style>
        * { margin: 0; padding: 0; }
        body { background: transparent; overflow: hidden; }
        svg { width: \(svgSize.width)px; height: \(svgSize.height)px; }
        </style></head><body>\(svgString)</body></html>
        """
        webView.loadHTMLString(html, baseURL: nil as URL?)
        let loaded = await withCheckedContinuation { continuation in
            let navDelegate = NavigationDelegate { continuation.resume(returning: true) }
            webView.navigationDelegate = navDelegate
            NavigationDelegate.retain(navDelegate, on: webView)
        }
        let delay: UInt64 = loaded ? 2_000_000_000 : 3_000_000_000
        try? await Task.sleep(nanoseconds: delay)
        let config = WKSnapshotConfiguration()
        config.rect = CGRect(origin: .zero, size: svgSize)
        guard let snapshot = try? await webView.takeSnapshot(configuration: config) else { return nil }
        guard let tiffData = snapshot.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let cgImage = bitmapRep.cgImage else { return nil }
        return SVGRenderResult(cgImage: cgImage, logicalSize: svgSize, scale: renderScale)
    }

    private static func parseSVGSize(from svgString: String) -> CGSize {
        let widthPattern = #"<svg[^>]*\swidth\s*=\s*["']([\d.]+)"#
        let heightPattern = #"<svg[^>]*\sheight\s*=\s*["']([\d.]+)"#
        var width: CGFloat?, height: CGFloat?
        if let regex = try? NSRegularExpression(pattern: widthPattern, options: [.caseInsensitive]),
           let match = regex.firstMatch(in: svgString, range: NSRange(svgString.startIndex..., in: svgString)),
           let range = Range(match.range(at: 1), in: svgString), let value = Double(svgString[range]) {
            width = CGFloat(value)
        }
        if let regex = try? NSRegularExpression(pattern: heightPattern, options: [.caseInsensitive]),
           let match = regex.firstMatch(in: svgString, range: NSRange(svgString.startIndex..., in: svgString)),
           let range = Range(match.range(at: 1), in: svgString), let value = Double(svgString[range]) {
            height = CGFloat(value)
        }
        if let w = width, let h = height { return CGSize(width: w, height: h) }
        let viewBoxPattern = #"<svg[^>]*\sviewBox\s*=\s*["']\s*[\d.]+\s+[\d.]+\s+([\d.]+)\s+([\d.]+)"#
        if let regex = try? NSRegularExpression(pattern: viewBoxPattern, options: [.caseInsensitive]),
           let match = regex.firstMatch(in: svgString, range: NSRange(svgString.startIndex..., in: svgString)),
           let wRange = Range(match.range(at: 1), in: svgString), let hRange = Range(match.range(at: 2), in: svgString),
           let vw = Double(svgString[wRange]), let vh = Double(svgString[hRange]) {
            return CGSize(width: CGFloat(vw), height: CGFloat(vh))
        }
        if let w = width { return CGSize(width: w, height: w * 0.22) }
        return CGSize(width: 200, height: 40)
    }

    private static func fetchData(from url: URL) async throws -> Data {
        if url.isFileURL { return try Data(contentsOf: url) }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let httpResponse = response as? HTTPURLResponse {
            guard 200..<300 ~= httpResponse.statusCode else { throw URLError(.badServerResponse) }
        }
        return data
    }
}

// MARK: - NavigationDelegate

@MainActor
private class NavigationDelegate: NSObject, WKNavigationDelegate {
    private static var associatedObjectKey: UInt8 = 0
    let onFinished: () -> Void
    init(onFinished: @escaping () -> Void) { self.onFinished = onFinished }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { onFinished() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { onFinished() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { onFinished() }
    static func retain(_ delegate: NavigationDelegate, on webView: WKWebView) {
        objc_setAssociatedObject(webView, &associatedObjectKey, delegate, .OBJC_ASSOCIATION_RETAIN)
    }
}

// MARK: - RasterImageAttachment

struct RasterImageAttachment: Attachment {
    let cgImage: CGImage
    let size: CGSize
    let scale: CGFloat
    let text: String
    var description: String { text }

    /// 链接点击由 Textual 的 TextLinkInteraction 通过 AttributedString 的 `link` 属性处理，
    /// 不需要在 Attachment 层面处理点击事件。onTapGesture/CursorOverlayView 会拦截
    /// Textual 的原生链接交互，导致链接图片无法点击。
    @MainActor
    var body: some View {
        Image(decorative: cgImage, scale: scale)
            .resizable()
            .aspectRatio(contentMode: .fit)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, in _: TextEnvironmentValues) -> CGSize {
        guard let proposedWidth = proposal.width else { return size }
        let aspect = size.width / size.height
        let width = min(proposedWidth, size.width)
        let height = width / aspect
        return CGSize(width: width, height: height)
    }

    func pngData() -> Data? {
        NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    }
}
