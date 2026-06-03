import SwiftUI

/// 目录树视图模型，管理目录树数据和展开/折叠状态
@MainActor
@Observable
final class FileTreeViewModel {

    // MARK: - 状态

    /// 目录树根节点
    var nodes: [FileNode] = []

    /// 已展开的目录 URL 集合
    var expandedDirs: Set<URL> = []

    /// 当前选中的文件 URL
    var selectedFileURL: URL?

    /// 是否正在加载
    var isLoading: Bool = false

    /// 错误信息
    var errorMessage: String?

    /// 是否为空目录（无 Markdown 文件）
    var isEmptyDirectory: Bool = false

    // MARK: - 依赖

    private let fileService: FileService

    /// 设置模型（用于读取文件树过滤设置）
    var settings: SettingsModel

    /// 文件系统监控器
    private let fileSystemWatcher = FileSystemWatcher()

    /// 是否正在刷新（防止并发刷新）
    private var isRefreshing = false

    /// 是否有待处理的刷新请求
    private var needsRefresh = false

    // MARK: - 初始化

    init(fileService: FileService = FileService(), settings: SettingsModel = SettingsModel.shared) {
        self.fileService = fileService
        self.settings = settings
    }

    // MARK: - 方法

    /// 加载目录树
    /// - Parameter directory: 根目录 URL
    func loadDirectory(_ directory: URL) async {
        isLoading = true
        errorMessage = nil
        isEmptyDirectory = false

        // 停止之前的监控
        fileSystemWatcher.stopWatching()

        do {
            let children = try await fileService.scanDirectory(
                directory,
                showHiddenFiles: settings.showHiddenFiles,
                showNonMarkdownFiles: settings.showNonMarkdownFiles
            )
            isEmptyDirectory = !fileService.directoryContainsMarkdown(
                directory,
                showHiddenFiles: settings.showHiddenFiles
            )

            // 根目录作为一级节点显示，子目录内容作为其 children
            let rootNode = FileNode(
                name: directory.lastPathComponent,
                path: directory,
                isDirectory: true,
                children: children
            )
            nodes = [rootNode]

            // 默认展开根目录（显示第一级目录和文件）
            expandedDirs.insert(directory)
        } catch {
            errorMessage = error.localizedDescription
            nodes = []
        }

        isLoading = false

        // 开始监控目录变化
        startWatching(directory)
    }

    /// 刷新目录树（由文件系统监控触发，不显示加载状态，保留展开和选中状态）
    func refreshDirectory() async {
        if isRefreshing {
            // 已有刷新在进行中，标记需要再次刷新
            needsRefresh = true
            return
        }

        guard let dir = rootDirectory else { return }

        // 检查根目录是否仍然存在
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else {
            // 根目录已被删除或移动
            clearDirectory()
            errorMessage = "目录已被删除或移动"
            return
        }

        isRefreshing = true

        do {
            let children = try await fileService.scanDirectory(
                dir,
                showHiddenFiles: settings.showHiddenFiles,
                showNonMarkdownFiles: settings.showNonMarkdownFiles
            )

            let rootNode = FileNode(
                name: dir.lastPathComponent,
                path: dir,
                isDirectory: true,
                children: children
            )
            nodes = [rootNode]

            // 清理已不存在的展开目录
            let allPaths = Set(collectAllPaths(from: nodes))
            expandedDirs = expandedDirs.intersection(allPaths)
            expandedDirs.insert(dir)

            // 如果选中的文件已不存在，清除选中
            if let selected = selectedFileURL, !allPaths.contains(selected) {
                selectedFileURL = nil
            }

            isEmptyDirectory = !fileService.directoryContainsMarkdown(
                dir,
                showHiddenFiles: settings.showHiddenFiles
            )
            errorMessage = nil
        } catch {
            // 刷新失败时不覆盖已有数据，仅记录错误
        }

        isRefreshing = false

        // 如果刷新期间有新的变更，再次刷新
        if needsRefresh {
            needsRefresh = false
            Task { @MainActor in
                await refreshDirectory()
            }
        }
    }

