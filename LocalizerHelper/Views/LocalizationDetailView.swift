import SwiftUI

struct LocalizationDetailView: View {
    let results: [KeyAuditResult]
    let languages: [String]
    let onToggleIgnore: (LocalizationKey) -> Void
    let sourceFileForLanguage: (LocalizationKey, String) -> URL?
    let onSaveTranslations: (LocalizationKey, [String: String]) -> Void

    let onTranslate: (String, String) async throws -> String

    @State private var editSession: EditSession?
    @State private var editValues: [String: String] = [:]
    @State private var showSaveConfirmation = false
    @State private var isTranslating = false

    struct EditSession: Identifiable, Equatable {
        let id = UUID()
        let key: LocalizationKey
        let availableLanguages: [String]
        let originalValues: [String: String]
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
                } else {
                    editValues = [:]
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
                            Button("Auto-Translate All") {
                                autoTranslateAll(key: session.key, availableLanguages: session.availableLanguages)
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(session.availableLanguages, id: \.self) { language in
                                let editable = sourceFileForLanguage(session.key, language) != nil
                                let originalValue = session.originalValues[language] ?? ""
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(displayLanguageName(language))
                                            .font(.subheadline.weight(.semibold))
                                        Text(language.uppercased())
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        if !editable {
                                            Text("(read-only)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    
                                    HStack {
                                        TextField("Translation", text: Binding(
                                            get: { editValues[language] ?? "" },
                                            set: { editValues[language] = $0 }
                                        ))
                                        .textFieldStyle(.roundedBorder)
                                        .disabled(!editable)
                                        .opacity(editable ? 1 : 0.5)

                                        if editable && language != "en" {
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
            }
        }
    }

    private func translateField(key: String, lang: String) {
        isTranslating = true
        Task {
            do {
                let result = try await onTranslate(key, lang)
                await MainActor.run {
                    editValues[lang] = result
                    isTranslating = false
                }
            } catch {
                await MainActor.run {
                    isTranslating = false
                }
            }
        }
    }

    private func autoTranslateAll(key: LocalizationKey, availableLanguages: [String]) {
        isTranslating = true
        Task {
            var updated = editValues
            for lang in availableLanguages {
                let editable = sourceFileForLanguage(key, lang) != nil
                if editable && lang != "en" {
                    do {
                        let result = try await onTranslate(key.key, lang)
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

                HStack(alignment: .top, spacing: 8) {
                    Text(result.englishValue)
                        .foregroundStyle(.primary)
                        .font(.subheadline)
                        .lineLimit(2)
                        .truncationMode(.tail)

                    Button {
                        openEditSession(for: result)
                    } label: {
                        Image(systemName: "pencil")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.accentColor)
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

                Button {
                    onToggleIgnore(result.key)
                } label: {
                    Label(result.issues.contains(where: { $0.severity == .ignored }) ? "Unignore" : "Ignore", systemImage: result.issues.contains(where: { $0.severity == .ignored }) ? "eye" : "eye.slash")
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            .frame(minWidth: 140)
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.03), radius: 1, x: 0, y: 1)
        .contextMenu {
            Button(result.issues.contains(where: { $0.severity == .ignored }) ? "Stop Ignoring Key" : "Ignore This Key") {
                onToggleIgnore(result.key)
            }
            Button("Edit Translations") {
                openEditSession(for: result)
            }
        }
    }

    private var nonEnglishLanguages: [String] {
        languages.filter { $0 != "en" }
    }

    private func languageChip(language: String, result: KeyAuditResult) -> some View {
        let value = result.translations[language]
        let severity: AuditSeverity = {
            if result.issues.contains(where: { $0.language == language && $0.severity == .error }) { return .error }
            if result.issues.contains(where: { $0.language == language && $0.severity == .warning }) { return .warning }
            if value != nil { return .ok }
            return .warning
        }()
        return HStack(spacing: 6) {
            Text(language.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary)

            if let value, !value.isEmpty {
                Text(value)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.secondary)
            }

            Circle()
                .fill(color(for: severity))
                .frame(width: 6, height: 6)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
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
        editSession = EditSession(key: result.key, availableLanguages: languages, originalValues: values)
    }

    private var hasSaveChanges: Bool {
        guard let session = editSession else { return false }
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

#Preview {
    LocalizationDetailView(
        results: [],
        languages: ["en", "de"],
        onToggleIgnore: { _ in },
        sourceFileForLanguage: { _, _ in nil },
        onSaveTranslations: { _, _ in },
        onTranslate: { _, _ async throws -> String in
            return ""
        }
    )
}
