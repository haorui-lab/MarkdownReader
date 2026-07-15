# MarkdownReader Multi-Window Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将 MarkdownReader 实现为 Word 式多窗口应用，使窗口状态、命令、文件所有权、Undo、面板和生命周期彼此隔离。

**Architecture:** 使用 data-driven `WindowGroup<WindowID>` 生成稳定窗口身份；应用级 `WindowCoordinator` 维护 session registry 和 resource ownership registry；每个 `WindowSession` 持有独立 ViewModel/Undo 状态；菜单通过 `FocusedValues` 路由到活动窗口。外部打开、Open Recent、打开面板、拖拽和 Markdown 链接统一进入 Coordinator。

**Tech Stack:** Swift 6.2、SwiftUI（macOS 26）、AppKit、Observation `@Observable`、Swift Concurrency、Swift Package Manager、XCTest。

---

## 执行前提

- 需求文档：`docs/multi-window-requirements.md`
- 技术设计：`docs/plans/2026-07-14-multi-window-design.md`
- 必须在独立 worktree/feature branch 中执行，建议分支：`codex/multi-window`。
- 开始前运行 `git status --short`，确认并保留用户已有修改。
- 每个任务遵守 red → green → refactor；不得先删除现有单窗口保护再补路由。
- 每完成一个任务运行该任务测试；每个阶段结束运行 `swift test` 和 `swift build`。
- 计划中的 commit 是建议检查点；只有执行者获得提交授权时才实际提交。

## Task 1：建立测试目标与基线

**Files:**

- Modify: `Package.swift`
- Create: `Tests/MarkdownReaderTests/TestSupport/TemporaryDirectory.swift`
- Create: `Tests/MarkdownReaderTests/SmokeTests.swift`

### Step 1：先验证当前基线

Run:

```bash
swift build
```

Expected: exit 0。

### Step 2：在 `Package.swift` 添加测试目标

在 `targets` 数组末尾加入：

```swift
.testTarget(
    name: "MarkdownReaderTests",
    dependencies: ["MarkdownReader"],
    path: "Tests/MarkdownReaderTests"
)
```

### Step 3：添加最小 smoke test

```swift
import XCTest
@testable import MarkdownReader

final class SmokeTests: XCTestCase {
    func testTestTargetLoadsApplicationModule() {
        XCTAssertTrue(true)
    }
}
```

`TemporaryDirectory` 提供 `setUp`/`tearDown` 可复用临时目录，并使用 `FileManager` 删除测试数据。

### Step 4：运行测试基线

Run:

```bash
swift test --filter SmokeTests
```

Expected: 1 test passed。

### Step 5：提交检查点

```bash
git add Package.swift Tests/MarkdownReaderTests
git commit -m "test: add MarkdownReader test target"
```

## Task 2：实现 WindowID 与资源身份规范化

**Files:**

- Create: `Sources/MarkdownReader/Models/WindowID.swift`
- Create: `Sources/MarkdownReader/Models/ResourceIdentity.swift`
- Create: `Sources/MarkdownReader/Services/ResourceIdentityService.swift`
- Create: `Tests/MarkdownReaderTests/ResourceIdentityServiceTests.swift`

### Step 1：编写失败测试

覆盖：

```swift
func testWindowIDRoundTripsThroughCodable()
func testDotDotAndStandardPathResolveToSameIdentity()
func testSymlinkAndDestinationResolveToSameIdentity()
func testFileAndDirectoryAtSamePathUseDifferentKinds()
func testMissingPathProducesStableIdentity()
```

关键断言示例：

```swift
let direct = try service.identity(for: target, kind: .file)
let linked = try service.identity(for: symlink, kind: .file)
XCTAssertEqual(direct, linked)
```

### Step 2：运行并确认失败

Run:

```bash
swift test --filter ResourceIdentityServiceTests
```

Expected: FAIL，缺少 `WindowID` / `ResourceIdentityService`。

### Step 3：实现最小模型

```swift
struct WindowID: Hashable, Codable, Sendable, Identifiable {
    let rawValue: UUID
    var id: UUID { rawValue }
    init(rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

struct ResourceIdentity: Hashable, Sendable {
    enum Kind: Hashable, Sendable { case file, directory }
    let kind: Kind
    let canonicalURL: URL
    let comparisonKey: String

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.kind == rhs.kind && lhs.comparisonKey == rhs.comparisonKey
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(kind)
        hasher.combine(comparisonKey)
    }
}
```

`ResourceIdentityService.identity(for:kind:)` 完成标准化、符号链接解析和卷大小写能力检测。不要在调用处复制规范化逻辑。

### Step 4：运行测试

Run:

```bash
swift test --filter ResourceIdentityServiceTests
```

Expected: all tests passed。

### Step 5：提交检查点

```bash
git add Sources/MarkdownReader/Models Sources/MarkdownReader/Services/ResourceIdentityService.swift Tests/MarkdownReaderTests/ResourceIdentityServiceTests.swift
git commit -m "feat: add window and resource identities"
```