    /// 停止文件监控并清空目录树
    func clearDirectory() {
        fileSystemWatcher.stopWatching()
        nodes = []
        expandedDirs = []
        selectedFileURL = nil
        errorMessage = nil
        isEmptyDirectory = false
        isRefreshing = false
        needsRefresh = false
    }

    /// 切换目录展开/折叠
    func toggleExpand(_ url: URL) {
        if expandedDirs.contains(url) {
            expandedDirs.remove(url)
        } else {
            expandedDirs.insert(url)
        }
    }

    /// 判断目录是否已展开
    func isExpanded(_ url: URL) -> Bool {
        expandedDirs.contains(url)
    }

    /// 选中文件（包括非 .md 文件，以触发错误提示）
    func selectFile(_ node: FileNode) {
        if node.isDirectory { return }
        selectedFileURL = node.path
    }

    /// 获取扁平化的可见节点列表（用于键盘导航）
    func flattenedVisibleNodes() -> [FileNode] {
        var result: [FileNode] = []
        for node in nodes {
            result.append(node)
            if node.isDirectory, expandedDirs.contains(node.path), let children = node.children {
                result.append(contentsOf: flattenChildren(children))
            }
        }
        return result
    }

    /// 在扁平列表中移动选中项
    func moveSelection(direction: Int) -> FileNode? {
        let flat = flattenedVisibleNodes()
        guard !flat.isEmpty else { return nil }

        let currentIndex: Int
        if let currentURL = selectedFileURL,
           let idx = flat.firstIndex(where: { $0.path == currentURL }) {
            currentIndex = idx
        } else {
            currentIndex = -1
        }

        let newIndex = max(0, min(flat.count - 1, currentIndex + direction))
        let node = flat[newIndex]

        if node.isDirectory {
            toggleExpand(node.path)
        } else {
            selectFile(node)
        }

        return node
    }

    // MARK: - 新建文件

    /// 在指定目录下创建新的 Markdown 文件
    /// - Parameter directory: 目标目录 URL，若为 nil 则使用根目录
    /// - Returns: 新建文件的 URL，失败返回 nil
    func createNewFile(in directory: URL? = nil) -> URL? {
        let targetDir = directory ?? rootDirectory
        guard let dir = targetDir else { return nil }

        // 生成不重名的文件名
        var fileName = "Untitled.md"
        var fileURL = dir.appendingPathComponent(fileName)
        var counter = 1
        while FileManager.default.fileExists(atPath: fileURL.path) {
            fileName = "Untitled \(counter).md"
            fileURL = dir.appendingPathComponent(fileName)
            counter += 1
        }

        // 创建空文件
        guard FileManager.default.createFile(atPath: fileURL.path, contents: nil) else {
            return nil
        }

        // 刷新目录树（使用 refreshDirectory 避免重启监控器）
        Task {
            await refreshDirectory()
            // 选中新建的文件
            selectedFileURL = fileURL
        }

        return fileURL
    }

    /// 根目录 URL（供外部访问）
    var rootDirectory: URL? {
        nodes.first?.path
    }

    // MARK: - 文件监控

    /// 开始监控目录变化
    private func startWatching(_ directory: URL) {
        fileSystemWatcher.startWatching(url: directory) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.refreshDirectory()
            }
        }
    }

    /// 收集所有节点路径（用于清理展开状态和选中状态）
    private func collectAllPaths(from nodes: [FileNode]) -> [URL] {
        var paths: [URL] = []
        for node in nodes {
            paths.append(node.path)
            if let children = node.children {
                paths.append(contentsOf: collectAllPaths(from: children))
            }
        }
        return paths
    }

    // MARK: - 私有方法

    private func flattenChildren(_ children: [FileNode]) -> [FileNode] {
        var result: [FileNode] = []
        for node in children {
            result.append(node)
            if node.isDirectory, expandedDirs.contains(node.path), let subChildren = node.children {
                result.append(contentsOf: flattenChildren(subChildren))
            }
        }
        return result
    }
}
