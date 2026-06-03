import SwiftUI

/// 文档视图模型，管理当前文档状态和文件读取
@MainActor
@Observable
final class DocumentViewModel {

    // MARK: - 状态

    /// 当前文档内容
    var content: String = "" {
        didSet {
            // 内容变更时标记为脏（跳过首次加载时的赋值）
            if currentFileURL != nil && !isLoading {
                markDirtyIfNeeded()
            }
        }
    }

    /// 当前文件 URL
    var currentFileURL: URL? {
        didSet { syncHasDocument() }
    }

    /// 当前文件名
    var fileName: String = ""

    /// 显示模式
    var displayMode: DisplayMode = .rendered

    /// 是否正在加载
    var isLoading: Bool = false

    /// 错误信息
    var fileError: FileError? {
        didSet { syncHasDocument() }
    }

    /// 内容是否有未保存的修改
    var isDirty: Bool = false

    /// 当前文件是否为未保存的新建文件（位于临时目录）
    var isUntitled: Bool = false

    var hasDocument: Bool = false

    /// 新建文件的临时目录
    static let untitledDirectory: URL = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("MarkdownReader")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// 是否有任何未保存的文件（包括当前文件和缓存中的文件）
    var hasAnyDirtyFile: Bool {
        if isDirty { return true }
        for (url, content) in contentCache {
            if let snapshot = diskContentSnapshot[url], content != snapshot {
                return true
            }
        }
        return false
    }

    /// 当前文档的大纲项
    var outlineItems: [OutlineItem] = []

    /// 大纲导航滚动请求（非 nil 时触发滚动，滚动后应清空）
    var scrollToLineRequest: Int?

    /// Per-file 内容缓存：保存未写入磁盘的编辑内容
    /// 切换文件时保存当前内容，切换回来时恢复缓存内容
    /// 确保 per-file UndoManager 的 undo 动作与内容一致
    private var contentCache: [URL: String] = [:]

    /// Per-file 显示模式缓存：每个文件记住自己的显示模式
    /// 切换文件时保存当前模式，切换回来时恢复，避免模式全局串扰
    private var displayModeCache: [URL: DisplayMode] = [:]

    /// Per-file 磁盘内容快照，用于判断内容是否已修改
    private var diskContentSnapshot: [URL: String] = [:]

    // MARK: - 依赖

    private let fileService: FileService

    /// 设置模型（用于读取默认显示模式等设置）
    var settings: SettingsModel

    // MARK: - 初始化

    init(fileService: FileService = FileService(), settings: SettingsModel = SettingsModel.shared) {
        self.fileService = fileService
        self.settings = settings
        self.displayMode = settings.defaultDisplayMode
    }

    // MARK: - 方法

    /// 加载文件内容
    /// - Parameter url: 文件 URL
    func loadFile(at url: URL) async {
        // 切换文件前，保存当前文件的编辑内容和显示模式到缓存
        if let currentURL = currentFileURL, currentURL != url, hasDocument {
            contentCache[currentURL] = content
            displayModeCache[currentURL] = displayMode
        }

        if isUntitled, let oldURL = currentFileURL, oldURL != url {
            try? FileManager.default.removeItem(at: oldURL)
            contentCache.removeValue(forKey: oldURL)
            diskContentSnapshot.removeValue(forKey: oldURL)
        }

        // 检查是否为 Markdown 文件
        guard url.pathExtension == "md" else {
            fileError = .unsupportedFileType(url.pathExtension)
            content = ""
            currentFileURL = url
            fileName = url.lastPathComponent
            outlineItems = []
            isDirty = false
            isUntitled = false
            return
        }

        isLoading = true
        fileError = nil

        do {
            let diskContent = try await fileService.readFile(at: url)
            currentFileURL = url
            fileName = url.lastPathComponent
            // 保存磁盘内容快照，用于脏状态判断
            diskContentSnapshot[url] = diskContent
            // 优先使用缓存内容（保留未保存的编辑）
            // 缓存内容与 per-file UndoManager 的 undo 动作一致
            if let cached = contentCache[url] {
                content = cached
            } else {
                content = diskContent
            }
            // 更新脏状态
            isDirty = (content != diskContent)
            // 加载真实文件时重置 isUntitled
            isUntitled = false
            outlineItems = OutlineService.parse(content)
            // 恢复目标文件的显示模式（有缓存用缓存，否则用默认设置）
            displayMode = displayModeCache[url] ?? settings.defaultDisplayMode
        } catch let fileError as FileError {
            self.fileError = fileError
            content = ""
            currentFileURL = url
            fileName = url.lastPathComponent
            outlineItems = []
            isDirty = false
            isUntitled = false
        } catch {
            self.fileError = .unknown(error)
            content = ""
            currentFileURL = url
            fileName = url.lastPathComponent
            outlineItems = []
            isDirty = false
            isUntitled = false
        }

        isLoading = false
    }

    /// 加载选中的文件节点
    /// - Parameter node: 文件节点
    func loadFileNode(_ node: FileNode) async {
        if !node.isMarkdown {
            fileError = .unsupportedFileType(node.path.pathExtension)
            currentFileURL = node.path
            fileName = node.name
            content = ""
            outlineItems = []
            isUntitled = false
            return
        }
        await loadFile(at: node.path)
    }

    /// 切换显示模式
    func switchDisplayMode(_ mode: DisplayMode) {
        displayMode = mode
        // 同步更新缓存，确保切换文件后能恢复正确的模式
        if let url = currentFileURL {
            displayModeCache[url] = mode
        }
    }

