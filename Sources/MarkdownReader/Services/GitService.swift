import Foundation

/// Git 服务，通过 Process 执行 git 命令
struct GitService: Sendable {

    // MARK: - Git 状态信息

    /// Git 仓库状态摘要
    struct GitStatus: Sendable {
        let branch: String
        let remote: String?
        let stagedFiles: [FileChange]
        let unstagedFiles: [FileChange]
        let untrackedFiles: [String]
        let isClean: Bool
        let latestCommitHash: String?
    }

    /// 文件变更信息
    struct FileChange: Sendable {
        let path: String
        let status: ChangeStatus
    }

    /// 变更状态
    enum ChangeStatus: String, Sendable {
        case added = "A"
        case modified = "M"
        case deleted = "D"
        case renamed = "R"
        case copied = "C"
        case unmerged = "U"
        case unknown = "?"
    }

    // MARK: - 公共方法

    /// 检查目录是否为 git 仓库
    func isGitRepository(_ directory: URL) -> Bool {
        let result = runGit(arguments: ["rev-parse", "--is-inside-work-tree"], workingDirectory: directory)
        return result.success && result.output.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }

    /// 获取当前分支名
    func currentBranch(_ directory: URL) -> String? {
        let result = runGit(arguments: ["rev-parse", "--abbrev-ref", "HEAD"], workingDirectory: directory)
        guard result.success else { return nil }
        let branch = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return branch.isEmpty ? nil : branch
    }

    /// 获取远程名（通常为 origin 或 upstream）
    func remoteName(_ directory: URL) -> String? {
        let result = runGit(arguments: ["remote"], workingDirectory: directory)
        guard result.success else { return nil }
        let remotes = result.output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n")
            .map(String.init)
        // 优先返回 upstream，其次 origin
        if remotes.contains("upstream") { return "upstream" }
        if remotes.contains("origin") { return "origin" }
        return remotes.first
    }

    /// 获取最新 commit hash（短格式）
    func latestCommitHash(_ directory: URL) -> String? {
        let result = runGit(arguments: ["rev-parse", "--short", "HEAD"], workingDirectory: directory)
        guard result.success else { return nil }
        let hash = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return hash.isEmpty ? nil : hash
    }

    /// 获取完整 git 状态
    func gitStatus(_ directory: URL) -> GitStatus? {
        guard isGitRepository(directory) else { return nil }

        let branch = currentBranch(directory)
        let remote = remoteName(directory)
        let commitHash = latestCommitHash(directory)

        // 获取 porcelain 格式的 status
        let statusResult = runGit(
            arguments: ["status", "--porcelain=v1"],
            workingDirectory: directory
        )
        guard statusResult.success else {
            return GitStatus(
                branch: branch ?? "unknown",
                remote: remote,
                stagedFiles: [],
                unstagedFiles: [],
                untrackedFiles: [],
                isClean: true,
                latestCommitHash: commitHash
            )
        }

        var stagedFiles: [FileChange] = []
        var unstagedFiles: [FileChange] = []
        var untrackedFiles: [String] = []

        let lines = statusResult.output.split(separator: "\n", omittingEmptySubsequences: true)
        for line in lines {
            let lineStr = String(line)
            guard lineStr.count >= 4 else { continue }

            let indexStatus = String(lineStr[lineStr.index(lineStr.startIndex, offsetBy: 0)])
            let workTreeStatus = String(lineStr[lineStr.index(lineStr.startIndex, offsetBy: 1)])
            let filePath = String(lineStr[lineStr.index(lineStr.startIndex, offsetBy: 3)...])

            // 未跟踪文件
            if indexStatus == "?" && workTreeStatus == "?" {
                untrackedFiles.append(filePath)
                continue
            }

            // 暂存区变更
            if indexStatus != " " && indexStatus != "?" {
                if let status = ChangeStatus(rawValue: indexStatus) {
                    stagedFiles.append(FileChange(path: filePath, status: status))
                }
            }

            // 工作区变更
            if workTreeStatus != " " && workTreeStatus != "?" {
                if let status = ChangeStatus(rawValue: workTreeStatus) {
                    unstagedFiles.append(FileChange(path: filePath, status: status))
                }
            }
        }

        let isClean = stagedFiles.isEmpty && unstagedFiles.isEmpty && untrackedFiles.isEmpty

        return GitStatus(
            branch: branch ?? "unknown",
            remote: remote,
            stagedFiles: stagedFiles,
            unstagedFiles: unstagedFiles,
            untrackedFiles: untrackedFiles,
            isClean: isClean,
            latestCommitHash: commitHash
        )
    }

    /// 添加所有变更到暂存区
    func addAll(_ directory: URL) -> Bool {
        let result = runGit(arguments: ["add", "--all"], workingDirectory: directory)
        return result.success
    }

    /// 提交变更
    func commit(_ directory: URL, message: String) -> Bool {
        let result = runGit(arguments: ["commit", "-m", message], workingDirectory: directory)
        return result.success
    }

    /// 推送到远程
    func push(_ directory: URL, remote: String, branch: String) -> Bool {
        let result = runGit(arguments: ["push", remote, branch], workingDirectory: directory)
        return result.success
    }

    /// 提交并推送（一步操作）
    /// - Returns: 推送成功后返回短 commit hash，失败返回 nil
    func commitAndPush(_ directory: URL, message: String) -> String? {
        guard addAll(directory) else { return nil }
        guard commit(directory, message: message) else { return nil }

        let commitHash = latestCommitHash(directory)

        guard let branch = currentBranch(directory),
              let remote = remoteName(directory) else { return nil }

        guard push(directory, remote: remote, branch: branch) else { return nil }

        return commitHash
    }

    // MARK: - 私有方法

    private struct ProcessResult {
        let success: Bool
        let output: String
    }

    @discardableResult
    private func runGit(arguments: [String], workingDirectory: URL) -> ProcessResult {
        let process = Process()
        let pipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.standardOutput = pipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            if process.terminationStatus == 0 {
                return ProcessResult(success: true, output: output)
            } else {
                return ProcessResult(success: false, output: output)
            }
        } catch {
            return ProcessResult(success: false, output: error.localizedDescription)
        }
    }
}
