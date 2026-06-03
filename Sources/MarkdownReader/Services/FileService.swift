import Foundation

/// 文件系统服务，负责目录扫描和文件读取
struct FileService: Sendable {

    /// 扫描指定目录，返回文件树结构
    /// - Parameters:
    ///   - directory: 要扫描的目录 URL
    ///   - showHiddenFiles: 是否显示隐藏文件
    ///   - showNonMarkdownFiles: 是否显示非 Markdown 文件
    /// - Returns: 排序后的 FileNode 数组
    func scanDirectory(
        _ directory: URL,
        showHiddenFiles: Bool = false,
        showNonMarkdownFiles: Bool = true
    ) async throws -> [FileNode] {
        var options: FileManager.DirectoryEnumerationOptions = [.skipsSubdirectoryDescendants]
        if !showHiddenFiles {
            options.insert(.skipsHiddenFiles)
        }

        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
            options: options
        )

        var nodes: [FileNode] = []

        for url in contents {
            let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey, .nameKey])
            let isDirectory = resourceValues.isDirectory ?? false
            let name = resourceValues.name ?? url.lastPathComponent
            let isMarkdown = url.pathExtension == "md"

            if isDirectory {
                let children = try await scanDirectory(
                    url,
                    showHiddenFiles: showHiddenFiles,
                    showNonMarkdownFiles: showNonMarkdownFiles
                )
                // 如果目录内没有可见文件，跳过空目录
                guard !children.isEmpty else { continue }
                let node = FileNode(
                    name: name,
                    path: url,
                    isDirectory: true,
                    children: children
                )
                nodes.append(node)
            } else {
                // 如果不显示非 Markdown 文件，则跳过
                if !showNonMarkdownFiles && !isMarkdown { continue }
                let node = FileNode(
                    name: name,
                    path: url,
                    isDirectory: false,
                    isMarkdown: isMarkdown,
                    children: nil
                )
                nodes.append(node)
            }
        }

        // 排序：目录在前，文件在后；同类型按名称排序
        nodes.sort { a, b in
            if a.isDirectory != b.isDirectory {
                return a.isDirectory
            }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }

        return nodes
    }

    /// 读取文件内容
    /// - Parameter url: 文件 URL
    /// - Returns: 文件内容字符串
    func readFile(at url: URL) async throws -> String {
        do {
            // 检查文件是否可读
            if FileManager.default.isReadableFile(atPath: url.path) == false {
                throw FileError.permissionDenied(url)
            }
            let content = try String(contentsOf: url, encoding: .utf8)
            return content
        } catch let error as FileError {
            throw error
        } catch {
            // 尝试用其他编码读取
            if let content = try? String(contentsOf: url, encoding: .ascii) {
                return content
            }
            throw FileError.encodingError(url)
        }
    }

    /// 写入文件内容
    /// - Parameters:
    ///   - url: 文件 URL
    ///   - content: 要写入的内容
    func writeFile(at url: URL, content: String) async throws {
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw FileError.permissionDenied(url)
        }
    }

    /// 检查目录是否包含 Markdown 文件
    /// - Parameters:
    ///   - directory: 要检查的目录
    ///   - showHiddenFiles: 是否检查隐藏文件
    /// - Returns: 是否包含 .md 文件
    func directoryContainsMarkdown(_ directory: URL, showHiddenFiles: Bool = false) -> Bool {
        var options: FileManager.DirectoryEnumerationOptions = []
        if !showHiddenFiles {
            options.insert(.skipsHiddenFiles)
        }

        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: options
        ) else {
            return false
        }

        for case let url as URL in enumerator {
            if url.pathExtension == "md" {
                return true
            }
        }
        return false
    }
}
