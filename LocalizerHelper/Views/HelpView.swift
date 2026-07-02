//
//  HelpView.swift
//  LocalizerHelper
//

import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    private struct Shortcut: Identifiable {
        let id = UUID()
        let keys: String
        let action: String
    }

    private let shortcuts: [Shortcut] = [
        .init(keys: "⌘ + O", action: "Open Project…"),
        .init(keys: "⇧ + ⌘ + O", action: "Open Project in New Window…"),
        .init(keys: "⌘ + R", action: "Refresh Project"),
        .init(keys: "⌘ + F", action: "Find (focus search field)"),
        .init(keys: "⌘ + L", action: "View Localization File"),
        .init(keys: "⌘ + 1", action: "Show All Strings"),
        .init(keys: "⌘ + 2", action: "Show Errors Only"),
        .init(keys: "⌘ + 3", action: "Show Warnings Only"),
        .init(keys: "⌘ + 4", action: "Show Ignored Only"),
        .init(keys: "⌘ + 5", action: "Show AI Ready Only")
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("StringPilot Help")
                        .font(.headline)
                    Text("Xcode Localization Wizard — what the app does and how to use it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    section("Overview") {
                        Text("StringPilot audits localization coverage in Xcode projects. Open a project folder to browse its file tree, inspect Swift string literals, and review `.strings` / `.xcstrings` files for missing or inconsistent translations across languages.")
                    }

                    section("Getting Started") {
                        VStack(alignment: .leading, spacing: 6) {
                            step(1, "Open Project… to pick a folder — the project is scanned recursively.")
                            step(2, "Select a file in the sidebar to inspect its Swift string literals or localization entries.")
                            step(3, "Review flagged issues — errors, warnings, and ignored strings — in the detail panel.")
                            step(4, "Fill in missing translations by hand, or use AI / free translation to fill them automatically.")
                            step(5, "Edits save directly back to the source `.strings` / `.xcstrings` files.")
                        }
                    }

                    section("Search") {
                        Text("Use the search field to filter by key, source value, or translation text. Choose a scope (All, Keys, Values, Translations) from the menu next to it, and toggle case-sensitive or whole-word matching. Results update shortly after you stop typing.")
                    }

                    section("Translation") {
                        Text("Strings with a developer comment are translated via your configured AI provider (Claude, OpenAI, Gemini, Ollama, LM Studio, or MLX) in Settings. Strings without a comment fall back to free translation services. Bulk translation can fill in all missing strings, or only the ones currently missing, across every language at once.")
                    }

                    section("Ignoring Strings") {
                        Text("Strings that shouldn't be flagged (e.g. intentionally untranslated) can be added to the ignore list, scoped per key and language.")
                    }

                    section("Finder & Xcode") {
                        Text("Any file or folder — in the sidebar, the detail header, or a file section when viewing strings from a folder — can be revealed in Finder or opened directly in Xcode. Clicking a line number in the string literal table jumps straight to that line in Xcode. Use File ▸ Open Project in Xcode (or the toolbar button) to open the whole project's `.xcworkspace` / `.xcodeproj`.")
                    }

                    section("Keyboard Shortcuts") {
                        VStack(spacing: 0) {
                            ForEach(shortcuts) { shortcut in
                                HStack {
                                    Text(shortcut.keys)
                                        .font(.system(.body, design: .monospaced))
                                        .frame(width: 90, alignment: .leading)
                                    Text(shortcut.action)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                                if shortcut.id != shortcuts.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .frame(width: 480, height: 620)
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            content()
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .trailing)
            Text(text)
        }
        .font(.callout)
    }
}

#Preview {
    HelpView()
}