## Task 3：建立纯路由引擎

**Files:**

- Create: `Sources/MarkdownReader/Models/OpenRequest.swift`
- Create: `Sources/MarkdownReader/Models/RouteDecision.swift`
- Create: `Sources/MarkdownReader/Services/WindowRoutingEngine.swift`
- Create: `Tests/MarkdownReaderTests/WindowRoutingEngineTests.swift`

### Step 1：编写失败测试

至少覆盖：

```swift
func testNewResourceReusesPreferredBlankSession()
func testNewResourceCreatesWindowWhenPreferredSessionIsOccupied()
func testOwnedFileActivatesOwner()
func testOwnedDirectoryActivatesOwner()
func testDuplicateURLsInOneRequestProduceOneDecision()
func testMultipleNewURLsReuseOneBlankThenCreateWindows()
func testOwnerConflictDoesNotReassignResource()
```

### Step 2：运行并确认失败

```bash
swift test --filter WindowRoutingEngineTests
```

Expected: FAIL，缺少路由类型。

### Step 3：实现纯状态与决策

```swift
struct SessionRoutingSnapshot: Equatable, Sendable {
    let id: WindowID
    let isBlank: Bool
}

struct WindowRoutingState: Sendable {
    var sessions: [WindowID: SessionRoutingSnapshot] = [:]
    var owners: [ResourceIdentity: WindowID] = [:]
}

struct WindowRoutingEngine: Sendable {
    func decision(
        for resource: ResourceIdentity,
        preferredWindowID: WindowID?,
        state: WindowRoutingState,
        makeWindowID: () -> WindowID = { WindowID() }
    ) -> RouteDecision
}
```

决策顺序必须固定：owner → preferred blank → 任意可复用 blank → create window。路由引擎不调用 AppKit/SwiftUI。

### Step 4：运行测试

```bash
swift test --filter WindowRoutingEngineTests
```

Expected: all tests passed。

### Step 5：提交检查点

```bash
git add Sources/MarkdownReader/Models/OpenRequest.swift Sources/MarkdownReader/Models/RouteDecision.swift Sources/MarkdownReader/Services/WindowRoutingEngine.swift Tests/MarkdownReaderTests/WindowRoutingEngineTests.swift
git commit -m "feat: add deterministic window routing engine"
```

## Task 4：实现 WindowCoordinator 注册表与所有权事务

**Files:**

- Create: `Sources/MarkdownReader/Services/WindowCoordinator.swift`
- Create: `Tests/MarkdownReaderTests/WindowCoordinatorTests.swift`
- Create: `Tests/MarkdownReaderTests/TestSupport/WindowSessionStub.swift`

### Step 1：编写失败测试

```swift
func testRegisterAndUnregisterSession()
func testClaimRejectsSecondOwner()
func testUnregisterReleasesAllOwnedResources()
func testMigrationMovesOwnershipAtomically()
func testMigrationConflictPreservesOldOwnership()
func testPendingRequestIsStoredByDestinationWindowID()
```

冲突回滚断言：

```swift
XCTAssertThrowsError(try coordinator.migrateOwnership(
    from: sourceURL,
    to: occupiedURL,
    for: windowA
))
XCTAssertEqual(coordinator.owner(of: sourceURL), windowA)
XCTAssertEqual(coordinator.owner(of: occupiedURL), windowB)
```

### Step 2：运行并确认失败

```bash
swift test --filter WindowCoordinatorTests
```

Expected: FAIL，缺少 Coordinator。

### Step 3：实现 Coordinator 核心

先实现不依赖真实 `NSWindow` 的部分：

```swift
@MainActor
@Observable
final class WindowCoordinator {
    private(set) var sessionSnapshots: [WindowID: SessionRoutingSnapshot] = [:]
    private(set) var resourceOwners: [ResourceIdentity: WindowID] = [:]
    private var ownedResources: [WindowID: Set<ResourceIdentity>] = [:]
    private var pendingResources: [WindowID: ResourceIdentity] = [:]
    private let identityService: ResourceIdentityService
    private let routingEngine: WindowRoutingEngine

    func claim(_ resource: ResourceIdentity, for windowID: WindowID) throws
    func migrateOwnership(from: URL, to: URL, for windowID: WindowID) throws
    func unregister(windowID: WindowID)
}
```

所有写入都在 `@MainActor` 完成。迁移先预检目标 owner，再更新两个字典；任何失败不得修改原状态。

### Step 4：运行测试

```bash
swift test --filter WindowCoordinatorTests
```

Expected: all tests passed。

### Step 5：提交检查点

```bash
git add Sources/MarkdownReader/Services/WindowCoordinator.swift Tests/MarkdownReaderTests
git commit -m "feat: add window coordinator and ownership registry"
```

## Task 5：引入 WindowSession 并迁移 ContentView 所有权

**Files:**

