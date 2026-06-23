//
//  ContentView.swift
//  LocalizerHelper
//
//  Created by Bandan's MacBook Pro on 17/06/26.
//


import SwiftUI

struct ContentView: View {
    @State private var viewModel = ProjectViewModel()
    @State private var hasAutoOpened = false
    @State private var showAddLanguage = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailPanel
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar { toolbarContent }
        .searchable(text: $viewModel.searchText, prompt: "Search keys or literals")
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
        .onAppear {
            // Auto-open last project on app launch (only once per session)
            guard !hasAutoOpened else { return }
            hasAutoOpened = true
            
            let projectStore = ProjectStore()
            if let lastURL = projectStore.loadLastProjectURL() {
                print("🔄 Auto-opening last project: \(lastURL.path)")
                // Give the view a moment to render first, then open
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    viewModel.openProject(at: lastURL)
                }
            } else {
                print("ℹ️ No last project found to auto-open")
            }
        }
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
            }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 280)
        .overlay {
            if viewModel.isScanning {
                ProgressView("Scanning…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
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
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(viewModel.selectedNode?.url.path ?? "")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Button(action: {
                        if let url = viewModel.selectedNode?.url {
                            NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                        }
                    }) {
                        Label("Open in Finder", systemImage: "folder")
                    }
                    .help("Open file or folder in Finder")
                }
                if showsLocalizationDetail {
                    HStack {
                        AuditSummaryView(
                            errors: viewModel.issueSummary.errors,
                            warnings: viewModel.issueSummary.warnings,
                            ignored: viewModel.issueSummary.ignored
                        )
                        Spacer(minLength: 8)
                        Picker("Filter", selection: $viewModel.detailFilter) {
                            ForEach(DetailFilter.allCases) { filter in
                                Text(filter.label).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 320)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
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

        ToolbarItemGroup(placement: .automatic) {
            // Scope menu
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
            .help("Search scope: \(viewModel.searchScope.label)")
            .menuStyle(.borderlessButton)
            .fixedSize()

            // Match case toggle
            Toggle(isOn: $viewModel.searchMatchCase) {
                Text("Aa")
                    .font(.system(.body, design: .monospaced).bold())
            }
            .toggleStyle(.button)
            .help(viewModel.searchMatchCase ? "Match case: on" : "Match case: off")

            // Whole word toggle
            Toggle(isOn: $viewModel.searchWholeWord) {
                Image(systemName: "textformat.abc.dottedunderline")
            }
            .toggleStyle(.button)
            .help(viewModel.searchWholeWord ? "Whole word: on" : "Whole word: off")
        }
    }
}

#Preview {
    ContentView()
}
