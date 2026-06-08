import Foundation
import WebKit

struct MarkdownURLSchemeHandler: URLSchemeHandler {
    private let baseURL: URL?

    init(baseURL: URL?) {
        self.baseURL = baseURL
    }

    func reply(for request: URLRequest) -> some AsyncSequence<URLSchemeTaskResult, any Error> {
        let capturedBaseURL = baseURL
        return AsyncThrowingStream { continuation in
            let url = request.url
            let scheme = url?.scheme

            guard scheme == "mr" else {
                continuation.finish()
                return
            }

            guard var path = url?.path else {
                continuation.finish()
                return
            }

            if path.hasPrefix("/") {
                path = String(path.dropFirst())
            }

            let resourceURL = Self.resolveResourceURL(path: path, baseURL: capturedBaseURL)

            guard let resourceURL, FileManager.default.fileExists(atPath: resourceURL.path) else {
                let response = HTTPURLResponse(
                    url: url!,
                    statusCode: 404,
                    httpVersion: "HTTP/1.1",
                    headerFields: nil
                )!
                continuation.yield(.response(response))
                continuation.yield(.data(Data()))
                continuation.finish()
                return
            }

            do {
                let data = try Data(contentsOf: resourceURL)
                let mimeType = Self.mimeType(for: resourceURL.pathExtension)
                let response = HTTPURLResponse(
                    url: url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": mimeType]
                )!
                continuation.yield(.response(response))
                continuation.yield(.data(data))
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    private static func resolveResourceURL(path: String, baseURL: URL?) -> URL? {
        // 如果路径已经是绝对文件路径，直接使用
        let absoluteURL = URL(fileURLWithPath: "/" + path)
        if FileManager.default.fileExists(atPath: absoluteURL.path) {
            return absoluteURL
        }

        if let baseURL, FileManager.default.fileExists(atPath: baseURL.appendingPathComponent(path).path) {
            return baseURL.appendingPathComponent(path)
        }

        // 在 .app 包内搜索资源，不依赖 Bundle.module（其 fatalError 不可恢复）
        // 搜索顺序：
        //   1. Contents/Resources/MarkdownReader_MarkdownReader.bundle/Resources/{path} （正确结构）
        //   2. Contents/Resources/Resources/{path} （bundle 被展开的情况）
        //   3. Contents/Resources/{path} （bundle 内容被直接展开到 Resources 的情况）
        let searchPaths: [URL] = [
            Bundle.main.resourceURL?.appendingPathComponent("MarkdownReader_MarkdownReader.bundle").appendingPathComponent("Resources").appendingPathComponent(path),
            Bundle.main.resourceURL?.appendingPathComponent("Resources").appendingPathComponent(path),
            Bundle.main.resourceURL?.appendingPathComponent(path),
        ].compactMap { $0 }

        for url in searchPaths {
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        return nil
    }

    private static func mimeType(for pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "css": return "text/css"
        case "js": return "application/javascript"
        case "html", "htm": return "text/html"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "webp": return "image/webp"
        case "ico": return "image/x-icon"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "ttf": return "font/ttf"
        case "json": return "application/json"
        default: return "application/octet-stream"
        }
    }
}