- Create: `Sources/MarkdownReader/ViewModels/WindowSession.swift`
- Create: `Tests/MarkdownReaderTests/WindowSessionTests.swift`
- Modify: `Sources/MarkdownReader/Views/ContentView.swift:6-100`
- Modify: `Sources/MarkdownReader/ViewModels/CommandPaletteViewModel.swift:41-63`

### Step 1：编写失败测试

```swift
func testSessionStartsBlank()
func testSessionWiresFileTreeToDocumentViewModel()
func testSessionDisposeClearsOnlyItsOwnDocumentState()
func testOwnerConflictLeavesSelectionUnchanged()
```

### Step 2：运行并确认失败

```bash
swift test --filter WindowSessionTests
```

Expected: FAIL，缺少 `WindowSession`。

### Step 3：创建 WindowSession

```swift
@MainActor
@Observable
final class WindowSession {
    let id: WindowID
    let appViewModel: AppViewModel
    let fileTreeViewModel: FileTreeViewModel
    let documentViewModel: DocumentViewModel
    let commandPaletteViewModel: CommandPaletteViewModel
    weak var coordinator: WindowCoordinator?
    weak var window: NSWindow?

    init(
        id: WindowID,
        settings: SettingsModel = .shared,
        coordinator: WindowCoordinator
    ) {
        self.id = id
        self.appViewModel = AppViewModel()
        self.fileTreeViewModel = FileTreeViewModel(settings: settings)
        self.documentViewModel = DocumentViewModel(settings: settings)
        self.commandPaletteViewModel = CommandPaletteViewModel()
        self.coordinator = coordinator
        self.fileTreeViewModel.documentViewModel = documentViewModel
        self.commandPaletteViewModel.configure(
            appViewModel: appViewModel,
            fileTreeViewModel: fileTreeViewModel,
            documentViewModel: documentViewModel,
            settings: settings
        )
    }
}
```

### Step 4：让 ContentView 接收 session

删除 `ContentView` 自行创建的四个主 `@State`，改为：

```swift
struct ContentView: View {
    let session: WindowSession

    private var appViewModel: AppViewModel { session.appViewModel }
    private var fileTreeViewModel: FileTreeViewModel { session.fileTreeViewModel }
    private var documentViewModel: DocumentViewModel { session.documentViewModel }
    private var commandPaletteViewModel: CommandPaletteViewModel { session.commandPaletteViewModel }
}
```

保留 `themeColors` 等纯窗口 UI state。删除 `.task` 中重复的 ViewModel 连接代码。

### Step 5：运行测试与构建

```bash
swift test --filter WindowSessionTests
swift build
```

Expected: tests passed；build exit 0；现有单窗口行为不变。

### Step 6：提交检查点

```bash
git add Sources/MarkdownReader/ViewModels/WindowSession.swift Sources/MarkdownReader/Views/ContentView.swift Sources/MarkdownReader/ViewModels/CommandPaletteViewModel.swift Tests/MarkdownReaderTests/WindowSessionTests.swift
git commit -m "refactor: introduce window session boundary"
```

## Task 6：切换到 data-driven WindowGroup

**Files:**

- Create: `Sources/MarkdownReader/Views/WindowSceneHost.swift`
- Create: `Sources/MarkdownReader/Views/WindowLifecycleBridge.swift`
- Modify: `Sources/MarkdownReader/App/MarkdownReaderApp.swift:6-142`
- Modify: `Sources/MarkdownReader/App/AppDelegate.swift:16-252`
- Create: `Tests/MarkdownReaderTests/WindowLifecycleRegistryTests.swift`

### Step 1：为生命周期注册编写失败测试

```swift
func testRegisterMakesSessionAvailable()
func testWindowCloseUnregistersAndReleasesResources()
func testSameWindowIDIsNotRegisteredTwice()
```

### Step 2：运行并确认失败

```bash
swift test --filter WindowLifecycleRegistryTests
```

### Step 3：实现 WindowSceneHost

```swift
struct WindowSceneHost: View {
    let windowID: WindowID
    let coordinator: WindowCoordinator
    @Environment(\.openWindow) private var openWindow
    @State private var session: WindowSession

    init(windowID: WindowID, coordinator: WindowCoordinator) {
        self.windowID = windowID
        self.coordinator = coordinator
        _session = State(initialValue: WindowSession(
            id: windowID,
            coordinator: coordinator
        ))
    }

    var body: some View {
        ContentView(session: session)
            .background(WindowLifecycleBridge(session: session))
            .task {
                coordinator.install(openWindowAction: openWindow)
                coordinator.register(session: session, window: session.window)
                await coordinator.consumePendingResource(for: windowID)
            }
    }
}
```

### Step 4：替换 Scene

```swift
WindowGroup(
    "Markdown Reader",
    id: WindowSceneID.document,
    for: WindowID.self
) { $windowID in
    WindowSceneHost(windowID: windowID, coordinator: windowCoordinator)
} defaultValue: {
    WindowID()
}
.restorationBehavior(.disabled)
```

