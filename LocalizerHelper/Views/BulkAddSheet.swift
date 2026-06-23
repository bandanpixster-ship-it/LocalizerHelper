//
//  BulkAddSheet.swift
//  LocalizerHelper
//
//  Created by Bandan's MacBook Pro on 23/06/26.
//


import SwiftUI

struct BulkAddSheet: View {
    let literals: [SwiftStringLiteral]
    let localizationFiles: [URL]
    let languages: [String]
    let onBulkAdd: (_ items: [(key: String, translations: [String: String], comment: String)], _ file: URL, _ progress: @escaping (Int) -> Void) async -> Void
    let onTranslate: (String, String) async throws -> String
    let onAITranslateBatch: ((String, String, String?, [String]) async throws -> [String: String])?

    @Environment(\.dismiss) private var dismiss
    @State private var selectedFile: URL?
    @State private var checkedIDs: Set<UUID> = []
    @State private var translateMode: TranslateMode = .none
    @State private var isRunning = false
    @State private var progress = 0
    @State private var resultSummary: String?

    enum TranslateMode: String, CaseIterable, Identifiable {
        case none = "None"
        case free = "Free"
        case ai   = "AI"
        var id: String { rawValue }
    }

    private var nonEnglishLanguages: [String] { languages.filter { $0 != "en" } }
    private var checkedLiterals: [SwiftStringLiteral] { literals.filter { checkedIDs.contains($0.id) } }
    private var allChecked: Bool { checkedIDs.count == literals.count }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    filePicker
                    translatePicker
                    stringList
                    if isRunning { progressSection }
                    if let summary = resultSummary { resultSection(summary) }
                }
                .padding()
            }

            Divider()

            footer
        }
        .frame(width: 500, height: 600)
        .onAppear {
            selectedFile = localizationFiles.first
            checkedIDs = Set(literals.map { $0.id })
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Add Missing Strings")
                    .font(.headline)
                Text("\(checkedIDs.count) of \(literals.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(isRunning)
        }
        .padding()
    }

    private var filePicker: some View {
        GroupBox("Target File") {
            Picker("", selection: $selectedFile) {
                ForEach(localizationFiles, id: \.self) { file in
                    Text(file.lastPathComponent).tag(URL?.some(file))
                }
            }
            .labelsHidden()
            .padding(4)
        }
    }

    @ViewBuilder
    private var translatePicker: some View {
        if !nonEnglishLanguages.isEmpty {
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 0) {
                        ForEach(availableTranslateModes) { mode in
                            translateModeButton(mode)
                        }
                    }
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

                    Text(translateModeDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(4)
            } label: {
                Text("Translation")
            }
        }
    }

    private func translateModeButton(_ mode: TranslateMode) -> some View {
        Button {
            translateMode = mode
        } label: {
            HStack(spacing: 4) {
                if mode == .ai { Image(systemName: "sparkles").font(.caption) }
                Text(mode.rawValue)
                    .font(.subheadline.weight(translateMode == mode ? .semibold : .regular))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(translateMode == mode ? Color.accentColor.opacity(0.18) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .padding(2)
    }

    private var translateModeDescription: String {
        switch translateMode {
        case .none: return "Strings will be added in English only. You can translate them individually later."
        case .free: return "Uses free translation services (MyMemory / Google). No API key needed. May be slower."
        case .ai:   return "Uses your configured AI provider to translate all \(nonEnglishLanguages.count) languages at once. Failed strings are skipped."
        }
    }

    private var availableTranslateModes: [TranslateMode] {
        if onAITranslateBatch != nil { return TranslateMode.allCases }
        return [.none, .free]
    }

    private var stringList: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                // Select all / deselect all
                HStack {
                    Button(allChecked ? "Deselect All" : "Select All") {
                        if allChecked {
                            checkedIDs = []
                        } else {
                            checkedIDs = Set(literals.map { $0.id })
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(.accentColor)
                    Spacer()
                    Text("\(checkedIDs.count) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 6)

                Divider()

                ForEach(literals) { lit in
                    HStack(spacing: 10) {
                        Toggle("", isOn: Binding(
                            get: { checkedIDs.contains(lit.id) },
                            set: { on in
                                if on { checkedIDs.insert(lit.id) }
                                else { checkedIDs.remove(lit.id) }
                            }
                        ))
                        .labelsHidden()
                        .toggleStyle(.checkbox)

                        Text(lit.localizationTemplate)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(checkedIDs.contains(lit.id) ? .primary : .secondary)

                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if checkedIDs.contains(lit.id) { checkedIDs.remove(lit.id) }
                        else { checkedIDs.insert(lit.id) }
                    }

                    if lit.id != literals.last?.id { Divider() }
                }
            }
            .padding(4)
        } label: {
            Text("Strings to Add")
        }
    }

    private var progressSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: Double(progress), total: Double(checkedLiterals.count))
                Text(translateMode != .none
                     ? "Translating and adding \(progress) of \(checkedLiterals.count)…"
                     : "Adding \(progress) of \(checkedLiterals.count)…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(4)
        }
    }

    private func resultSection(_ summary: String) -> some View {
        Label(summary, systemImage: "checkmark.circle.fill")
            .foregroundStyle(.green)
            .font(.subheadline.weight(.medium))
    }

    private var footer: some View {
        HStack {
            Spacer()
            if resultSummary != nil {
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Add \(checkedLiterals.count) String\(checkedLiterals.count == 1 ? "" : "s")") {
                    start()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(selectedFile == nil || checkedIDs.isEmpty || isRunning)
            }
        }
        .padding()
    }

    // MARK: - Action

    private func start() {
        guard let file = selectedFile else { return }
        isRunning = true
        progress = 0
        resultSummary = nil
        let selected = checkedLiterals
        let mode = translateMode

        Task {
            var items: [(key: String, translations: [String: String], comment: String)] = []
            var translatedCount = 0

            for (index, literal) in selected.enumerated() {
                let key = literal.localizationTemplate
                var translations: [String: String] = ["en": key]

                switch mode {
                case .none:
                    break

                case .free:
                    await withTaskGroup(of: (String, String?).self) { group in
                        for lang in nonEnglishLanguages {
                            group.addTask {
                                let value = try? await onTranslate(key, lang)
                                return (lang, value)
                            }
                        }
                        for await (lang, value) in group {
                            if let v = value, !v.isEmpty { translations[lang] = v }
                        }
                    }
                    if translations.count > 1 { translatedCount += 1 }

                case .ai:
                    if let batchFn = onAITranslateBatch, !nonEnglishLanguages.isEmpty {
                        do {
                            let results = try await batchFn(key, key, nil, nonEnglishLanguages)
                            for (lang, value) in results where !value.isEmpty {
                                translations[lang] = value
                            }
                            if translations.count > 1 { translatedCount += 1 }
                        } catch {
                            print("[BulkAdd] AI translate failed for '\(key)': \(error.localizedDescription)")
                        }
                    }
                }

                items.append((key: key, translations: translations, comment: ""))
                let idx = index + 1
                await MainActor.run { progress = idx }
            }

            await onBulkAdd(items, file) { _ in }

            await MainActor.run {
                isRunning = false
                let added = items.count
                if mode != .none {
                    resultSummary = "Added \(added) string\(added == 1 ? "" : "s"), \(translatedCount) translated."
                } else {
                    resultSummary = "Added \(added) string\(added == 1 ? "" : "s")."
                }
            }
        }
    }
}