    /// 请求滚动到指定行号（大纲导航使用）
    func requestScrollToLine(_ lineNumber: Int) {
        scrollToLineRequest = lineNumber
    }

    /// 清除滚动请求（滚动完成后调用）
    func clearScrollRequest() {
        scrollToLineRequest = nil
    }

    @discardableResult
    func createUntitledFile() -> URL? {
        if isUntitled { return nil }

        // 切换前保存当前文件的编辑内容和显示模式
        if let currentURL = currentFileURL, hasDocument {
            contentCache[currentURL] = content
            displayModeCache[currentURL] = displayMode
        }

        let tempDir = Self.untitledDirectory
        let untitledName = "Untitled.md"
        let fileURL = tempDir.appendingPathComponent(untitledName)

        // 创建空文件
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)

        // 使用 isLoading 阻止 content 的 didSet 触发 markDirtyIfNeeded()
        // 确保所有属性一次性设置完毕后再通知 SwiftUI
        isLoading = true

        currentFileURL = fileURL
        fileName = untitledName
        // 先设置快照，再设置 content，确保 markDirtyIfNeeded 即使被调用也能正确比较
        diskContentSnapshot[fileURL] = ""
        contentCache[fileURL] = ""
        content = ""
        outlineItems = []
        isDirty = false
        isUntitled = true
        fileError = nil
        displayMode = settings.defaultDisplayMode

        isLoading = false

        return fileURL
    }

    /// 保存当前文档内容到磁盘
    /// 如果是未保存的新建文件，返回 false 并发送 .saveAsFile 通知
    /// - Returns: 是否保存成功
    @discardableResult
    func save() async -> Bool {
        guard let url = currentFileURL else { return false }

        // 未保存的新建文件需要另存为
        if isUntitled {
            NotificationCenter.default.post(name: .saveAsFile, object: nil)
            return false
        }

        do {
            try await fileService.writeFile(at: url, content: content)
            // 更新磁盘快照
            diskContentSnapshot[url] = content
            isDirty = false
            // 同步更新缓存
            contentCache[url] = content
            return true
        } catch {
            fileError = .permissionDenied(url)
            return false
        }
    }

    /// 另存为：将内容保存到用户指定的新位置
    /// - Parameter newURL: 用户选择的新保存位置
    func saveAs(to newURL: URL) async {
        do {
            let oldURL = currentFileURL
            try await fileService.writeFile(at: newURL, content: content)

            // 清理旧的临时文件
            if isUntitled, let old = oldURL {
                try? FileManager.default.removeItem(at: old)
                contentCache.removeValue(forKey: old)
                diskContentSnapshot.removeValue(forKey: old)
            }

            // 更新文件引用
            currentFileURL = newURL
            fileName = newURL.lastPathComponent
            diskContentSnapshot[newURL] = content
            contentCache[newURL] = content
            isDirty = false
            isUntitled = false
            fileError = nil
        } catch {
            fileError = .permissionDenied(newURL)
        }
    }

    /// 检查内容是否与磁盘快照不同，更新脏状态
    private func markDirtyIfNeeded() {
        guard let url = currentFileURL else {
            isDirty = false
            return
        }
        if let snapshot = diskContentSnapshot[url] {
            isDirty = (content != snapshot)
        }
    }

    /// 同步 hasDocument 存储属性，确保 @Observable 可靠追踪
    /// 在 currentFileURL / fileError 的 didSet 中自动调用
    private func syncHasDocument() {
        hasDocument = (currentFileURL != nil && fileError == nil)
    }

    /// 检查指定文件是否有未保存的修改
    /// 比较缓存内容（或当前内容）与磁盘快照，判断文件是否处于脏状态
    /// - Parameter url: 文件 URL
    /// - Returns: 是否有未保存的修改
    func isFileDirty(at url: URL) -> Bool {
        // 当前正在编辑的文件，直接使用 isDirty
        if url == currentFileURL {
            return isDirty
        }
        // 非当前文件，比较缓存内容与磁盘快照
        guard let cached = contentCache[url], let snapshot = diskContentSnapshot[url] else {
            return false
        }
        return cached != snapshot
    }

    /// 清除当前文档
    func clearDocument() {
        // 清理未保存新建文件的临时文件
        if isUntitled, let url = currentFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        content = ""
        currentFileURL = nil
        fileName = ""
        fileError = nil
        isLoading = false
        isDirty = false
        isUntitled = false
        displayMode = settings.defaultDisplayMode
        outlineItems = []
        contentCache.removeAll()
        displayModeCache.removeAll()
        diskContentSnapshot.removeAll()
    }

    /// 取消选中当前文件（保留其他文件的缓存）
    /// 用于外部删除等场景：仅清理当前文件状态，不丢失其他已编辑文件的缓存
    func deselectCurrentFile() {
        if let url = currentFileURL {
            contentCache.removeValue(forKey: url)
            displayModeCache.removeValue(forKey: url)
            diskContentSnapshot.removeValue(forKey: url)
        }
        content = ""
        currentFileURL = nil
        fileName = ""
        fileError = nil
        isLoading = false
        isDirty = false
        isUntitled = false
        displayMode = settings.defaultDisplayMode
        outlineItems = []
    }

    func discardUntitledFile() {
        guard isUntitled, let url = currentFileURL else { return }
        try? FileManager.default.removeItem(at: url)
        contentCache.removeValue(forKey: url)
        diskContentSnapshot.removeValue(forKey: url)
        isUntitled = false
        isDirty = false
    }
}
