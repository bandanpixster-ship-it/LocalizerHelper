import SwiftUI

struct ContentView: View {
    @State private var viewModel = ProjectViewModel()
    @State private var hasAutoOpened = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailPanel
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar { toolbarContent }
        .searchable(text: $viewModel.searchText, prompt: "Search keys or literals")
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
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.selectedNode?.url.path ?? "")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button(action: {
                    if let url = viewModel.selectedNode?.url {
                        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                    }
                }) {
                    Label("Open in Finder", systemImage: "folder")
                }
                .help("Open file or folder in Finder")
                if showsLocalizationDetail {
                    AuditSummaryView(
                        errors: viewModel.issueSummary.errors,
                        warnings: viewModel.issueSummary.warnings,
                        ignored: viewModel.issueSummary.ignored
                    )
                    Picker("Filter", selection: $viewModel.detailFilter) {
                        ForEach(DetailFilter.allCases) { filter in
                            Text(filter.label).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 280)
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
                SwiftStringsDetailView(
                    literals: viewModel.filteredSwiftLiterals,
                    pendingLiterals: viewModel.missingSwiftLiterals,
                    localizationFiles: viewModel.localizationFiles,
                    languages: viewModel.catalog.languages,
                    isKeyDuplicate: { key, fileURL in
                        viewModel.catalog.entries.contains { $0.sourceFile == fileURL && $0.key.key == key }
                    },
                    onAddLocalization: { key, fileURL, translations in
                        viewModel.addLocalization(key: key, targetFileURL: fileURL, translations: translations)
                    },
                    onTranslate: { text, lang in
                        try await viewModel.translate(text: text, to: lang)
                    }
                )
            case .directory, .strings, .xcstrings:
                if viewModel.filteredAuditResults.isEmpty && selected.fileKind == .directory {
                    EmptySelectionView(node: selected)
                } else {
                    LocalizationDetailView(
                        results: viewModel.filteredAuditResults,
                        languages: viewModel.catalog.languages,
                        onToggleIgnore: { viewModel.toggleIgnore(key: $0) },
                        sourceFileForLanguage: { viewModel.sourceFileURL(for: $0, language: $1) },
                        onSaveTranslations: { viewModel.saveTranslations(key: $0, values: $1) },
                        onTranslate: { text, lang in
                            try await viewModel.translate(text: text, to: lang)
                        }
                    )
                }
            case .other:
                EmptySelectionView(node: selected)
            }
        } else {
            EmptySelectionView(node: nil)
        }
    }

    private var showsLocalizationDetail: Bool {
        guard let selected = viewModel.selectedNode else { return false }
        return selected.fileKind == .directory || selected.fileKind == .strings || selected.fileKind == .xcstrings
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
        }
    }
}

#Preview {
    ContentView()
}
