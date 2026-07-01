//
//  ContentView.swift
//  LocalizerHelper
//
//  Created by Bandan's MacBook Pro on 17/06/26.
//


import SwiftUI

struct ContentView: View {
    @State private var viewModel: ProjectViewModel
    @State private var hasAutoOpened = false
    @State private var showAddLanguage = false
    @State private var showMissingProjectAlert = false
    @State private var initialProjectURL: URL?
    @State private var autoOpenLastProject: Bool

    init(initialProjectURL: URL? = nil, autoOpenLastProject: Bool = true) {
        _viewModel = State(initialValue: ProjectViewModel())
        _initialProjectURL = State(initialValue: initialProjectURL)
        _autoOpenLastProject = State(initialValue: autoOpenLastProject)
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailPanel
        }
        .focusedSceneValue(\.projectViewModel, viewModel)
        .focusedSceneValue(\.showAddLanguageAction, { showAddLanguage = true })
        .focusedSceneValue(\.openProjectInNewWindowAction, {
            viewModel.openProjectInNewWindow { projectURL in
                WindowCoordinator.shared.openProjectWindow(with: projectURL)
            }
        })
        .navigationTitle(windowTitle)
        .navigationSplitViewStyle(.balanced)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showAddLanguage) {
            AddLanguageView(
                localizationFiles: viewModel.localizationFiles,
                existingLanguages: viewModel.catalog.languages,
                onAdd: { code, file in viewModel.addLanguage(code: code, to: file) }
            )
        }
        .alert("Scan Error", isPresented: .init(
            get: { viewModel.scanError != nil },
            set: { if !$0 { viewModel.scanError = nil } }
        )) {
            Button("OK") { viewModel.scanError = nil }
        } message: {
            Text(viewModel.scanError ?? "")
        }
        .alert("Last Project Missing", isPresented: $showMissingProjectAlert) {
            Button("Locate Project…") {
                locateMissingProject()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The previously opened project could not be found at its saved location. You can locate a project folder manually.")
        }
        .confirmationDialog("Project Already Open", isPresented: $viewModel.showOpenProjectChoice, titleVisibility: .visible) {
            Button("Open in This Window") {
                viewModel.openPendingProjectInCurrentWindow()
            }
            Button("Open in New Window") {
                if let projectURL = viewModel.pendingProjectURL {
                    WindowCoordinator.shared.openProjectWindow(with: projectURL)
                }
                viewModel.cancelPendingProjectOpen()
            }
            Button("Cancel", role: .cancel) {
                viewModel.cancelPendingProjectOpen()
            }
        } message: {
            Text("This window already has a project open. Choose whether to replace it here or open the selected project in a new window.")
        }
        .background(
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.06),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .onAppear {
            guard !hasAutoOpened else { return }
            hasAutoOpened = true

            if let initialProjectURL {
                DispatchQueue.main.async {
                    viewModel.openProject(at: initialProjectURL)
                }
                return
            }

            guard autoOpenLastProject else { return }

            let projectStore = ProjectStore()
            if case let .found(lastURL) = projectStore.loadLastProjectURL() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    viewModel.openProject(at: lastURL)
                }
            } else {
                showMissingProjectAlert = true
            }
        }
    }

    private var windowTitle: String {
        if let selected = viewModel.selectedNode {
            return selected.name
        }
        if let rootURL = viewModel.rootURL {
            return rootURL.lastPathComponent
        }
        return "LocalizerHelper"
    }

    private func locateMissingProject() {
        let panel = NSOpenPanel()
        panel.title = "Locate Project Folder"
        panel.message = "Choose the folder for the project that moved."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Locate"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        viewModel.openProject(at: url)
    }

    @ViewBuilder
    private var sidebar: some View {
        Group {
            if let root = viewModel.rootNode {
                ProjectTreeView(root: root, selection: Binding(
                    get: { viewModel.selectedNode },
                    set: { viewModel.selectNode($0) }
                ))
            } else {
                ContentUnavailableView {
                    Label("No Project", systemImage: "folder")
                } description: {
                    Text("Open a project folder to browse files and audit localizations.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
        .navigationSplitViewColumnWidth(min: 240, ideal: 300)
        .overlay {
            if viewModel.isScanning {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Scanning project…")
                        .font(.subheadline.weight(.medium))
                    Text("We’re indexing files and localization entries.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(16)
                .frame(maxWidth: 240)
                .modernCard()
            }
        }
    }

    @ViewBuilder
    private var detailPanel: some View {
        VStack(spacing: 0) {
            detailHeader
            Divider()
            detailContent
        }
        .background(.background)
    }

    @ViewBuilder
    private var detailHeader: some View {
        if viewModel.selectedNode != nil {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    Button {
                        viewModel.goBackToPreviousSelection()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                            .labelStyle(.iconOnly)
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.canGoBackInSelection)
                    .help("Go back to the previous selection")

                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.selectedNode?.name ?? "")
                            .font(.headline)
                            .lineLimit(1)
                        Text(viewModel.selectedNode?.url.path ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 12)

                    Button(action: {
                        if let url = viewModel.selectedNode?.url {
                            NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                        }
                    }) {
                        Label("Open in Finder", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Open file or folder in Finder")
                }

                HStack(spacing: 10) {
                    TextField("Search keys or literals", text: $viewModel.searchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 360)

                    Menu {
                        ForEach(SearchScope.allCases) { scope in
                            Button {
                                viewModel.searchScope = scope
                            } label: {
                                Label(scope.label, systemImage: scope.icon)
                                if viewModel.searchScope == scope {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    } label: {
                        Label(viewModel.searchScope.label, systemImage: viewModel.searchScope.icon)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .padding(.horizontal, 2)
                    .help("Search scope: \(viewModel.searchScope.label)")

                    Toggle(isOn: $viewModel.searchMatchCase) {
                        Text("Aa")
                            .font(.system(.body, design: .monospaced).bold())
                    }
                    .toggleStyle(.button)
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                    .help(viewModel.searchMatchCase ? "Match case: on" : "Match case: off")

                    Toggle(isOn: $viewModel.searchWholeWord) {
                        Image(systemName: "textformat.abc.dottedunderline")
                    }
                    .toggleStyle(.button)
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                    .help(viewModel.searchWholeWord ? "Whole word: on" : "Whole word: off")

                    Spacer(minLength: 0)
                }

                if showsLocalizationDetail {
                    HStack(spacing: 12) {
                        AuditSummaryView(
                            errors: viewModel.issueSummary.errors,
                            warnings: viewModel.issueSummary.warnings,
                            ignored: viewModel.issueSummary.ignored
                        )
                        Spacer(minLength: 8)
                        if canShowLocalizationFilters {
                            Picker("Filter", selection: $viewModel.detailFilter) {
                                ForEach(DetailFilter.allCases) { filter in
                                    Text(filter.label).tag(filter)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 260)
                            .padding(.horizontal, 20)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if let selected = viewModel.selectedNode {
            switch selected.fileKind {
            case .swift:
                swiftStringsDetailView
            case .directory:
                if !viewModel.swiftLiterals.isEmpty {
                    swiftStringsDetailView
                } else if !viewModel.filteredAuditResults.isEmpty {
                    localizationDetailView
                } else {
                    EmptySelectionView(node: selected)
                }
            case .strings, .xcstrings:
                localizationDetailView
            case .other:
                EmptySelectionView(node: selected)
            }
        } else {
            EmptySelectionView(node: nil)
        }
    }

    private var aiTranslateBatchHandler: ((String, String, String?, [String]) async throws -> [String: String])? {
        guard AISettings.shared.hasAnyKey else { return nil }
        return { [viewModel] key, sourceText, commentOverride, languages in
            try await viewModel.aiTranslateBatch(key: key, sourceText: sourceText, commentOverride: commentOverride, languages: languages)
        }
    }

    private var generateCommentHandler: ((String, String) async throws -> String)? {
        guard AISettings.shared.hasAnyKey else { return nil }
        return { [viewModel] sourceLine, key in
            try await viewModel.generateComment(sourceLine: sourceLine, key: key)
        }
    }

    @ViewBuilder
    private var swiftStringsDetailView: some View {
        SwiftStringsDetailView(
            literals: viewModel.filteredSwiftLiterals,
            pendingLiterals: viewModel.missingSwiftLiterals,
            localizationFiles: viewModel.localizationFiles,
            languages: viewModel.catalog.languages,
            isKeyDuplicate: { key, fileURL in
                viewModel.catalog.entries.contains { $0.sourceFile == fileURL && $0.key.key == key }
            },
            onAddLocalization: { key, fileURL, translations, comment in
                viewModel.addLocalization(key: key, targetFileURL: fileURL, translations: translations, comment: comment)
            },
            onBulkAdd: { items, file, progress in
                await viewModel.bulkAddLocalizations(items: items, targetFileURL: file, progress: progress)
            },
            onTranslate: { text, lang in
                try await viewModel.translate(text: text, to: lang)
            },
            onAITranslateBatch: aiTranslateBatchHandler,
            onGenerateComment: generateCommentHandler,
            onCreateLocalizationFile: {
                await viewModel.createLocalizationFile()
            }
        )
    }

    @ViewBuilder
    private var localizationDetailView: some View {
        LocalizationDetailView(
            results: viewModel.filteredAuditResults,
            languages: viewModel.catalog.languages,
            onToggleIgnore: { viewModel.toggleIgnore(key: $0) },
            sourceFileForLanguage: { viewModel.sourceFileURL(for: $0, language: $1) },
            onSaveTranslations: { viewModel.saveTranslations(key: $0, values: $1) },
            onSaveComment: { viewModel.saveComment(key: $0, comment: $1) },
            onTranslate: { text, lang, commentOverride in
                try await viewModel.translate(text: text, to: lang, commentOverride: commentOverride)
            },
            onAITranslateBatch: aiTranslateBatchHandler,
            onAffectedFiles: { viewModel.affectedFiles(for: $0) },
            onDeleteKey: { viewModel.deleteLocalization(key: $0) }
        )
    }

    private var showsLocalizationDetail: Bool {
        guard let selected = viewModel.selectedNode else { return false }
        return selected.fileKind == .directory || selected.fileKind == .strings || selected.fileKind == .xcstrings
    }

    private var canShowLocalizationFilters: Bool {
        guard let selected = viewModel.selectedNode else { return false }
        return selected.fileKind == .strings || selected.fileKind == .xcstrings
    }

    @ViewBuilder
    private var openLocalizableButton: some View {
        let files = viewModel.localizationFiles
        if files.count == 1 {
            Button {
                viewModel.selectLocalizationFile(files[0])
            } label: {
                Label("Open Localizable", systemImage: "doc.text.magnifyingglass")
            }
            .disabled(files.isEmpty)
            .help("Select \(files[0].lastPathComponent) in the sidebar")
        } else if files.count > 1 {
            Menu {
                ForEach(files, id: \.self) { file in
                    Button(file.lastPathComponent) {
                        viewModel.selectLocalizationFile(file)
                    }
                }
            } label: {
                Label("Open Localizable", systemImage: "doc.text.magnifyingglass")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Jump to a localization file in the sidebar")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button(action: { viewModel.openProject() }) {
                Label("Open Project", systemImage: "folder")
            }
            Button(action: { viewModel.refreshProject() }) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(viewModel.rootURL == nil || viewModel.isScanning)
            Button(action: { showAddLanguage = true }) {
                Label("Add Language", systemImage: "plus.bubble")
            }
            .disabled(viewModel.localizationFiles.isEmpty)
            .help("Add a new language to your localization files")

            openLocalizableButton
        }
    }
}

#Preview {
    ContentView()
}
