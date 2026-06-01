import SwiftUI
import UniformTypeIdentifiers

/// 自定义标题栏（50px），包含 Sidebar 切换、文件名、渲染/原文 Picker、Open 按钮
struct TitleBarView: View {
    let appViewModel: AppViewModel
    let documentViewModel: DocumentViewModel
    @Environment(\.language) private var language

    var body: some View {
        HStack(spacing: 0) {
            // 左侧：红绿灯占位 + Sidebar 切换按钮
            trafficLightsAndSidebarToggle

            // 中间：文件名（作为拖拽区域的一部分）
            Text(documentViewModel.hasDocument ? documentViewModel.fileName : L10n.tr(.appName, language: language))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 8)

            Spacer()

            // 右侧：渲染/原文切换 + Open 按钮
            rightControls
        }
        .frame(height: 50)
        .padding(.horizontal, 12)
        .background(WindowDragArea())
    }

    // MARK: - 左侧控件

    private var trafficLightsAndSidebarToggle: some View {
        HStack(spacing: 8) {
            // 红绿灯占位（Sidebar 可见时在 Sidebar 区域，不可见时在 TitleBar 左侧）
            Color.clear
                .frame(width: appViewModel.isSidebarVisible ? 0 : appViewModel.trafficLightWidth, height: 20)

            // Sidebar 切换按钮（单文件模式下禁用）
            Button {
                appViewModel.toggleSidebar()
            } label: {
                Image(systemName: "sidebar.leading")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(L10n.tr(.titleBarToggleSidebar, language: language))
            .disabled(appViewModel.isSingleFileMode)
            .opacity(appViewModel.isSingleFileMode ? 0.3 : 1)
        }
    }

    // MARK: - 右侧控件

    private var rightControls: some View {
        HStack(spacing: 12) {
            // 渲染/原文切换
            Picker(L10n.tr(.titleBarDisplayMode, language: language), selection: Binding(
                get: { documentViewModel.displayMode },
                set: { documentViewModel.switchDisplayMode($0) }
            )) {
                Text(L10n.tr(.displayModeRendered, language: language)).tag(DisplayMode.rendered)
                Text(L10n.tr(.displayModeSource, language: language)).tag(DisplayMode.source)
            }
            .pickerStyle(.segmented)
            .frame(width: 140)
            .disabled(!documentViewModel.hasDocument)

            // Open 按钮
            Button {
                openPanel()
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(L10n.tr(.titleBarOpen, language: language))
        }
    }

    // MARK: - 方法

    /// 打开面板，支持选择目录和 .md 文件
    private func openPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.tr(.open, language: language)
        panel.allowedContentTypes = [.folder, UTType(filenameExtension: "md")].compactMap { $0 }

        if panel.runModal() == .OK, let url = panel.url {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)

            if isDir.boolValue {
                appViewModel.openDirectory(url)
            } else {
                appViewModel.openSingleFile(url)
                NotificationCenter.default.post(name: .openFile, object: url)
            }
        }
    }
}

// MARK: - 窗口拖拽区域

/// NSViewRepresentable 用于将 TitleBar 区域标记为窗口拖拽区域
/// 在 .hiddenTitleBar 模式下，需要手动指定可拖拽区域来移动窗口
private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = DragAreaView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    /// 自定义 NSView，其区域可作为窗口拖拽区域
    private final class DragAreaView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}
