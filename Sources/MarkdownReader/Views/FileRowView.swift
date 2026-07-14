import SwiftUI
import MarkdownReaderKit

/// 目录树中单个文件/目录行视图
struct FileRowView: View {
    let node: FileNode
    let fileTreeViewModel: FileTreeViewModel
    let documentViewModel: DocumentViewModel
    /// Task 9：用于跨窗口所有权标记。
    let session: WindowSession
    @Environment(\.themeColors) private var themeColors
    @Environment(\.language) private var language

    /// 当前文件是否有未保存的修改
    private var isDirty: Bool {
        !node.isDirectory && documentViewModel.isFileDirty(at: node.path)
    }

    /// Task 9：该文件是否由「本窗口之外」的窗口持有。仅文件行判断。
    private var isOpenInAnotherWindow: Bool {
        guard !node.isDirectory else { return false }
        return session.coordinator?.isFileOwnedByAnotherWindow(node.path, besides: session.id) ?? false
    }

    var body: some View {
        HStack(spacing: 6) {
            if node.isDirectory {
                Image(systemName: "folder.fill")
                    .foregroundStyle(themeColors.ink)
                    .frame(width: 16)
            } else {
                Image(systemName: node.isMarkdown ? "doc.text" : "doc")
                    .foregroundStyle(node.isMarkdown ? themeColors.fgSecondary : themeColors.fgMuted)
                    .frame(width: 16)
            }

            Text(node.name)
                .foregroundStyle(node.isMarkdown || node.isDirectory ? themeColors.ink : themeColors.fgSecondary)
                .lineLimit(1)

            if isDirty {
                Text("*")
                    .foregroundStyle(themeColors.accent)
            }

            Spacer()

            // Task 9：跨窗口所有权标记。macwindow 图标 + 三语 tooltip/accessibility。
            // 不改变行高，避免目录树抖动。
            if isOpenInAnotherWindow {
                Image(systemName: "macwindow")
                    .font(.system(size: 10))
                    .foregroundStyle(themeColors.fgMuted)
                    .help(L10n.tr(.fileOwnedByAnotherWindow, language: language))
                    .accessibilityLabel(L10n.tr(.fileOwnedByAnotherWindow, language: language))
            }
        }
        .padding(.vertical, 4)
    }
}
