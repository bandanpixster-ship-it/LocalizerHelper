import SwiftUI

struct LocalizationDetailView: View {
    let results: [KeyAuditResult]
    let languages: [String]
    let onToggleIgnore: (LocalizationKey) -> Void
    let sourceFileForLanguage: (LocalizationKey, String) -> URL?
    let onSaveTranslations: (LocalizationKey, [String: String]) -> Void
    let onSaveComment: (LocalizationKey, String) -> Void
    let onTranslate: (String, String, String?) async throws -> String
    let onAITranslateBatch: ((String, String, String?, [String]) async throws -> [String: String])?
    let onAffectedFiles: (LocalizationKey) -> [URL]
    let onDeleteKey: (LocalizationKey) -> Void

    @EnvironmentObject private var ignoreStore: GlobalIgnoreStore

    @State private var editSession: EditSession?
    @State private var editValues: [String: String] = [:]
    @State private var editComment: String = ""
    @State private var showSaveConfirmation = false
    @State private var deleteConfirmation: DeleteConfirmation?
    @State private var translateError: String?

    struct DeleteConfirmation: Identifiable {
        let id = UUID()
        let key: LocalizationKey
        let affectedFiles: [URL]
    }
    @State private var isTranslating = false

    struct EditSession: Identifiable, Equatable {
        let id = UUID()
        let key: LocalizationKey
        let availableLanguages: [String]
        let originalValues: [String: String]
        let originalComment: String
        let issues: [AuditIssue]
    }

