import SwiftUI

/// Git 视图模型，管理 Git 状态和操作
@MainActor
@Observable
final class GitViewModel {

    // MARK: - 状态

    /// 当前 Git 状态
    var gitStatus: GitService.GitStatus?

    /// 是否为 Git 仓库
    var isGitRepository: Bool = false

    /// 是否正在加载
    var isLoading: Bool = false

    /// 是否正在执行 commit+push
    var isCommitting: Bool = false

    /// 成功消息（如 "已提交并推送到 upstream（db7fba7）"）
    var successMessage: String?

    /// 错误消息
    var errorMessage: String?

    /// Commit 消息输入
    var commitMessage: String = ""

    // MARK: - 依赖

    private let gitService: GitService

    // MARK: - 初始化

    init(gitService: GitService = GitService()) {
        self.gitService = gitService
    }

    // MARK: - 方法

    /// 刷新 Git 状态
    func refreshStatus(directory: URL?) {
        guard let directory else {
            isGitRepository = false
            gitStatus = nil
            return
        }

        isLoading = true

        Task {
            let isRepo = gitService.isGitRepository(directory)
            isGitRepository = isRepo

            if isRepo {
                gitStatus = gitService.gitStatus(directory)
            } else {
                gitStatus = nil
            }

            isLoading = false
        }
    }

    /// 提交并推送
    func commitAndPush(directory: URL?) {
        guard let directory, isGitRepository else { return }

        let message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            errorMessage = "请输入提交消息"
            return
        }

        isCommitting = true
        errorMessage = nil
        successMessage = nil

        Task {
            let remote = gitService.remoteName(directory) ?? "origin"
            if let commitHash = gitService.commitAndPush(directory, message: message) {
                let shortHash = commitHash.prefix(7)
                successMessage = "已提交并推送到 \(remote)（\(shortHash)）"
                commitMessage = ""
                // 刷新状态
                refreshStatus(directory: directory)
            } else {
                errorMessage = "提交或推送失败，请检查是否有变更或网络连接"
            }
            isCommitting = false
        }
    }

    /// 清除成功消息
    func dismissSuccess() {
        successMessage = nil
    }

    /// 清除错误消息
    func dismissError() {
        errorMessage = nil
    }

    // MARK: - 便捷属性

    /// 当前分支名
    var branchName: String {
        gitStatus?.branch ?? "—"
    }

    /// 远程名
    var remoteName: String {
        gitStatus?.remote ?? "—"
    }

    /// 最新 commit hash
    var latestHash: String {
        gitStatus?.latestCommitHash ?? "—"
    }

    /// 变更文件总数
    var totalChangeCount: Int {
        (gitStatus?.stagedFiles.count ?? 0)
        + (gitStatus?.unstagedFiles.count ?? 0)
        + (gitStatus?.untrackedFiles.count ?? 0)
    }

    /// 是否有可提交的变更
    var hasChanges: Bool {
        guard let status = gitStatus else { return false }
        return !status.isClean
    }
}