保留现有单窗口守卫到本任务人工验证前；确认两个合法窗口能独立创建后再在同一任务末尾删除 `enforceSingleWindow` 注册和实现，防止新旧行为同时存在。

### Step 5：添加 New Window 临时入口并人工验证

使用 Coordinator 调用：

```swift
openWindow(id: WindowSceneID.document, value: WindowID())
```

验证两个空白窗口不会互相关闭，标题和自定义红绿灯正常。

### Step 6：运行验证

```bash
swift test --filter WindowLifecycleRegistryTests
swift test
swift build
```

Expected: all tests passed；build exit 0。

### Step 7：提交检查点

```bash
git add Sources/MarkdownReader/App Sources/MarkdownReader/Views/WindowSceneHost.swift Sources/MarkdownReader/Views/WindowLifecycleBridge.swift Tests/MarkdownReaderTests/WindowLifecycleRegistryTests.swift
git commit -m "feat: create data-driven document windows"
```

## Task 7：用 FocusedValues 替换窗口级菜单广播

**Files:**

- Create: `Sources/MarkdownReader/App/MarkdownReaderCommands.swift`
- Create: `Sources/MarkdownReader/Models/WindowCommand.swift`
- Create: `Sources/MarkdownReader/ViewModels/WindowCommandTarget.swift`
- Modify: `Sources/MarkdownReaderKit/Models/DisplayMode.swift`
- Modify: `Sources/MarkdownReader/App/MarkdownReaderApp.swift:143-270`
- Modify: `Sources/MarkdownReader/Views/WindowSceneHost.swift`
- Modify: `Sources/MarkdownReader/Views/ContentView.swift:420-970`
- Modify: `Sources/MarkdownReader/Views/DetailView.swift:100-118, 647-654`
- Modify: `Sources/MarkdownReader/Views/WebViewMarkdownView.swift:186-193`
- Create: `Tests/MarkdownReaderTests/WindowCommandTargetTests.swift`

### Step 1：编写失败测试

```swift
func testCommandTargetsOnlyBoundSession()
func testSaveCommandDoesNotReachOtherSession()
func testTargetBecomesNoOpAfterSessionDisposal()
```

### Step 2：运行并确认失败

```bash
swift test --filter WindowCommandTargetTests
```

### Step 3：实现 command target 与 FocusedValues

先让命令关联值满足 Swift 6 Sendable 检查：

```swift
public enum DisplayMode: String, CaseIterable, Sendable {
    case rendered = "渲染"
    case raw = "编辑"
}
```

```swift
@MainActor
final class WindowCommandTarget {
    weak var session: WindowSession?
    func perform(_ command: WindowCommand) { session?.perform(command) }
    func openBlankWindow() { session?.coordinator?.openBlankWindow() }
}

extension FocusedValues {
    @Entry var windowCommandTarget: WindowCommandTarget?
}
```

在 `WindowSceneHost` 发布：

```swift
.focusedSceneValue(\.windowCommandTarget, session.commandTarget)
```

### Step 4：迁移菜单

把 `MarkdownReaderApp` 内所有窗口级 `NotificationCenter.default.post` 改为 `MarkdownReaderCommands` 的 focused target 调用。应用级 About、更新、清除最近记录保留应用服务调用。

窗口级命令列表必须覆盖：new/save/saveAs/export/reload/sidebar/outline/settings/palette/display mode/zoom/find/close/minimize/window zoom。

### Step 5：迁移视图监听器

- `DetailView` 提供 reload/export/find command handler 给 session。
- `WebViewMarkdownView` 提供 zoom handler 给 session。
- 删除对应无目标的 `.onReceive`。
- `DocumentViewModel.save()` 返回明确结果，不再 post `.saveAsFile`。

### Step 6：静态检查遗漏

Run:

```bash
rg -n "NotificationCenter.default.(post|publisher).*\.(saveFile|saveAsFile|exportPDF|reloadFile|zoomIn|zoomOut|zoomReset|findInDocument|findNext|findPrevious|findAndReplace|toggleSidebar|switchToRendered|switchToRaw|toggleSettings|toggleCommandPalette)" Sources/MarkdownReader
```

Expected: no matches。

### Step 7：运行验证

```bash
swift test --filter WindowCommandTargetTests
swift test
swift build
```

### Step 8：提交检查点

```bash
git add Sources/MarkdownReader/App Sources/MarkdownReader/Models/WindowCommand.swift Sources/MarkdownReader/ViewModels Sources/MarkdownReader/Views Sources/MarkdownReaderKit/Models/DisplayMode.swift Tests/MarkdownReaderTests/WindowCommandTargetTests.swift
git commit -m "refactor: route commands to focused window"
```

## Task 8：统一 OpenPanel、Open Recent 与外部多 URL 路由

**Files:**