    var body: some View {
        if results.isEmpty {
            ContentUnavailableView("No Localization Keys", systemImage: "globe", description: Text("No .strings or .xcstrings entries found in this selection."))
        } else {
            List {
                ForEach(groupedByFile, id: \.file) { group in
                    Section {
                        ForEach(group.results) { result in
                            localizationRow(result)
                                .listRowSeparator(.hidden)
                        }
                    } header: {
                        Text(group.file.lastPathComponent)
                            .font(.headline)
                    }
                }
            }
            .listStyle(.plain)
            .onChange(of: editSession) { oldSession, newSession in
                if let session = newSession {
                    editValues = session.originalValues
                    editComment = session.originalComment
                } else {
                    editValues = [:]
                    editComment = ""
                }
            }
            .sheet(item: $deleteConfirmation) { confirmation in
                DeleteConfirmationSheet(confirmation: confirmation) {
                    onDeleteKey(confirmation.key)
                }
            }
            .sheet(item: $editSession) { session in
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Edit translations for \(session.key.key)")
                                .font(.headline)
                            Text("Key cannot be modified")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if isTranslating {
                            ProgressView().controlSize(.small)
                        } else {
                            HStack(spacing: 8) {
                                Button("Auto-Translate All") {
                                    autoTranslateAll(key: session.key, availableLanguages: session.availableLanguages)
                                }
                                .buttonStyle(.bordered)

                                if onAITranslateBatch != nil {
                                    Button {
                                        aiTranslateAll(key: session.key, availableLanguages: session.availableLanguages)
                                    } label: {
                                        Label("AI Translate", systemImage: "sparkles")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .help("Translates all languages in a single AI call using your configured provider. This may incur API costs.")
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Label("Developer Comment", systemImage: "text.bubble")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            if !editComment.isEmpty {
                                Image(systemName: "sparkles")
                                    .font(.caption)
                                    .foregroundStyle(.purple)
                                    .help("This comment will be used as context for AI translation")
                            }
                        }
                        TextField("Add a comment to help AI translate this key in context…", text: $editComment, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2...4)
                    }

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(sortedLanguages(session: session), id: \.self) { language in
                                let editable = sourceFileForLanguage(session.key, language) != nil
                                let originalValue = session.originalValues[language] ?? ""
                                let langIssues = session.issues.filter { $0.language == language }
                                let isLangIgnored = ignoreStore.entries.contains(where: { $0.key == session.key.key && $0.language == language })
                                let langSeverity: AuditSeverity? = isLangIgnored ? .ignored
                                    : langIssues.contains(where: { $0.severity == .error }) ? .error
                                    : langIssues.contains(where: { $0.severity == .warning }) ? .warning
                                    : nil
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 6) {
                                        if let sev = langSeverity {
                                            Image(systemName: sev == .ignored ? "eye.slash" : "circle.fill")
                                                .font(.system(size: sev == .ignored ? 9 : 7))
                                                .foregroundStyle(sev == .ignored ? Color.secondary : sev == .error ? Color.red : Color.orange)
                                        }
                                        Text(displayLanguageName(language))
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(isLangIgnored ? .secondary : .primary)
                                        Text(language.uppercased())
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        if !editable {
                                            Text("(read-only)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        if !isLangIgnored, let issue = langIssues.first, langSeverity != nil {
                                            Text(issue.message)
                                                .font(.caption)
                                                .foregroundStyle(langSeverity == .error ? .red : .orange)
                                        }
                                        Spacer()
                                        if language != "en" {
                                            Button {
                                                if isLangIgnored {
                                                    ignoreStore.remove(key: session.key.key, language: language)
                                                } else {
                                                    ignoreStore.add(key: session.key.key, language: language)
                                                }
                                            } label: {
                                                Label(isLangIgnored ? "Unignore" : "Ignore", systemImage: isLangIgnored ? "eye" : "eye.slash")
                                                    .font(.caption)
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.mini)
                                            .tint(isLangIgnored ? .accentColor : .secondary)
                                        }
                                    }

                                    HStack {
                                        TextField("Translation", text: Binding(
                                            get: { editValues[language] ?? "" },
                                            set: { editValues[language] = $0 }
                                        ))
                                        .textFieldStyle(.roundedBorder)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(
                                                    isLangIgnored ? Color.clear :
                                                    langSeverity == .error ? Color.red.opacity(0.6) :
                                                    langSeverity == .warning ? Color.orange.opacity(0.5) : .clear,
                                                    lineWidth: 1.5
                                                )
                                        )
                                        .disabled(!editable || isLangIgnored)
                                        .opacity((editable && !isLangIgnored) ? 1 : 0.4)

                                        if editable && language != "en" && !isLangIgnored {
                                            Button(action: {
                                                translateField(key: session.key.key, lang: language)
                                            }) {
                                                Image(systemName: "translate")
                                            }
                                            .buttonStyle(.borderless)
                                            .disabled(isTranslating)
                                        }
                                    }

                                    if !originalValue.isEmpty {
                                        Text("Original: \(originalValue)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(minHeight: 280)

                    HStack {
                        Button("Cancel") {
                            editSession = nil
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Button("Save") {
                            prepareSaveConfirmation()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!hasSaveChanges)
                    }
                }
                .padding()
                .frame(minWidth: 520, minHeight: 420)
                .alert("Save changes?", isPresented: $showSaveConfirmation) {
                    Button("Cancel", role: .cancel) {
                        showSaveConfirmation = false
                    }
                    Button("Confirm") {
                        performSave()
                    }
                } message: {
                    Text("You changed translations for \(session.key.key). These updates will be written to the project files.")
                }
                .alert("Translation Failed", isPresented: .init(
                    get: { translateError != nil },
                    set: { if !$0 { translateError = nil } }
                )) {
                    Button("OK") { translateError = nil }
                } message: {
                    Text(translateError ?? "")
                }
            }
        }
    }

    private func translateField(key: String, lang: String) {
        isTranslating = true
        let commentOverride = editComment.isEmpty ? nil : editComment
        Task {
            do {
                let result = try await onTranslate(key, lang, commentOverride)
                await MainActor.run {
                    editValues[lang] = result
                    isTranslating = false
                }
            } catch {
                print("[Translate \(lang)] failed: \(error.localizedDescription)")
                await MainActor.run {
                    isTranslating = false
                    translateError = error.localizedDescription
                }
            }
        }
    }

    private func autoTranslateAll(key: LocalizationKey, availableLanguages: [String]) {
        isTranslating = true
        let commentOverride = editComment.isEmpty ? nil : editComment
        Task {
            var updated = editValues
            for lang in availableLanguages {
                let editable = sourceFileForLanguage(key, lang) != nil
                if editable && lang != "en" {
                    do {
                        let result = try await onTranslate(key.key, lang, commentOverride)
                        updated[lang] = result
                    } catch {
                        // ignore/fallback
                    }
                }
            }
            await MainActor.run {
                editValues = updated
                isTranslating = false
            }
        }
    }

    private func aiTranslateAll(key: LocalizationKey, availableLanguages: [String]) {
        guard let onAITranslateBatch else { return }
        let targets = availableLanguages.filter { lang in
            lang != "en" && sourceFileForLanguage(key, lang) != nil
        }
        guard !targets.isEmpty else { return }

        // Use the live English value from the edit sheet (may differ from saved catalog value)
        let sourceText = editValues["en"] ?? key.key
        let commentOverride = editComment.isEmpty ? nil : editComment

        print("[AI Translate] key=\(key.key) sourceText=\(sourceText) comment=\(commentOverride ?? "nil") targets=\(targets)")

        isTranslating = true
        Task {
            do {
                let results = try await onAITranslateBatch(key.key, sourceText, commentOverride, targets)
                print("[AI Translate] success — received \(results.count) translations")
                await MainActor.run {
                    for (lang, value) in results where !value.isEmpty {
                        editValues[lang] = value
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

    private var groupedByFile: [(file: URL, results: [KeyAuditResult])] {
        let grouped = Dictionary(grouping: results, by: \.sourceFile)
        return grouped.keys.sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
            .map { ($0, grouped[$0] ?? []) }
    }

    private func localizationRow(_ result: KeyAuditResult) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(result.key.key)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(result.englishValue)
                    .foregroundStyle(.primary)
                    .font(.subheadline)
                    .lineLimit(2)
                    .truncationMode(.tail)

                if let comment = result.comment, !comment.isEmpty {
                    Label(comment, systemImage: "text.bubble")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                if !result.issues.isEmpty {
                    DisclosureGroup("Issues (\(result.issues.count))") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(result.issues) { issue in
                                Text(issue.message)
                                    .font(.caption2)
                                    .foregroundStyle(color(for: issue.severity))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .font(.caption)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                AuditBadgeView(severity: result.highestSeverity)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        ForEach(nonEnglishLanguages, id: \.self) { language in
                            languageChip(language: language, result: result)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxWidth: 420)

                HStack(spacing: 8) {
                    Button {
                        openEditSession(for: result)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)

                    Button {
                        onToggleIgnore(result.key)
                    } label: {
                        Label(result.issues.contains(where: { $0.severity == .ignored }) ? "Unignore" : "Ignore", systemImage: result.issues.contains(where: { $0.severity == .ignored }) ? "eye" : "eye.slash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)

                    Button(role: .destructive) {
                        let files = onAffectedFiles(result.key)
                        deleteConfirmation = DeleteConfirmation(key: result.key, affectedFiles: files)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
            .frame(minWidth: 140)
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.03), radius: 1, x: 0, y: 1)
        .contextMenu {
            Button("Edit Translations") {
                openEditSession(for: result)
            }
            Button(result.issues.contains(where: { $0.severity == .ignored }) ? "Stop Ignoring Key" : "Ignore This Key") {
                onToggleIgnore(result.key)
            }
            Divider()
            Button("Delete Key", role: .destructive) {
                let files = onAffectedFiles(result.key)
                deleteConfirmation = DeleteConfirmation(key: result.key, affectedFiles: files)
            }
        }
    }

    private var nonEnglishLanguages: [String] {
        languages.filter { $0 != "en" }
    }

    private func languageChip(language: String, result: KeyAuditResult) -> some View {
        let value = result.translations[language]
        let isLangIgnored = ignoreStore.entries.contains(where: { $0.key == result.key.key && ($0.language == language || $0.language == nil) })
        let severity: AuditSeverity = {
            if isLangIgnored { return .ignored }
            if result.issues.contains(where: { $0.language == language && $0.severity == .error }) { return .error }
            if result.issues.contains(where: { $0.language == language && $0.severity == .warning }) { return .warning }
            if value != nil { return .ok }
            return .warning
        }()
        return HStack(spacing: 4) {
            Text(language.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isLangIgnored ? .secondary : .primary)

            if !isLangIgnored, let value, !value.isEmpty {
                Text(value)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.secondary)
            }

            if isLangIgnored {
                Image(systemName: "eye.slash")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            } else {
                Circle()
                    .fill(color(for: severity))
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isLangIgnored ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.ultraThinMaterial))
        .clipShape(Capsule())
        .opacity(isLangIgnored ? 0.6 : 1)
    }

    private func color(for severity: AuditSeverity) -> Color {
        switch severity {
        case .error: return .red
        case .warning: return .orange
        case .ignored: return .secondary
        case .ok: return .green
        }
    }

    private func openEditSession(for result: KeyAuditResult) {
        let values = languages.reduce(into: [String: String]()) { accumulator, language in
            accumulator[language] = language == "en" ? result.englishValue : (result.translations[language] ?? "")
        }
        editValues = values
        editComment = result.comment ?? ""
        editSession = EditSession(key: result.key, availableLanguages: languages, originalValues: values, originalComment: result.comment ?? "", issues: result.issues)
    }

    private func sortedLanguages(session: EditSession) -> [String] {
        session.availableLanguages.sorted { a, b in
            let rank: (String) -> Int = { lang in
                if lang == "en" { return 0 }
                let ignored = ignoreStore.entries.contains(where: { $0.key == session.key.key && ($0.language == lang || $0.language == nil) })
                if ignored { return 10 }
                let issues = session.issues.filter { $0.language == lang }
                if issues.contains(where: { $0.severity == .error }) { return 1 }
                if issues.contains(where: { $0.severity == .warning }) { return 2 }
                return 3
            }
            let ra = rank(a), rb = rank(b)
            if ra != rb { return ra < rb }
            return a < b
        }
    }

    private var hasSaveChanges: Bool {
        guard let session = editSession else { return false }
        if editComment != session.originalComment { return true }
        return session.availableLanguages.contains { language in
            let original = session.originalValues[language] ?? ""
            let current = editValues[language] ?? ""
            return original != current
        }
    }

    private func prepareSaveConfirmation() {
        showSaveConfirmation = true
    }

    private func performSave() {
        guard let session = editSession else { return }
        onSaveTranslations(session.key, editValues)
        if editComment != session.originalComment {
            onSaveComment(session.key, editComment)
        }
        editSession = nil
        showSaveConfirmation = false
    }

    private func displayLanguageName(_ code: String) -> String {
        let normalizedCode = code.replacingOccurrences(of: "_", with: "-")
        let locale = Locale(identifier: "en")

        if let identifierName = locale.localizedString(forIdentifier: normalizedCode), !identifierName.isEmpty {
            return identifierName.capitalized
        }

        let components = normalizedCode.split(separator: "-")
        guard let languageCode = components.first else {
            return code.uppercased()
        }

        var displayName = locale.localizedString(forLanguageCode: String(languageCode))?.capitalized ?? code.uppercased()
        if components.count > 1 {
            let regionCode = String(components[1])
            if let regionName = locale.localizedString(forRegionCode: regionCode) {
                displayName += " (\(regionName))"
            }
        }

        return displayName
    }
}

struct DeleteConfirmationSheet: View {
    let confirmation: LocalizationDetailView.DeleteConfirmation
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Delete Localization Key", systemImage: "trash")
                    .font(.headline)
                    .foregroundStyle(.red)
                Text("This will permanently remove \"\(confirmation.key.key)\" from \(confirmation.affectedFiles.count) file\(confirmation.affectedFiles.count == 1 ? "" : "s"). This cannot be undone.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Affected files:")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(confirmation.affectedFiles, id: \.self) { file in
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(file.lastPathComponent)
                                .font(.system(.caption, design: .monospaced))
                            Text(file.deletingLastPathComponent().path)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Delete", role: .destructive) {
                    onConfirm()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}

#Preview {
    LocalizationDetailView(
        results: [],
        languages: ["en", "de"],
        onToggleIgnore: { _ in },
        sourceFileForLanguage: { _, _ in nil },
        onSaveTranslations: { _, _ in },
        onSaveComment: { _, _ in },
        onTranslate: { _, _, _ async throws -> String in "" },
        onAITranslateBatch: nil,
        onAffectedFiles: { _ in [] },
        onDeleteKey: { _ in }
    )
}
