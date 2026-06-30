//
//  AppCommands.swift
//  LocalizerHelper
//

import SwiftUI

// MARK: - Focused values bridging ViewModel into menu commands

extension FocusedValues {
    @Entry var projectViewModel: ProjectViewModel? = nil
    @Entry var showAddLanguageAction: (() -> Void)? = nil
    @Entry var openProjectInNewWindowAction: (() -> Void)? = nil
}

// MARK: - Menu commands
struct AppCommands: Commands {
    @FocusedValue(\.projectViewModel) private var viewModel: ProjectViewModel?
    @FocusedValue(\.showAddLanguageAction) private var showAddLanguage: (() -> Void)?
    @FocusedValue(\.openProjectInNewWindowAction) private var openProjectInNewWindow: (() -> Void)?

    var body: some Commands {
        fileMenuCommands
        viewMenuCommands
    }

    // MARK: File menu

    private var fileMenuCommands: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Project…") {
                viewModel?.openProject()
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("Open Project in New Window…") {
                openProjectInNewWindow?()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Button("Refresh Project") {
                viewModel?.refreshProject()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(viewModel?.rootURL == nil || viewModel?.isScanning == true)
        }
    }

    // MARK: View menu

    private var viewMenuCommands: some Commands {
        CommandMenu("Localization") {
            let canUseLocalizationActions = viewModel?.selectedNode?.fileKind == .strings || viewModel?.selectedNode?.fileKind == .xcstrings

            // Jump to localization file(s)
            let files = viewModel?.localizationFiles ?? []
            if files.isEmpty {
                Button("View Localization File") {}
                    .disabled(true)
            } else if files.count == 1 {
                Button("View Localization File") {
                    viewModel?.selectLocalizationFile(files[0])
                }
                .keyboardShortcut("l", modifiers: .command)
            } else {
                Menu("View Localization File") {
                    ForEach(files, id: \.self) { file in
                        Button(file.lastPathComponent) {
                            viewModel?.selectLocalizationFile(file)
                        }
                    }
                }
            }

            Button("Add Language…") {
                showAddLanguage?()
            }
            .disabled(viewModel?.localizationFiles.isEmpty ?? true)

            Divider()

            // Detail filter shortcuts
            Button("Show All Strings") {
                viewModel?.detailFilter = .all
            }
            .keyboardShortcut("1", modifiers: .command)
            .disabled(!canUseLocalizationActions)

            Button("Show Errors Only") {
                viewModel?.detailFilter = .errors
            }
            .keyboardShortcut("2", modifiers: .command)
            .disabled(!canUseLocalizationActions)

            Button("Show Warnings Only") {
                viewModel?.detailFilter = .warnings
            }
            .keyboardShortcut("3", modifiers: .command)
            .disabled(!canUseLocalizationActions)

            Button("Show Ignored Only") {
                viewModel?.detailFilter = .ignored
            }
            .keyboardShortcut("4", modifiers: .command)
            .disabled(!canUseLocalizationActions)

            Button("Show AI Ready Only") {
                viewModel?.detailFilter = .aiReady
            }
            .keyboardShortcut("5", modifiers: .command)
            .disabled(!canUseLocalizationActions)
        }
    }
}
