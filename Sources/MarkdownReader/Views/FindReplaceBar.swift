import SwiftUI

struct FindReplaceBar: View {
    @Bindable var viewModel: FindReplaceViewModel
    let isRawMode: Bool
    let onFindNext: () -> Void
    let onFindPrevious: () -> Void
    let onReplace: () -> Void
    let onReplaceAll: () -> Void
    let onClose: () -> Void

    @FocusState private var isSearchFieldFocused: Bool
    @Environment(\.themeColors) private var themeColors
    @Environment(\.language) private var language

    var body: some View {
        VStack(spacing: 0) {
            findRow
            if viewModel.isReplaceExpanded {
                replaceRow
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(themeColors.surface.opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(themeColors.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 6)
        .frame(width: 400)
        .onAppear { isSearchFieldFocused = true }
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
    }

    // MARK: - Find Row

    private var findRow: some View {
        HStack(spacing: 6) {
            Button {
                viewModel.isReplaceExpanded.toggle()
            } label: {
                Image(systemName: viewModel.isReplaceExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(themeColors.fgSecondary)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)

            searchField

            optionToggle(isOn: $viewModel.isCaseSensitive, label: "Aa", tooltip: L10n.tr(.findBarCaseSensitive, language: language))
            optionToggle(isOn: $viewModel.isWholeWord, label: "W*", tooltip: L10n.tr(.findBarWholeWord, language: language))
            optionToggle(isOn: $viewModel.isRegularExpression, label: ".*", tooltip: L10n.tr(.findBarRegularExpression, language: language))

            Button { onFindPrevious() } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11))
                    .foregroundStyle(themeColors.fgSecondary)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.totalMatchCount == 0)

            Button { onFindNext() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11))
                    .foregroundStyle(themeColors.fgSecondary)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.totalMatchCount == 0)

            Button { onClose() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundStyle(themeColors.fgMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, viewModel.isReplaceExpanded ? 1 : 6)
    }

    // MARK: - Replace Row

    private var replaceRow: some View {
        HStack(spacing: 6) {
            Color.clear.frame(width: 16)

            replaceField

            Color.clear.frame(width: 24)
            Color.clear.frame(width: 24)
            Color.clear.frame(width: 24)

            Button { onReplace() } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 11))
                    .foregroundStyle(isRawMode ? themeColors.fgSecondary : themeColors.fgMuted)
            }
            .buttonStyle(.plain)
            .disabled(!isRawMode || viewModel.totalMatchCount == 0)

            Button { onReplaceAll() } label: {
                Image(systemName: "arrow.uturn.backward.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(isRawMode ? themeColors.fgSecondary : themeColors.fgMuted)
            }
            .buttonStyle(.plain)
            .disabled(!isRawMode || viewModel.totalMatchCount == 0)

            Color.clear.frame(width: 16)
        }
        .padding(.horizontal, 8)
        .padding(.top, 1)
        .padding(.bottom, 6)
    }

    // MARK: - Text Fields

    private var searchField: some View {
        ZStack(alignment: .trailing) {
            TextField(L10n.tr(.findBarSearchPlaceholder, language: language), text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(themeColors.bgSubtle)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(viewModel.totalMatchCount == 0 && !viewModel.searchText.isEmpty ? themeColors.danger : themeColors.border, lineWidth: 1)
                )
                .focused($isSearchFieldFocused)
                .onSubmit {
                    onFindNext()
                }

            if !viewModel.searchText.isEmpty {
                Text(viewModel.matchDisplayText)
                    .font(.system(size: 11))
                    .foregroundStyle(viewModel.totalMatchCount == 0 ? themeColors.danger : themeColors.fgMuted)
                    .padding(.trailing, 6)
            }
        }
    }

    private var replaceField: some View {
        TextField(L10n.tr(.findBarReplacePlaceholder, language: language), text: $viewModel.replaceText)
            .textFieldStyle(.plain)
            .font(.system(size: 12, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(themeColors.bgSubtle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(themeColors.border, lineWidth: 1)
            )
    }

    // MARK: - Option Toggle

    private func optionToggle(isOn: Binding<Bool>, label: String, tooltip: String) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(isOn.wrappedValue ? themeColors.accent : themeColors.fgMuted)
                .frame(width: 24, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isOn.wrappedValue ? themeColors.accent.opacity(0.15) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .onHover { hovering in
            if hovering {
                NSCursor.arrow.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