- Modify: `Sources/MarkdownReader/Services/OpenPanelHelper.swift`
- Modify: `Sources/MarkdownReader/App/AppDelegate.swift:60-198, 228-252`
- Modify: `Sources/MarkdownReader/App/MarkdownReaderApp.swift:45-105`
- Modify: `Sources/MarkdownReader/ViewModels/CommandPaletteViewModel.swift:82-146, 375-391`
- Modify: `Sources/MarkdownReader/Views/SidebarView.swift:32-47`
- Modify: `Sources/MarkdownReader/Services/CommandLineService.swift`
- Modify: `Sources/MarkdownReader/Services/WindowCoordinator.swift`
- Create: `Tests/MarkdownReaderTests/OpenRequestRoutingTests.swift`

### Step 1：编写失败测试

```swift
func testColdStartRequestWinsOverRestoreRequest()
func testAllExternalURLsAreQueued()
func testFirstURLReusesBlankAndSecondCreatesWindow()
func testOpenRecentActivatesExistingOwner()
func testMissingURLDoesNotBlockFollowingURLs()
func testNoVisibleWindowCreatesOrReopensCorrectWindow()
```

### Step 2：运行并确认失败

```bash
swift test --filter OpenRequestRoutingTests
```

### Step 3：把 OpenPanel 改为目标窗口 sheet

实现：

```swift
@MainActor
static func chooseResource(
    for window: NSWindow,
    language: Language
) async -> URL?
```

使用 `beginSheetModal(for:)` 和 checked continuation。删除全局 `isPanelShowing`，由 session 维护面板状态。

### Step 4：收缩 AppDelegate

- `application(_:open:)` 传递完整 `[URL]`。
- Coordinator 未 attach 时在 AppDelegate 内存队列暂存。
- attach 后一次性 drain。
- 删除 `pendingOpenFilePath` / `pendingOpenDirectoryPath` UserDefaults。
- 删除固定 0.5 秒启动延迟。
- `applicationShouldHandleReopen` 调用 Coordinator，不再激活任意第一个窗口。

### Step 5：迁移所有打开入口

- Open Recent → `coordinator.enqueue(OpenRequest(..., source: .openRecent))`
- Sidebar Open → 当前 session `openFromPanel()`
- Command Palette → session `requestFileSelection` 或 Coordinator
- CLI → 保留全部路径，不截断
- `.onOpenURL` 安全网 → Coordinator，并依靠 request ID/identity 幂等去重

### Step 6：运行验证

```bash
swift test --filter OpenRequestRoutingTests
swift test
swift build
```

### Step 7：提交检查点

```bash
git add Sources/MarkdownReader/App Sources/MarkdownReader/Services Sources/MarkdownReader/ViewModels/CommandPaletteViewModel.swift Sources/MarkdownReader/Views/SidebarView.swift Tests/MarkdownReaderTests/OpenRequestRoutingTests.swift
git commit -m "feat: centralize resource opening and external events"
```

## Task 9：实现目录树所有权冲突与窗口标识

**Files:**

- Modify: `Sources/MarkdownReader/ViewModels/WindowSession.swift`
- Modify: `Sources/MarkdownReader/ViewModels/DocumentViewModel.swift:102-112, 134-260, 338-544, 640-745`
- Modify: `Sources/MarkdownReader/Views/SidebarView.swift:80-230`
- Modify: `Sources/MarkdownReader/Views/FileRowView.swift`
- Modify: `Sources/MarkdownReaderKit/Services/LocalizationService.swift`
- Create: `Tests/MarkdownReaderTests/FileOwnershipSelectionTests.swift`

### Step 1：编写失败测试，覆盖用户确认场景

```swift
func testDirectorySelectionActivatesStandaloneOwner()
func testOwnerConflictKeepsDirectorySelectionUnchanged()
func testOwnerConflictDoesNotLoadDocument()
func testClosingOwnerAllowsDirectoryWindowToSelectFile()
func testRowMarksFileOwnedByAnotherWindow()
```

关键测试：

```swift
let previous = directorySession.fileTreeViewModel.selectedFileURL
directorySession.requestFileSelection(aURL)
XCTAssertEqual(directorySession.fileTreeViewModel.selectedFileURL, previous)
XCTAssertEqual(activator.activatedWindowID, standaloneSession.id)
```

### Step 2：运行并确认失败

```bash
swift test --filter FileOwnershipSelectionTests
```

### Step 3：暴露 ownedFileURLs

`DocumentViewModel` 提供只读集合，包含 current URL、content cache、display mode cache、disk snapshot 和 undo store 仍持有的 URL。所有集合变化后通知 session 同步 ownership diff。

### Step 4：选择前路由

把 Sidebar、键盘导航、Command Palette、Markdown link 所有会写 `selectedFileURL` 的用户路径改为先调用：

```swift
session.requestFileSelection(url)
```

只有 `.openInSession` 才能真正赋值。

### Step 5：增加文件行标识

`FileRowView` 增加 `isOpenInAnotherWindow`。为 true 时显示 `macwindow`，并使用 L10n 三语 tooltip/accessibility label。不得使用行高变化造成目录树抖动。

