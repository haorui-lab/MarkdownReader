import XCTest
@testable import MarkdownReader

/// 编辑器内容同步纯逻辑测试（任务 4）。
///
/// 直接测试生产代码中的 `EditorSyncPolicy`（由 `SyntaxHighlightedEditor.updateNSView`
/// 调用），避免维护两份判断逻辑。覆盖：同文件无版本变化且 first responder 允许回写、
/// contentVersion 变化强制覆盖、文件 URL 变化强制覆盖（即便 first responder）、
/// 新建 Untitled、连续两次相同临时 URL 不恢复旧内容。
@MainActor
final class SyntaxHighlightedEditorSyncTests: TemporaryDirectoryTestCase {

    private let identityService = ResourceIdentityService()

    // MARK: - 1. 同文件、无版本变化、编辑器为 first responder：允许编辑器回写

    func testSameFileNoVersionFirstResponderAllowsEditorWriteback() {
        let outcome = EditorSyncPolicy.outcome(
            contentDiffers: true,
            fileDidChange: false,
            contentVersionChanged: false,
            editorIsFirstResponder: true
        )
        XCTAssertEqual(outcome, .useEditor, "同文件无版本变化且 first responder 时应允许编辑器内容回写")
    }

    // MARK: - 2. contentVersion 变化：ViewModel 内容覆盖编辑器

    func testContentVersionChangeForcesViewModelOverride() {
        let outcome = EditorSyncPolicy.outcome(
            contentDiffers: true,
            fileDidChange: false,
            contentVersionChanged: true,
            editorIsFirstResponder: true
        )
        XCTAssertEqual(outcome, .useViewModel, "contentVersion 变化时必须用 ViewModel 内容覆盖，即便 first responder")
    }

    // MARK: - 3. 文件 URL 变化：即使编辑器是 first responder 仍由 ViewModel 覆盖

    func testFileURLChangeForcesViewModelOverrideEvenAsFirstResponder() {
        let outcome = EditorSyncPolicy.outcome(
            contentDiffers: true,
            fileDidChange: true,
            contentVersionChanged: false,
            editorIsFirstResponder: true
        )
        XCTAssertEqual(outcome, .useViewModel, "文件身份变化时必须用 ViewModel 内容覆盖，即便 first responder")
    }

    // MARK: - 3b. 非强制更新且非 first responder：用 ViewModel 覆盖

    func testNonForcedNonFirstResponderUsesViewModel() {
        let outcome = EditorSyncPolicy.outcome(
            contentDiffers: true,
            fileDidChange: false,
            contentVersionChanged: false,
            editorIsFirstResponder: false
        )
        XCTAssertEqual(outcome, .useViewModel, "非 first responder 时应用 ViewModel 内容覆盖编辑器")
    }

    // MARK: - 3c. 内容相同时：无操作意义，统一返回 useViewModel

    func testSameContentReturnsUseViewModel() {
        let outcome = EditorSyncPolicy.outcome(
            contentDiffers: false,
            fileDidChange: true,
            contentVersionChanged: true,
            editorIsFirstResponder: true
        )
        XCTAssertEqual(outcome, .useViewModel, "内容相同时无需写入，统一返回 useViewModel")
    }

    // MARK: - 4. 创建新 Untitled：最终内容为空 + 版本号递增

    func testCreateUntitledProducesEmptyContentAndBumpsVersion() {
        let vm = DocumentViewModel()
        let versionBefore = vm.contentVersion

        // 模拟此前加载过某文件（非空内容）
        vm.content = "# previous file"
        vm.currentFileURL = temporaryDirectory!.appendingPathComponent("old.md")

        let url = vm.createUntitledFile()

        XCTAssertEqual(vm.content, "", "新建 Untitled 内容必须为空")
        XCTAssertTrue(vm.isUntitled)
        XCTAssertNotNil(url)
        XCTAssertEqual(vm.contentVersion, versionBefore + 1, "createUntitledFile 必须递增 contentVersion")
    }

    // MARK: - 5. 连续两次相同临时 URL Untitled.md：第二次不恢复第一次或其他文件旧内容

    func testRepeatedUntitledDoesNotRestorePreviousContent() {
        let vm = DocumentViewModel()

        // 第一次 Untitled
        let firstURL = vm.createUntitledFile()
        XCTAssertEqual(vm.content, "")
        vm.content = "# first untitled edits"
        let versionAfterFirst = vm.contentVersion

        // 模拟用户丢弃并再次新建（createUntitledFile 在 isUntitled 时返回 nil，
        // 实际路径先 discardUntitledFile 再 createUntitledFile）
        vm.discardUntitledFile()
        let secondURL = vm.createUntitledFile()

        XCTAssertEqual(vm.content, "", "第二次新建 Untitled 不得恢复第一次或任何旧文件内容")
        // discard + create 两次都应递增版本号
        XCTAssertEqual(vm.contentVersion, versionAfterFirst + 2, "discard 与 create 应各递增一次 contentVersion")
        // 临时 URL 复用 Untitled.md，但内容来自 ViewModel 的空值，不读磁盘
        XCTAssertEqual(secondURL?.lastPathComponent, "Untitled.md")
        XCTAssertEqual(firstURL?.lastPathComponent, "Untitled.md")
        XCTAssertNotEqual(vm.content, "# first untitled edits")
    }
}
