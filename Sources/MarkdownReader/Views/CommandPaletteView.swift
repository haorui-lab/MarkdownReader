import SwiftUI
import MarkdownReaderKit

/// CMD+P 命令面板视图
/// 在窗口标题栏下方横向居中弹出，包含搜索框和文件列表
struct CommandPaletteView: View {
    @Bindable var viewModel: CommandPaletteViewModel
    @Environment(\.language) private var language
    @Environment(\.themeColors) private var themeColors
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // 搜索框
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(themeColors.fgMuted)

                TextField(L10n.tr(.commandPaletteFilePlaceholder, language: language), text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($isSearchFieldFocused)
                    .onSubmit {
                        viewModel.selectCurrent()
                    }
                    .onChange(of: viewModel.searchText) { _, _ in
                        viewModel.handleSearchTextChanged()
                    }

                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(themeColors.fgMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(themeColors.surface)

            Divider()
                .background(themeColors.border)

            // 结果列表
            if viewModel.searchText.isEmpty {
                EmptyView()
            } else if viewModel.filteredItems.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(viewModel.filteredItems.enumerated()), id: \.element.id) { index, item in
                                itemRow(item: item, index: index)
                                    .id(item.id)
                            }
                        }
                    }
                    .frame(maxHeight: 320)
                    .onChange(of: viewModel.selectedIndex) { _, newIndex in
                        guard newIndex < viewModel.filteredItems.count else { return }
                        withAnimation(.easeInOut(duration: 0.1)) {
                            proxy.scrollTo(viewModel.filteredItems[newIndex].id, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(width: 520)
        .background(themeColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(themeColors.border, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.2), radius: 12, x: 0, y: 4)
        .onAppear {
            isSearchFieldFocused = true
        }
        .onExitCommand {
            viewModel.hide()
        }
        .background(CommandPaletteKeyMonitor(viewModel: viewModel))
    }

    // MARK: - 空状态

    private var emptyState: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(themeColors.fgMuted)
            Text(L10n.tr(.commandPaletteNoResults, language: language))
                .font(.system(size: 13))
                .foregroundStyle(themeColors.fgMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
    }

    // MARK: - 行视图

    @ViewBuilder
    private func itemRow(item: CommandPaletteFileItem, index: Int) -> some View {
        let isSelected = index == viewModel.selectedIndex

        Button {
            viewModel.selectItem(item)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? themeColors.ink : themeColors.fgSecondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.fileName)
                        .font(.system(size: 13))
                        .foregroundStyle(isSelected ? themeColors.ink : themeColors.ink)
                        .lineLimit(1)

                    Text(item.relativePath)
                        .font(.system(size: 11))
                        .foregroundStyle(themeColors.fgMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(isSelected ? themeColors.accentSoft : Color.clear)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 键盘监听

    /// 通过 AppKit NSEvent 监听上下箭头键，避免 SwiftUI .onKeyPress 干扰 TextField 输入
    private struct CommandPaletteKeyMonitor: NSViewRepresentable {
        let viewModel: CommandPaletteViewModel

        func makeNSView(context: Context) -> NSView {
            let view = KeyMonitorView()
            view.viewModel = viewModel
            return view
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            (nsView as? KeyMonitorView)?.viewModel = viewModel
        }
    }

    /// 监听键盘事件的 NSView，仅拦截上下箭头键
    private final class KeyMonitorView: NSView {
        var viewModel: CommandPaletteViewModel?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self, let vm = self.viewModel, vm.isVisible else { return event }

                    switch event.keyCode {
                    case 126: // Up arrow
                        vm.moveUp()
                        return nil
                    case 125: // Down arrow
                        vm.moveDown()
                        return nil
                    default:
                        return event
                    }
                }
            } else {
                if let monitor {
                    NSEvent.removeMonitor(monitor)
                    self.monitor = nil
                }
            }
        }
    }
}