### Step 6：运行验证

```bash
swift test --filter FileOwnershipSelectionTests
swift test
swift build
```

### Step 7：提交检查点

```bash
git add Sources/MarkdownReader/ViewModels Sources/MarkdownReader/Views/SidebarView.swift Sources/MarkdownReader/Views/FileRowView.swift Sources/MarkdownReaderKit/Services/LocalizationService.swift Tests/MarkdownReaderTests/FileOwnershipSelectionTests.swift
git commit -m "feat: enforce single-window file ownership"
```

## Task 10：隔离 WindowUndoStore

**Files:**

- Create: `Sources/MarkdownReader/Services/WindowUndoStore.swift`
- Modify: `Sources/MarkdownReader/Views/SyntaxHighlightedEditor.swift:100-240, 330-380`
- Modify: `Sources/MarkdownReader/Views/WindowLifecycleBridge.swift`
- Modify: `Sources/MarkdownReader/ViewModels/DocumentViewModel.swift`
- Modify: `Sources/MarkdownReader/ViewModels/WindowSession.swift`
- Create: `Tests/MarkdownReaderTests/WindowUndoStoreTests.swift`

### Step 1：编写失败测试

```swift
func testTwoStoresReturnDifferentManagersForSameURL()
func testSwitchingFileChangesOnlyOneStoreActiveManager()
func testMigrationMovesManagerToNewURL()
func testRemovingOneStoreActionsDoesNotClearOtherStore()
```

### Step 2：运行并确认失败

```bash
swift test --filter WindowUndoStoreTests
```

### Step 3：实现 WindowUndoStore

实现 `manager(for:)`、`switchFile(to:)`、`migrate(from:to:)`、`remove(for:)`、`removeAllActions()`。每个 `WindowSession` 创建一个 store。

### Step 4：移除全局 active undo

- 删除 `_activePerFileUndoManager`。
- 删除 `UndoManagerProvider.shared`。
- 使用 Objective-C associated object 将 store 绑定到具体 `NSWindow`。
- swizzled `NSWindow.undoManager` getter 读取 `self` 的 store。
- NSTextView delegate 从 session store 返回同一 manager。
- 编辑器 deinit 只清理其文件或所属 store，不清理其他窗口。

### Step 5：运行测试与双窗口人工验证

```bash
swift test --filter WindowUndoStoreTests
swift test
swift build
```

人工：窗口 A/B 分别编辑不同文件，交替按 Cmd+Z；不得跨窗口撤销。

### Step 6：提交检查点

```bash
git add Sources/MarkdownReader/Services/WindowUndoStore.swift Sources/MarkdownReader/Views/SyntaxHighlightedEditor.swift Sources/MarkdownReader/Views/WindowLifecycleBridge.swift Sources/MarkdownReader/ViewModels Tests/MarkdownReaderTests/WindowUndoStoreTests.swift
git commit -m "fix: isolate undo history by window session"
```

## Task 11：隔离保存面板、PDF、拖拽与红绿灯

**Files:**

- Modify: `Sources/MarkdownReader/Services/OpenPanelHelper.swift`
- Modify: `Sources/MarkdownReader/Services/PDFExportService.swift`
- Modify: `Sources/MarkdownReader/Views/DetailView.swift`
- Modify: `Sources/MarkdownReader/Views/TrafficLightButtons.swift`
- Modify: `Sources/MarkdownReader/App/AppDelegate.swift:254-384`
- Modify: `Sources/MarkdownReader/Views/WindowLifecycleBridge.swift`
- Create: `Tests/MarkdownReaderTests/WindowScopedActionTests.swift`

### Step 1：编写失败测试

使用可注入 action recorder 覆盖：

```swift
func testTrafficLightsOperateOwningWindow()
func testDropCallbackCarriesTargetWindowID()
func testUnsupportedDropUpdatesOnlyTargetSession()
func testExportCommandReachesOnlyTargetSession()
```

### Step 2：运行并确认失败

```bash
swift test --filter WindowScopedActionTests
```

### Step 3：改造红绿灯

`TrafficLightButtons` 接收所属 `NSWindow` 或 `WindowCommandTarget`，关闭使用 `performClose`，最小化/缩放直接操作该窗口。删除 `NSApp.keyWindow` 依赖。

### Step 4：改造拖拽 overlay

`FileDropOverlayView` 构造时接收 session callbacks；hover、open、unsupported 不再发全局通知。overlay 由每个 `WindowLifecycleBridge` 安装和移除。

### Step 5：改造保存/PDF 面板

- 另存为、PDF 导出使用所属窗口 `beginSheetModal`。
- `PDFExportService` 的 offscreen window 不注册为文档窗口。
- 前一个 key window 恢复逻辑改为显式目标窗口，不从全局推断。

### Step 6：运行验证

```bash
swift test --filter WindowScopedActionTests
swift test
swift build
```

### Step 7：提交检查点

