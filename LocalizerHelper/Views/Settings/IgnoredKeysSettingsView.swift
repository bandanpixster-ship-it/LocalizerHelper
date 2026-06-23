//
//  IgnoredKeysSettingsView.swift
//  LocalizerHelper
//
//  Created by Bandan's MacBook Pro on 22/06/26.
//


import SwiftUI

struct IgnoredKeysSettingsView: View {
    @EnvironmentObject private var store: GlobalIgnoreStore
    @State private var showClearConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.entries.isEmpty {
                ContentUnavailableView {
                    Label("No Ignored Keys", systemImage: "checkmark.circle")
                } description: {
                    Text("Keys you ignore from the audit view will appear here.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(store.entries) {
                    TableColumn("Key") { entry in
                        Text(entry.key)
                            .font(.system(.body, design: .monospaced))
                    }
                    TableColumn("Language") { entry in
                        Text(entry.language ?? "All languages")
                            .foregroundStyle(entry.language == nil ? .secondary : .primary)
                    }
                    .width(120)
                    TableColumn("") { entry in
                        Button {
                            store.remove(key: entry.key, language: entry.language)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                    .width(30)
                }

                Divider()

                HStack {
                    Text("\(store.entries.count) ignored \(store.entries.count == 1 ? "key" : "keys")")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Spacer()
                    Button("Clear All") {
                        showClearConfirmation = true
                    }
                    .foregroundStyle(.red)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .confirmationDialog(
            "Clear all ignored keys?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                store.removeAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove \(store.entries.count) ignored \(store.entries.count == 1 ? "key" : "keys"). They will appear in audit results again.")
        }
    }
}
