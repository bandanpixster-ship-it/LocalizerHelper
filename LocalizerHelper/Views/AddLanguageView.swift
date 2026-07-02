//
//  AddLanguageView.swift
//  LocalizerHelper
//
//  Created by Bandan's MacBook Pro on 23/06/26.
//


import SwiftUI

struct AddLanguageView: View {
    let localizationFiles: [URL]
    let existingLanguages: [String]
    let onAdd: ([String], URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var selectedCodes: Set<String> = []
    @State private var selectedFile: URL?
    @State private var showAddAlert = false
    @State private var alertMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add Language")
                        .font(.headline)
                    Text("Choose one or more languages and the localization file to update.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(selectedCodes.count > 1 ? "Add (\(selectedCodes.count))" : "Add") {
                    guard !selectedCodes.isEmpty, let file = selectedFile else { return }
                    let codeList = selectedCodes.sorted().joined(separator: ", ")
                    if file.pathExtension.lowercased() == "strings" {
                        alertMessage = selectedCodes.count > 1
                            ? "\(selectedCodes.count) languages (\(codeList)) will each get a new .lproj folder and empty .strings file. Xcode may need to be refreshed to show them. Proceed?"
                            : "The language '\(codeList)' will be added by creating a new .lproj folder and an empty .strings file. Xcode may need to be refreshed to show the folder. Proceed?"
                    } else {
                        alertMessage = selectedCodes.count > 1
                            ? "\(selectedCodes.count) languages (\(codeList)) will be added to the String Catalog (\(file.lastPathComponent)). This updates the catalog file in place. Proceed?"
                            : "The language '\(codeList)' will be added to the String Catalog (\(file.lastPathComponent)). This updates the catalog file in place. Proceed?"
                    }
                    showAddAlert = true
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(selectedCodes.isEmpty || selectedFile == nil)
                .alert(isPresented: $showAddAlert) {
                    Alert(
                        title: Text("Add Language"),
                        message: Text(alertMessage),
                        primaryButton: .default(Text("Proceed")) {
                            guard let file = selectedFile else { return }
                            onAdd(Array(selectedCodes), file)
                            dismiss()
                        },
                        secondaryButton: .cancel()
                    )
                }
            }
            .padding(16)
            .background(.ultraThinMaterial)

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                if localizationFiles.count > 1 {
                    GroupBox("Target File") {
                        Picker("Target File", selection: $selectedFile) {
                            ForEach(localizationFiles, id: \.self) { file in
                                Text(file.lastPathComponent).tag(URL?.some(file))
                            }
                        }
                        .labelsHidden()
                    }
                    .modernCard(padding: 12)
                }

                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search languages…", text: $search)
                        .textFieldStyle(.plain)
                    if !search.isEmpty {
                        Button { search = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                HStack {
                    Text("⌘-click or shift-click to select multiple languages")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !selectedCodes.isEmpty {
                        Text("\(selectedCodes.count) selected")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 0)

            // `List` is already independently scrollable — nesting it inside a `ScrollView`
            // (as before) made it collapse to near-zero height on macOS, hiding every row.
            // A `Set` selection binding lets the user cmd/shift-click to pick several languages.
            List(filteredLanguages, selection: $selectedCodes) { lang in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lang.displayName)
                            .fontWeight(selectedCodes.contains(lang.code) ? .semibold : .regular)
                        Text(lang.code)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if existingLanguages.contains(lang.code) {
                        Text("Already added")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.thinMaterial, in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
                .tag(lang.code)
                .disabled(existingLanguages.contains(lang.code))
                .padding(.vertical, 4)
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .background(.clear)
            .modernCard(padding: 12)
            .padding(16)
            .frame(maxHeight: .infinity)
        }
        .background(
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.04),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .frame(width: 380, height: 520)
        .onAppear {
            selectedFile = localizationFiles.first
        }
    }

    private var filteredLanguages: [LanguageOption] {
        let all = LanguageOption.all
        guard !search.isEmpty else { return all }
        let q = search.lowercased()
        return all.filter {
            $0.displayName.lowercased().contains(q) || $0.code.lowercased().contains(q)
        }
    }
}