```bash
git add Sources/MarkdownReader/Services Sources/MarkdownReader/Views Sources/MarkdownReader/App/AppDelegate.swift Tests/MarkdownReaderTests/WindowScopedActionTests.swift
git commit -m "refactor: scope panels and appkit actions to windows"
```

## Task 12：完成窗口关闭、Dock 重开与应用退出协调

**Files:**

- Create: `Sources/MarkdownReader/Services/ApplicationTerminationCoordinator.swift`
- Modify: `Sources/MarkdownReader/Views/WindowLifecycleBridge.swift`
- Modify: `Sources/MarkdownReader/Views/ContentView.swift:1067-1158`
- Modify: `Sources/MarkdownReader/App/AppDelegate.swift`
- Modify: `Sources/MarkdownReader/Services/WindowCoordinator.swift`
- Create: `Tests/MarkdownReaderTests/ApplicationTerminationCoordinatorTests.swift`

### Step 1：编写失败测试

```swift
func testCloseOneSessionDoesNotDisposeOtherSession()
func testDontSaveDiscardsOnlyOwningUntitled()
func testCancelStopsWindowClose()
func testQuitVisitsEveryDirtyUntitledSession()
func testCancelInAnySessionCancelsQuit()
func testDockReopenCreatesOneBlankWindow()
```

### Step 2：运行并确认失败

```bash
swift test --filter ApplicationTerminationCoordinatorTests
```

### Step 3：统一 close decision

```swift
enum CloseDecision: Equatable, Sendable {
    case close
    case needsUntitledDecision
    case cancel
}
```

`WindowLifecycleBridge.windowShouldClose` 只询问所属 session。`windowWillClose` 调用 `dispose` 和 `coordinator.unregister`。

### Step 4：实现应用退出状态机

`applicationShouldTerminate` 返回 `.terminateLater`，TerminationCoordinator 串行处理所有 dirty Untitled session，最后调用：

```swift
NSApp.reply(toApplicationShouldTerminate: shouldTerminate)
```

任意取消立即停止，不得重复弹同一面板。

### Step 5：实现 Dock 重开

- 有可见窗口：前置最后活动窗口。
- 无可见窗口：Coordinator 创建一个 blank window。
- AppDelegate 返回 false，阻止系统再创建一份。

### Step 6：运行验证

```bash
swift test --filter ApplicationTerminationCoordinatorTests
swift test
swift build
```

### Step 7：提交检查点

```bash
git add Sources/MarkdownReader/Services/ApplicationTerminationCoordinator.swift Sources/MarkdownReader/Services/WindowCoordinator.swift Sources/MarkdownReader/Views/WindowLifecycleBridge.swift Sources/MarkdownReader/Views/ContentView.swift Sources/MarkdownReader/App/AppDelegate.swift Tests/MarkdownReaderTests/ApplicationTerminationCoordinatorTests.swift
git commit -m "feat: coordinate multi-window close and termination"
```

## Task 13：将更新、预热和最后位置恢复提升到应用级

**Files:**

- Create: `Sources/MarkdownReader/Services/WebViewWarmupService.swift`
- Create: `Sources/MarkdownReader/Services/AppStartupCoordinator.swift`
- Modify: `Sources/MarkdownReader/App/MarkdownReaderApp.swift:6-140`
- Modify: `Sources/MarkdownReader/Models/SettingsModel.swift`
- Modify: `Sources/MarkdownReader/ViewModels/UpdateViewModel.swift`
- Modify: `Sources/MarkdownReader/Views/WindowSceneHost.swift`
- Create: `Tests/MarkdownReaderTests/AppStartupCoordinatorTests.swift`

### Step 1：编写失败测试

```swift
func testWarmupRunsOnceAcrossMultipleWindowRegistrations()
func testAutomaticUpdateCheckRunsOnce()
func testExternalOpenSuppressesRestoreLastLocation()
func testOnlyLastActiveWindowUpdatesLastLocation()
func testNormalLaunchRestoresAtMostOneWindow()
```

### Step 2：运行并确认失败

```bash
swift test --filter AppStartupCoordinatorTests
```

### Step 3：实现幂等应用服务

`WebViewWarmupService` 使用状态枚举 `.idle/.warming/.ready`；`warmUpIfNeeded()` 幂等。Update 自动检查由 `AppStartupCoordinator` 在 launch barrier 后调用一次。

### Step 4：实现启动优先级

```text
pending external URLs
    > restore last active location
    > blank default window
```

删除 ContentView/每窗口 `.task` 中的更新检查和 WebView 预热。

### Step 5：限制 last opened 写入

只有 Coordinator 记录的 active session 可以更新 `lastOpenedFile` / `lastOpenedDirectory`。后台窗口加载、关闭或文件监控不得覆盖。

### Step 6：运行验证

```bash
swift test --filter AppStartupCoordinatorTests
swift test
swift build
```

### Step 7：提交检查点

