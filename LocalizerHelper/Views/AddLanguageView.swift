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
    let onAdd: (String, URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var selectedCode: String? = nil
    @State private var selectedFile: URL?
    @State private var showAddAlert = false
    @State private var alertMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Language")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    guard let code = selectedCode, let file = selectedFile else { return }
                    // Determine appropriate message based on file type
                    if file.pathExtension.lowercased() == "strings" {
                        alertMessage = "The language '\(code)' will be added by creating a new .lproj folder and an empty .strings file. Xcode may need to be refreshed to show the folder. Proceed?"
                    } else {
                        alertMessage = "The language '\(code)' will be added to the String Catalog (\(file.lastPathComponent)). This updates the catalog file in place. Proceed?"
                    }
                    showAddAlert = true
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(selectedCode == nil || selectedFile == nil)
                .alert(isPresented: $showAddAlert) {
                    Alert(
                        title: Text("Add Language"),
                        message: Text(alertMessage),
                        primaryButton: .default(Text("Proceed")) {
                            onAdd(selectedCode!, selectedFile!)
                            dismiss()
                        },
                        secondaryButton: .cancel()
                    )
                }
            }
            .padding()

            Divider()

            // File picker (only shown when multiple files)
            if localizationFiles.count > 1 {
                Picker("Target File", selection: $selectedFile) {
                    ForEach(localizationFiles, id: \.self) { file in
                        Text(file.lastPathComponent).tag(URL?.some(file))
                    }
                }
                .padding(.horizontal)
                .padding(.top, 12)
            }

            // Search
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
            .padding(8)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal)
            .padding(.top, 12)

            // Language list
            List(filteredLanguages, selection: $selectedCode) { lang in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lang.displayName)
                            .fontWeight(selectedCode == lang.code ? .semibold : .regular)
                        Text(lang.code)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if existingLanguages.contains(lang.code) {
                        Text("Already added")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tag(lang.code)
                .disabled(existingLanguages.contains(lang.code))
            }
            .listStyle(.inset)
        }
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
