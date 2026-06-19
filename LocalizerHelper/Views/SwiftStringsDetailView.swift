import SwiftUI

struct SwiftStringsDetailView: View {
    let literals: [SwiftStringLiteral]
    let pendingLiterals: [SwiftStringLiteral]
    let localizationFiles: [URL]
    let languages: [String]
    let isKeyDuplicate: (String, URL) -> Bool
    let onAddLocalization: (String, URL, [String: String]) -> Void
    let onTranslate: (String, String) async throws -> String

    @State private var filter: Filter = .all
    @State private var sortOrder: SortOrder = .line
    @State private var selectedLiteral: SwiftStringLiteral?
    @State private var isShowingAddSheet = false

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
                                isShowingAddSheet = true
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
                }
                .padding(.horizontal, 4)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .sheet(isPresented: $isShowingAddSheet, onDismiss: { selectedLiteral = nil }) {
                if let literal = selectedLiteral {
                    AddLocalizationSheet(
                        literal: literal,
                        localizationFiles: localizationFiles,
                        languages: languages,
                        isKeyDuplicate: isKeyDuplicate,
                        onAdd: onAddLocalization,
                        onTranslate: onTranslate
                    )
                }
            }
        }
    }
}

struct AddLocalizationSheet: View {
    let literal: SwiftStringLiteral
    let localizationFiles: [URL]
    let languages: [String]
    let isKeyDuplicate: (String, URL) -> Bool
    let onAdd: (String, URL, [String: String]) -> Void
    let onTranslate: (String, String) async throws -> String

    @Environment(\.dismiss) private var dismiss

    @State private var key: String = ""
    @State private var selectedFile: URL?
    @State private var translations: [String: String] = [:]
    @State private var isTranslating = false
    @State private var validationError: String? = nil

    init(
        literal: SwiftStringLiteral,
        localizationFiles: [URL],
        languages: [String],
        isKeyDuplicate: @escaping (String, URL) -> Bool,
        onAdd: @escaping (String, URL, [String: String]) -> Void,
        onTranslate: @escaping (String, String) async throws -> String
    ) {
        self.literal = literal
        self.localizationFiles = localizationFiles
        self.languages = languages
        self.isKeyDuplicate = isKeyDuplicate
        self.onAdd = onAdd
        self.onTranslate = onTranslate

        var defaultKey = literal.raw
        if defaultKey.hasPrefix("\"\"\"") && defaultKey.hasSuffix("\"\"\"") {
            defaultKey = String(defaultKey.dropFirst(3).dropLast(3))
        } else if defaultKey.hasPrefix("\"") && defaultKey.hasSuffix("\"") {
            defaultKey = String(defaultKey.dropFirst().dropLast())
        }

        _key = State(initialValue: defaultKey)
        _selectedFile = State(initialValue: localizationFiles.first)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Localization Settings").font(.headline)) {
                    TextField("Key", text: $key)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: key) {
                            validateKey()
                        }

                    if let validationError {
                        Text(validationError)
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    Picker("Target File", selection: $selectedFile) {
                        ForEach(localizationFiles, id: \.self) { file in
                            Text(file.lastPathComponent).tag(URL?.some(file))
                        }
                    }
                    .onChange(of: selectedFile) {
                        validateKey()
                    }
                }

                Section(header: HStack {
                    Text("Translations").font(.headline)
                    Spacer()
                    if isTranslating {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Auto-Translate All") {
                            autoTranslateAll()
                        }
                        .buttonStyle(.borderless)
                        .disabled(key.isEmpty)
                    }
                }) {
                    ForEach(languages, id: \.self) { lang in
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

                            Button(action: {
                                translateField(lang)
                            }) {
                                Image(systemName: "translate")
                            }
                            .buttonStyle(.borderless)
                            .disabled(key.isEmpty || isTranslating)
                        }
                    }
                }
            }
            .padding()
            .formStyle(.grouped)
            .navigationTitle("Add to Localization")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if let selectedFile {
                            onAdd(key, selectedFile, translations)
                            dismiss()
                        }
                    }
                    .disabled(key.isEmpty || selectedFile == nil || validationError != nil)
                }
            }
            .onAppear {
                if translations["en"] == nil {
                    translations["en"] = key
                }
                validateKey()
            }
        }
        .frame(width: 480, height: 480)
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
                }
            }
        }
    }

    private func autoTranslateAll() {
        isTranslating = true
        Task {
            var updated = translations
            for lang in languages {
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