```bash
git add Sources/MarkdownReader/Services/WebViewWarmupService.swift Sources/MarkdownReader/Services/AppStartupCoordinator.swift Sources/MarkdownReader/App/MarkdownReaderApp.swift Sources/MarkdownReader/Models/SettingsModel.swift Sources/MarkdownReader/ViewModels/UpdateViewModel.swift Sources/MarkdownReader/Views/WindowSceneHost.swift Tests/MarkdownReaderTests/AppStartupCoordinatorTests.swift
git commit -m "refactor: move startup services to app scope"
```

## Task 14：清理旧单窗口逻辑并完成文档与全量回归

**Files:**

- Modify: `Sources/MarkdownReader/App/AppDelegate.swift`
- Modify: `Sources/MarkdownReader/App/MarkdownReaderApp.swift`
- Modify: `Sources/MarkdownReader/Views/ContentView.swift`
- Modify: `Sources/MarkdownReader/Views/DetailView.swift`
- Modify: `Sources/MarkdownReader/Views/WebViewMarkdownView.swift`
- Modify: `Sources/MarkdownReader/Services/OpenPanelHelper.swift`
- Modify: `Sources/MarkdownReader/Views/SyntaxHighlightedEditor.swift`
- Modify: `docs/requirements.md`
- Modify: `docs/architecture.md`
- Modify: `docs/design.md`
- Modify: `CHANGELOG.md`
- Create: `docs/releases/release-notes-v<target>.md`

### Step 1：运行现有回归保护

```bash
swift test
swift build
```

Expected: all tests passed；build exit 0。若失败，先修复当前阶段问题，不得在红灯状态继续删除旧安全网。

### Step 2：删除失效机制

删除：

- `enforceSingleWindow` 及 observer；
- `activateFirstHiddenWindow`；
- `SingleWindow.hasMultipleMainWindows`；
- pending open UserDefaults keys；
- `_activePerFileUndoManager` / `UndoManagerProvider.shared`；
- `OpenPanelHelper.isPanelShowing`；
- 已迁移的窗口级 Notification.Name 和监听器；
- 任何以 `NSApp.windows.first` 或 `NSApp.keyWindow` 推断目标文档窗口的逻辑。

### Step 3：运行静态审计

```bash
rg -n "enforceSingleWindow|activateFirstHiddenWindow|SingleWindow|pendingOpen(File|Directory)Path|_activePerFileUndoManager|UndoManagerProvider.shared|isPanelShowing" Sources
rg -n "NotificationCenter.default.(post|publisher)" Sources/MarkdownReader
rg -n "NSApp.(keyWindow|windows)" Sources/MarkdownReader
```

Expected:

- 第一条无匹配；
- 后两条每个剩余匹配都有明确应用级或目标窗口理由，并在代码注释说明。

### Step 4：更新文档

- `docs/requirements.md`：移除单窗口约束，加入 MW 状态。
- `docs/architecture.md`：记录 WindowCoordinator/WindowSession/FocusedValues。
- `docs/design.md`：记录 New Window、Window 菜单和冲突标识。
- `CHANGELOG.md` 和 release notes：记录行为变化与系统要求。

### Step 5：运行完整自动验证

```bash
swift test
swift build
swift build -c release
git diff --check
```

Expected: all tests passed；三个构建/检查命令 exit 0。

### Step 6：执行人工回归矩阵

逐项记录结果：

1. `Cmd+Shift+N` 连续创建 5 个窗口。
2. 两窗口分别打开不同目录并独立切换、缩放、查找。
3. 单文件窗口 A 打开 `A.md`；目录窗口点击 `A.md`：目录选择不变，A 窗口前置。
4. 关闭 A 窗口后，目录窗口能正常选中 `A.md`。
5. Finder 冷启动单文件、多文件。
6. Finder 热启动有窗口、无可见窗口、目标窗口最小化。
7. Open Recent 重复文件只激活 owner。
8. 两窗口 Raw 编辑交替 Cmd+Z。
9. 两窗口分别打开/保存/导出 PDF，面板互不串扰。
10. 两个 dirty Untitled 退出，覆盖保存/不保存/取消。
11. 关闭最后窗口后通过 Dock、Finder、Open Recent 重开。
12. 20 次窗口创建/关闭循环，无重复 observer、僵尸窗口或崩溃。

### Step 7：提交最终检查点

```bash
git add Sources Tests Package.swift docs CHANGELOG.md
git commit -m "feat: support document-style multi-window workflows"
```

## 最终完成条件

- `MW-01`～`MW-15` 对应的 P0/P1 实现状态已在需求文档更新。
- `swift test`、debug build、release build 全部通过。
- 同一文件所有权、窗口命令、Undo、外部打开和退出协调均有自动化覆盖。
- 人工回归矩阵全部有结果，无跨窗口命令、保存面板、拖拽或状态污染。
- 旧单窗口守卫、全局 active undo 和窗口级广播通知已删除。
- 文档、CHANGELOG 和 release notes 已同步。
