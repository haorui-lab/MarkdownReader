import SwiftUI

/// 设置窗口主视图，包含「通用」和「外观」两个标签页
/// 参照 buddy-macos SettingsContent 的 Tab 式布局
struct SettingsView: View {
    @State private var settings = SettingsModel.shared
    @State private var selectedTab: SettingsTab = .general

    /// 当前解析后的语言，用于本地化
    private var currentLanguage: Language {
        settings.languagePref.resolvedLanguage
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView(settings: settings, language: currentLanguage)
                .tabItem {
                    Label(L10n.tr(.settingsTabGeneral, language: currentLanguage), systemImage: "gearshape")
                }
                .tag(SettingsTab.general)

            AppearanceSettingsView(settings: settings, language: currentLanguage)
                .tabItem {
                    Label(L10n.tr(.settingsTabAppearance, language: currentLanguage), systemImage: "paintbrush")
                }
                .tag(SettingsTab.appearance)
        }
        .frame(width: 450)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Settings Tab 枚举

private enum SettingsTab {
    case general
    case appearance
}

// MARK: - 通用设置视图

private struct GeneralSettingsView: View {
    @Bindable var settings: SettingsModel
    let language: Language

    /// 检测到的系统语言名称，用于 auto 选项的副标题
    /// 通过 L10n 渲染，避免英文界面下显示中文
    private var detectedLanguageName: String {
        LanguageService.detectLanguage().localizedName(language)
    }

    var body: some View {
        Form {
            // 界面语言
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Picker(L10n.tr(.settingsGeneralLanguageTitle, language: language), selection: $settings.languagePref) {
                        ForEach(LanguagePref.allCases) { pref in
                            if pref == .auto {
                                Text("\(L10n.tr(.languageAuto, language: language)) (\(detectedLanguageName))")
                                    .tag(pref)
                            } else {
                                Text(L10n.tr(LanguagePref.languageKey(for: pref), language: language))
                                    .tag(pref)
                            }
                        }
                    }
                    .pickerStyle(.menu)

                    Text(L10n.tr(.settingsGeneralLanguageDesc, language: language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(L10n.tr(.settingsGeneralLanguageTitle, language: language))
            }

            Divider()

            // 默认显示模式
            Section {
                Picker(L10n.tr(.settingsGeneralDisplayMode, language: language), selection: $settings.defaultDisplayMode) {
                    Text(L10n.tr(.displayModeRendered, language: language)).tag(DisplayMode.rendered)
                    Text(L10n.tr(.displayModeSource, language: language)).tag(DisplayMode.source)
                }
                .pickerStyle(.segmented)
            } header: {
                Text(L10n.tr(.settingsGeneralDisplayTitle, language: language))
            }

            Divider()

            // 启动行为
            Section {
                Toggle(L10n.tr(.settingsGeneralReopenLastLocation, language: language), isOn: $settings.reopenLastLocation)
            } header: {
                Text(L10n.tr(.settingsGeneralStartupTitle, language: language))
            }

            Divider()

            // 文件树过滤
            Section {
                Toggle(L10n.tr(.settingsGeneralShowHiddenFiles, language: language), isOn: $settings.showHiddenFiles)
                Toggle(L10n.tr(.settingsGeneralShowNonMarkdownFiles, language: language), isOn: $settings.showNonMarkdownFiles)
            } header: {
                Text(L10n.tr(.settingsGeneralFileTreeTitle, language: language))
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - 外观设置视图

private struct AppearanceSettingsView: View {
    @Bindable var settings: SettingsModel
    let language: Language

    var body: some View {
        Form {
            // 外观模式
            Section {
                Picker(L10n.tr(.settingsAppearanceMode, language: language), selection: $settings.appearanceMode) {
                    Text(L10n.tr(.settingsAppearanceModeLight, language: language)).tag(AppearanceMode.light)
                    Text(L10n.tr(.settingsAppearanceModeDark, language: language)).tag(AppearanceMode.dark)
                    Text(L10n.tr(.settingsAppearanceModeSystem, language: language)).tag(AppearanceMode.system)
                }
                .pickerStyle(.segmented)
                .onChange(of: settings.appearanceMode) { _, newValue in
                    applyAppearance(newValue)
                }
            } header: {
                Text(L10n.tr(.settingsAppearanceThemeTitle, language: language))
            }

            Divider()

            // 字体与排版
            Section {
                HStack {
                    Text(L10n.tr(.settingsAppearanceSourceFontSize, language: language))
                    Spacer()
                    Stepper(
                        "\(settings.sourceFontSize) pt",
                        value: $settings.sourceFontSize,
                        in: 10...24
                    )
                }

                HStack {
                    Text(L10n.tr(.settingsAppearanceContentPadding, language: language))
                    Spacer()
                    Stepper(
                        "\(settings.contentPadding) pt",
                        value: $settings.contentPadding,
                        in: 8...40
                    )
                }
            } header: {
                Text(L10n.tr(.settingsAppearanceTypographyTitle, language: language))
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    /// 应用外观模式到窗口
    private func applyAppearance(_ mode: AppearanceMode) {
        NSApp.appearance = mode.nsAppearance
        NSApp.windows.forEach { window in
            window.invalidateShadow()
        }
    }
}

// MARK: - LanguagePref 辅助扩展

extension LanguagePref {
    /// 获取语言偏好对应的本地化键
    static func languageKey(for pref: LanguagePref) -> L10n.Key {
        switch pref {
        case .auto: .languageAuto
        case .zhCN: .languageZhCN
        case .zhTW: .languageZhTW
        case .en: .languageEn
        }
    }
}
