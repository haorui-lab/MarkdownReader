import Foundation
import AppKit
import os
import MarkdownReaderKit

/// 应用级终止协调器（Task 12）。
@MainActor
final class ApplicationTerminationCoordinator {

    private let logger = Logger(subsystem: "com.markdownreader.app", category: "TerminationCoordinator")

    weak var coordinator: WindowCoordinator?

    private var isTerminating = false

    init(coordinator: WindowCoordinator? = nil) {
        self.coordinator = coordinator
    }

    func shouldClose(session: WindowSession) -> Bool {
        let decision = session.prepareForClose()
        switch decision {
        case .close:
            return true
        case .needsUntitledDecision:
            return presentUntitledSaveAlert(for: session)
        case .cancel:
            return false
        }
    }

    @discardableResult
    func processTermination() -> Bool {
        guard !isTerminating else { return false }
        isTerminating = true
        defer { isTerminating = false }

        guard let coordinator else {
            NSApp.reply(toApplicationShouldTerminate: true)
            return true
        }

        let dirtySessions = coordinator.sessions.values.filter {
            $0.documentViewModel.isUntitled && $0.documentViewModel.isDirty
        }

        for session in dirtySessions {
            let canClose = presentUntitledSaveAlert(for: session)
            if !canClose {
                NSApp.reply(toApplicationShouldTerminate: false)
                return false
            }
        }

        NSApp.reply(toApplicationShouldTerminate: true)
        return true
    }

    func handleReopen() {
        guard let coordinator else { return }
        if coordinator.hasRegisteredSession {
            if let lastID = coordinator.lastActiveWindowID {
                coordinator.activate(windowID: lastID)
            }
        } else {
            coordinator.openBlankWindow()
        }
    }

    private func presentUntitledSaveAlert(for session: WindowSession) -> Bool {
        let doc = session.documentViewModel
        let settings = SettingsModel.shared
        let language = settings.languagePref.resolvedLanguage

        let alert = NSAlert()
        alert.messageText = L10n.tr(.unsavedChangesTitle, language: language)
        alert.informativeText = L10n.tr(.unsavedChangesMessage, language: language)
        alert.alertStyle = .warning

        alert.addButton(withTitle: L10n.tr(.unsavedSave, language: language))
        alert.addButton(withTitle: L10n.tr(.unsavedDontSave, language: language))
        alert.addButton(withTitle: L10n.tr(.unsavedCancel, language: language))

        alert.buttons[0].keyEquivalent = "\r"
        alert.buttons[1].keyEquivalent = "d"
        alert.buttons[1].keyEquivalentModifierMask = .command
        alert.buttons[2].keyEquivalent = "\u{1b}"

        let response = alert.runModal()

        switch response {
        case .alertFirstButtonReturn:
            let defaultDir = settings.lastOpenedDirectory ?? settings.lastOpenedFile?.deletingLastPathComponent()
            let suggestedName = doc.fileName.isEmpty ? "Untitled.md" : doc.fileName
            guard let saveURL = OpenPanelHelper.showSavePanel(
                for: session.window,
                language: language,
                defaultDirectory: defaultDir,
                suggestedName: suggestedName
            ) else {
                return false
            }
            let semaphore = DispatchSemaphore(value: 0)
            Task { @MainActor in
                await doc.saveAs(to: saveURL)
                semaphore.signal()
            }
            semaphore.wait()
            return true
        case .alertSecondButtonReturn:
            doc.discardUntitledFile()
            return true
        default:
            return false
        }
    }
}
