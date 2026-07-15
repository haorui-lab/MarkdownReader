import Foundation

/// 应用启动协调器（Task 13）。
///
/// 把更新检查、WebView 预热、最后位置恢复提升到应用级，幂等执行一次。
/// 启动优先级：待处理外部 URL > 恢复上次位置 > 空白默认窗口。
@MainActor
final class AppStartupCoordinator {

    static let shared = AppStartupCoordinator()

    /// 启动屏障：确保应用级一次性服务只执行一次。
    private enum LaunchPhase: Sendable {
        case notStarted
        case started
    }

    private var phase: LaunchPhase = .notStarted
    private var didRunUpdateCheck = false
    private var didWarmup = false

    /// 是否已有待处理外部请求。由 AppDelegate/Coordinator 在冷启动入队前设置。
    var hasPendingExternalRequests: Bool = false

    private init() {}

    /// 启动屏障：应用级一次性服务（WebView 预热 + 更新检查）。
    /// 在第一个窗口注册后调用一次，幂等。
    func performAppLevelStartupOnce() {
        guard phase == .notStarted else { return }
        phase = .started

        // WebView 预热：幂等
        if !didWarmup {
            WebViewWarmupService.shared.warmUpIfNeeded()
            didWarmup = true
        }

        // 自动更新检查：延迟 2 秒，仅一次
        if !didRunUpdateCheck {
            didRunUpdateCheck = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                UpdateViewModel.shared.checkForUpdatesAutomatically()
            }
        }
    }

    /// 是否应在启动时恢复上次位置。
    /// 外部打开请求优先：有待处理外部 URL 时不恢复，避免覆盖。
    func shouldRestoreLastLocation() -> Bool {
        !hasPendingExternalRequests && SettingsModel.shared.reopenLastLocation
    }

    /// 测试用：重置状态。
    func resetForTesting() {
        phase = .notStarted
        didRunUpdateCheck = false
        didWarmup = false
        hasPendingExternalRequests = false
    }
}
