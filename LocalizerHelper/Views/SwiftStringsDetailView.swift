import SwiftUI

struct SwiftStringsDetailView: View {
    let literals: [SwiftStringLiteral]
    let pendingLiterals: [SwiftStringLiteral]
    let localizationFiles: [URL]
    let languages: [String]
    let isKeyDuplicate: (String, URL) -> Bool
    let onAddLocalization: (String, URL, [String: String], String) -> Void
    let onBulkAdd: (_ items: [(key: String, translations: [String: String], comment: String)], _ file: URL, _ progress: @escaping (Int) -> Void) async -> Void
    let onTranslate: (String, String) async throws -> String
    let onAITranslateBatch: ((String, String, String?, [String]) async throws -> [String: String])?
    let onGenerateComment: ((String, String) async throws -> String)?
    let onCreateLocalizationFile: () async -> URL?

    @State private var filter: Filter = .all
    @State private var sortOrder: SortOrder = .line
    @State private var selectedLiteral: SwiftStringLiteral?
    @State private var showBulkAdd = false

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case missing = "Missing"
        case present = "Present"

        var id: String { rawValue }
    }

    enum SortOrder: String, CaseIterable, Identifiable {
        case line = "Line"
        case status = "Status"
        case pattern = "Pattern"

        var id: String { rawValue }
    }

    private struct Row: Identifiable {
        let literal: SwiftStringLiteral
        let isMissing: Bool
        var id: UUID { literal.id }
    }

    private var rows: [Row] {
        let missingIDs = Set(pendingLiterals.map { $0.id })
        var rows = literals.map { literal in
            Row(literal: literal, isMissing: missingIDs.contains(literal.id))
        }

        switch filter {
        case .all:
            break
        case .missing:
            rows.removeAll { !$0.isMissing }
        case .present:
            rows.removeAll { $0.isMissing }
        }

        switch sortOrder {
        case .line:
            rows.sort { $0.literal.lineNumber < $1.literal.lineNumber }
        case .status:
            rows.sort {
                if $0.isMissing == $1.isMissing {
                    return $0.literal.lineNumber < $1.literal.lineNumber
                }
                return $0.isMissing && !$1.isMissing
            }
        case .pattern:
            rows.sort { $0.literal.displayPattern.localizedCaseInsensitiveCompare($1.literal.displayPattern) == .orderedAscending }
        }

        return rows
    }

    var body: some View {
        if literals.isEmpty {
            ContentUnavailableView("No String Literals", systemImage: "text.quote", description: Text("No double-quoted string literals were found in this file."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("String Literal Audit")
                            .font(.title3.weight(.semibold))
                        Text("Filter and sort extracted literals, with missing Localizable items highlighted.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    HStack(spacing: 12) {
                        Picker("Filter", selection: $filter) {
                            ForEach(Filter.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 320)

                        Menu {
                            ForEach(SortOrder.allCases) { option in
                                Button(option.rawValue) {
                                    sortOrder = option
                                }
                            }
                        } label: {
                            Label("Sort: \(sortOrder.rawValue)", systemImage: "arrow.up.arrow.down")
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                Table(rows) {
                    TableColumn("Pattern") { row in
                        Text(row.literal.displayPattern)
                            .font(.body)
                            .foregroundColor(.primary)
                    }
                    TableColumn("Raw") { row in
                        Text(row.literal.raw)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    TableColumn("Status") { row in
                        Text(row.isMissing ? "Missing" : "Present")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(row.isMissing ? .orange : .green)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background((row.isMissing ? Color.orange.opacity(0.16) : Color.green.opacity(0.16)), in: RoundedRectangle(cornerRadius: 12))
                    }
                    TableColumn("Line") { row in
                        Text("\(row.literal.lineNumber)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    TableColumn("Notes") { row in
                        if row.literal.hasInterpolation {
                            Text("Contains variable")
                                .foregroundStyle(.orange)
                        } else {
                            Text("—")
                                .foregroundStyle(.secondary)
                        }
                    }
                    TableColumn("Actions") { row in
                        if row.isMissing {
                            Button(action: {
                                selectedLiteral = row.literal
                            }) {
                                Label("Add to Localization", systemImage: "plus")
                            }
                            .buttonStyle(.borderless)
                        } else {
                            Text("—")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
                .background(.background)
                .cornerRadius(14)

                HStack(spacing: 12) {
                    Text("Showing \(rows.count) of \(literals.count) extracted literals")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if rows.count < literals.count {
                        Text("\(literals.count - rows.count) remaining")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if !pendingLiterals.isEmpty && !localizationFiles.isEmpty {
                        Button {
                            showBulkAdd = true
                        } label: {
                            Label("Add All Missing (\(pendingLiterals.count))", systemImage: "square.and.arrow.down.on.square")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal, 4)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .sheet(item: $selectedLiteral) { literal in
                AddLocalizationSheet(
                    literal: literal,
                    localizationFiles: localizationFiles,
                    languages: languages,
                    isKeyDuplicate: isKeyDuplicate,
                    onAdd: onAddLocalization,
                    onTranslate: onTranslate,
                    onAITranslateBatch: onAITranslateBatch,
                    onGenerateComment: onGenerateComment,
                    onCreateFile: onCreateLocalizationFile
                )
            }
            .sheet(isPresented: $showBulkAdd) {
                BulkAddSheet(
                    literals: pendingLiterals,
                    localizationFiles: localizationFiles,
                    languages: languages,
                    onBulkAdd: onBulkAdd,
                    onTranslate: onTranslate,
                    onAITranslateBatch: onAITranslateBatch
                )
            }
        }
    }
}

struct AddLocalizationSheet: View {
    let literal: SwiftStringLiteral
    let isKeyDuplicate: (String, URL) -> Bool
    let onAdd: (String, URL, [String: String], String) -> Void
    let onTranslate: (String, String) async throws -> String
    let onAITranslateBatch: ((String, String, String?, [String]) async throws -> [String: String])?
    let onGenerateComment: ((String, String) async throws -> String)?
    let onCreateFile: () async -> URL?

    @Environment(\.dismiss) private var dismiss

    @State private var key: String = ""
    @State private var comment: String = ""
    @State private var selectedFile: URL?
    @State private var localFiles: [URL]
    @State private var localLanguages: [String]
    @State private var translations: [String: String] = [:]
    @State private var isTranslating = false
    @State private var isGeneratingComment = false
    @State private var isCreatingFile = false
    @State private var validationError: String? = nil
    @State private var translateError: String?

    init(
        literal: SwiftStringLiteral,
        localizationFiles: [URL],
        languages: [String],
        isKeyDuplicate: @escaping (String, URL) -> Bool,
        onAdd: @escaping (String, URL, [String: String], String) -> Void,
        onTranslate: @escaping (String, String) async throws -> String,
        onAITranslateBatch: ((String, String, String?, [String]) async throws -> [String: String])?,
        onGenerateComment: ((String, String) async throws -> String)?,
        onCreateFile: @escaping () async -> URL?
    ) {
        self.literal = literal
        self.isKeyDuplicate = isKeyDuplicate
        self.onAdd = onAdd
        self.onTranslate = onTranslate
        self.onAITranslateBatch = onAITranslateBatch
        self.onGenerateComment = onGenerateComment
        self.onCreateFile = onCreateFile

        _key = State(initialValue: literal.localizationTemplate)
        _localFiles = State(initialValue: localizationFiles)
        _localLanguages = State(initialValue: languages.isEmpty ? ["en"] : languages)
        _selectedFile = State(initialValue: localizationFiles.first)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("Add to Localization")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                if !localFiles.isEmpty {
                    Button("Add") {
                        if let selectedFile {
                            onAdd(key, selectedFile, translations, comment)
                            dismiss()
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(key.isEmpty || selectedFile == nil || validationError != nil)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .background(.regularMaterial)

            Divider()

            if localFiles.isEmpty {
                noFilesView
            } else {
                formView
            }
        }
        .frame(width: 500, height: 520)
    }

    private var noFilesView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Localization Files Found")
                .font(.title3.weight(.semibold))
            Text("This project has no .strings or .xcstrings files yet.\nCreate one to get started.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: createFile) {
                if isCreatingFile {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Create Localizable.strings", systemImage: "plus")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isCreatingFile)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private var formView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Key + file picker
                GroupBox("Localization Settings") {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Key", text: $key)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: key) { validateKey() }

                        if let validationError {
                            Text(validationError)
                                .font(.caption)
                                .foregroundColor(.red)
                        }

                        Picker("Target File", selection: $selectedFile) {
                            ForEach(localFiles, id: \.self) { file in
                                Text(file.lastPathComponent).tag(URL?.some(file))
                            }
                        }
                        .onChange(of: selectedFile) { validateKey() }
                    }
                    .padding(4)
                }

                // Developer comment
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        if !literal.sourceLine.isEmpty {
                            Text(literal.sourceLine)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .truncationMode(.middle)
                        }
                        TextField("Describe this string's context for translators…", text: $comment, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2...4)
                    }
                    .padding(4)
                } label: {
                    HStack {
                        Label("Developer Comment", systemImage: "text.bubble")
                        Spacer()
                        if let onGenerateComment {
                            if isGeneratingComment {
                                ProgressView().controlSize(.small)
                            } else {
                                Button {
                                    generateComment(onGenerateComment)
                                } label: {
                                    Label("Generate", systemImage: "sparkles")
                                }
                                .buttonStyle(.borderless)
                                .disabled(literal.sourceLine.isEmpty)
                                .help("Use AI to generate a comment from the source code line")
                            }
                        }
                    }
                }

                // Translations
                GroupBox {
                    VStack(spacing: 10) {
                        ForEach(localLanguages, id: \.self) { lang in
                            HStack {
                                Text(lang.uppercased())
                                    .frame(width: 40, alignment: .leading)
                                    .font(.caption.bold())
                                    .foregroundColor(.secondary)
                                TextField("Translation", text: Binding(
                                    get: { translations[lang] ?? "" },
                                    set: { translations[lang] = $0 }
                                ))
                                .textFieldStyle(.roundedBorder)
                                Button { translateField(lang) } label: {
                                    Image(systemName: "translate")
                                }
                                .buttonStyle(.borderless)
                                .disabled(key.isEmpty || isTranslating)
                            }
                        }
                    }
                    .padding(4)
                } label: {
                    HStack {
                        Text("Translations")
                        Spacer()
                        if isTranslating {
                            ProgressView().controlSize(.small)
                        } else {
                            HStack(spacing: 12) {
                                Button("Auto-Translate All") { autoTranslateAll() }
                                    .buttonStyle(.borderless)
                                    .disabled(key.isEmpty)
                                if onAITranslateBatch != nil {
                                    Button {
                                        aiTranslateAll()
                                    } label: {
                                        Label("AI Translate", systemImage: "sparkles")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                    .disabled(key.isEmpty)
                                    .help("Translates all languages in one AI call using context from the developer comment")
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .alert("Translation Failed", isPresented: .init(
            get: { translateError != nil },
            set: { if !$0 { translateError = nil } }
        )) {
            Button("OK") { translateError = nil }
        } message: {
            Text(translateError ?? "")
        }
        .onAppear {
            if translations["en"] == nil { translations["en"] = key }
            validateKey()
        }
    }

    private func generateComment(_ generate: @escaping (String, String) async throws -> String) {
        isGeneratingComment = true
        let sourceLine = literal.sourceLine
        let currentKey = key
        Task {
            do {
                let generated = try await generate(sourceLine, currentKey)
                await MainActor.run {
                    comment = generated
                    isGeneratingComment = false
                }
            } catch {
                print("[GenerateComment] failed: \(error.localizedDescription)")
                await MainActor.run {
                    translateError = error.localizedDescription
                    isGeneratingComment = false
                }
            }
        }
    }

    private func aiTranslateAll() {
        guard let onAITranslateBatch else { return }
        let targets = localLanguages.filter { $0 != "en" }
        guard !targets.isEmpty else { return }
        let sourceText = translations["en"] ?? key
        let commentOverride = comment.isEmpty ? nil : comment
        isTranslating = true
        translateError = nil
        Task {
            do {
                let results = try await onAITranslateBatch(key, sourceText, commentOverride, targets)
                await MainActor.run {
                    if results.isEmpty {
                        translateError = "AI translation returned no results. Check your provider settings or try again."
                    } else {
                        for (lang, value) in results where !value.isEmpty {
                            translations[lang] = value
                        }
                    }
                    isTranslating = false
                }
            } catch {
                print("[AI Translate] failed: \(error.localizedDescription)")
                await MainActor.run {
                    isTranslating = false
                    translateError = error.localizedDescription
                }
            }
        }
    }

    private func createFile() {
        isCreatingFile = true
        Task {
            if let url = await onCreateFile() {
                let lang = languageFromFileURL(url)
                await MainActor.run {
                    localFiles = [url]
                    if !localLanguages.contains(lang) {
                        localLanguages = [lang]
                    }
                    selectedFile = url
                    if translations[lang] == nil { translations[lang] = key }
                    isCreatingFile = false
                    validateKey()
                }
            } else {
                await MainActor.run { isCreatingFile = false }
            }
        }
    }

    private func languageFromFileURL(_ url: URL) -> String {
        let parent = url.deletingLastPathComponent()
        if parent.pathExtension == "lproj" {
            return parent.deletingPathExtension().lastPathComponent
        }
        return "en"
    }

    private func validateKey() {
        guard !key.isEmpty else {
            validationError = "Key cannot be empty"
            return
        }
        if let selectedFile {
            if isKeyDuplicate(key, selectedFile) {
                validationError = "Key '\(key)' already exists in this file."
                return
            }
        }
        validationError = nil
    }

    private func translateField(_ lang: String) {
        isTranslating = true
        translateError = nil
        Task {
            do {
                let result = try await onTranslate(key, lang)
                await MainActor.run {
                    translations[lang] = result
                    isTranslating = false
                }
            } catch {
                await MainActor.run {
                    isTranslating = false
                    translateError = error.localizedDescription
                }
            }
        }
    }

    private func autoTranslateAll() {
        isTranslating = true
        Task {
            var updated = translations
            for lang in localLanguages {
                if lang != "en" {
                    do {
                        let result = try await onTranslate(key, lang)
                        updated[lang] = result
                    } catch {
                        // fallback / ignore
                    }
                }
            }
            await MainActor.run {
                translations = updated
                isTranslating = false
            }
        }
    }
}
