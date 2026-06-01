import SwiftUI

/// 左侧 Sidebar 目录树视图
struct SidebarView: View {
    let fileTreeViewModel: FileTreeViewModel
    let appViewModel: AppViewModel
    @Environment(\.language) private var language

    var body: some View {
        VStack(spacing: 0) {
            // 顶部红绿灯占位区域（与 TitleBar 对齐 50px）
            HStack {
                Color.clear
                    .frame(width: appViewModel.trafficLightWidth, height: 50)
                Spacer()
            }

            Divider()

            // 目录树列表
            if fileTreeViewModel.isLoading {
                ProgressView(L10n.tr(.loading, language: language))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = fileTreeViewModel.errorMessage {
                ErrorView(message: error)
            } else if fileTreeViewModel.nodes.isEmpty {
                emptyDirectoryView
            } else {
                directoryTreeView
            }

            Divider()

            // 底部固定区域：Settings 按钮（参考 Buddy 底部固定设置入口）
            settingsButton
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    // MARK: - 目录树（使用 OutlineGroup 渲染嵌套结构）

    private var directoryTreeView: some View {
        List(selection: Binding<URL?>(
            get: { fileTreeViewModel.selectedFileURL },
            set: { url in
                if let url {
                    if let node = findNode(in: fileTreeViewModel.nodes, url: url) {
                        if node.isDirectory {
                            fileTreeViewModel.toggleExpand(url)
                        } else {
                            fileTreeViewModel.selectFile(node)
                        }
                    }
                }
            }
        )) {
            OutlineGroup(
                fileTreeViewModel.nodes,
                children: \.children
            ) { node in
                FileRowView(node: node, fileTreeViewModel: fileTreeViewModel)
                    .tag(node.path)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .focusable()
        .onMoveCommand { direction in
            switch direction {
            case .up:
                _ = fileTreeViewModel.moveSelection(direction: -1)
            case .down:
                _ = fileTreeViewModel.moveSelection(direction: 1)
            default:
                break
            }
        }
        .onKeyPress(.return) {
            if let url = fileTreeViewModel.selectedFileURL,
               let node = findNode(in: fileTreeViewModel.nodes, url: url) {
                if node.isDirectory {
                    fileTreeViewModel.toggleExpand(url)
                } else {
                    fileTreeViewModel.selectFile(node)
                }
            }
            return .handled
        }
    }

    // MARK: - 空目录提示

    private var emptyDirectoryView: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(L10n.tr(.emptyDirectoryMessage, language: language))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 底部设置按钮

    private var settingsButton: some View {
        Button {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Text(L10n.tr(.settingsTabGeneral, language: language))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L10n.tr(.sidebarSettings, language: language))
    }

    // MARK: - 辅助方法

    private func findNode(in nodes: [FileNode], url: URL) -> FileNode? {
        for node in nodes {
            if node.path == url { return node }
            if node.isDirectory, let children = node.children {
                if let found = findNode(in: children, url: url) {
                    return found
                }
            }
        }
        return nil
    }
}
