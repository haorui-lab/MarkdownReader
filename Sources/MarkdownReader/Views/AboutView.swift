import SwiftUI
import MarkdownReaderKit

/// 自定义 About 面板，展示应用名称、版本号、功能特性和技术栈
struct AboutView: View {
    let language: Language
    private let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    private let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""

    var body: some View {
        VStack(spacing: 0) {
            // 顶部：图标 + 名称 + 版本
            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 80, height: 80)

                Text("Markdown Reader")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("v\(version)" + (build.isEmpty ? "" : " (\(build))"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 24)
            .padding(.bottom, 16)

            // 描述
            Text(L10n.tr(.aboutDescription, language: language))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

            // 功能列表
            VStack(alignment: .leading, spacing: 6) {
                featureRow(icon: "doc.richtext", text: L10n.tr(.aboutRendering, language: language))
                featureRow(icon: "chart.diagram", text: L10n.tr(.aboutMermaid, language: language))
                featureRow(icon: "flowchart", text: L10n.tr(.aboutPlantUML, language: language))
                featureRow(icon: "function", text: L10n.tr(.aboutKatex, language: language))
                featureRow(icon: "code", text: L10n.tr(.aboutPrism, language: language))
                featureRow(icon: "eye", text: L10n.tr(.aboutQuickLook, language: language))
                featureRow(icon: "pencil", text: L10n.tr(.aboutEdit, language: language))
                featureRow(icon: "folder", text: L10n.tr(.aboutFileTree, language: language))
                featureRow(icon: "list.bullet.indent", text: L10n.tr(.aboutOutline, language: language))
                featureRow(icon: "paintpalette", text: L10n.tr(.aboutThemes, language: language))
                featureRow(icon: "globe", text: L10n.tr(.aboutI18n, language: language))
                featureRow(icon: "terminal", text: L10n.tr(.aboutCLI, language: language))
                featureRow(icon: "doc.badge.arrow.up", text: L10n.tr(.aboutPDF, language: language))
                featureRow(icon: "magnifyingglass", text: L10n.tr(.aboutFindReplace, language: language))
                featureRow(icon: "plus.magnifyingglass", text: L10n.tr(.aboutZoom, language: language))
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 16)

            Divider()
                .padding(.horizontal, 24)

            // 技术栈
            Text(L10n.tr(.aboutCredits, language: language))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 12)

            // 网站
            if let url = URL(string: "https://davidhoo.github.io/MarkdownReader/") {
                Link(destination: url) {
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                            .font(.caption2)
                        Text(L10n.tr(.aboutWebsite, language: language))
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 12)
            }
        }
        .frame(width: 340)
        .fixedSize()
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .center)
                .padding(.top, 1)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
