import SwiftUI

struct AISettingsView: View {
    @State private var settings = AISettings.shared
    @State private var keyDraft: [AIProvider: String] = [:]
    @State private var keyVisible: [AIProvider: Bool] = [:]
    @State private var testResult: [AIProvider: TestState] = [:]

    enum TestState: Equatable {
        case idle, testing, success, failure(String)

        var label: String {
            switch self {
            case .idle:          return "Test"
            case .testing:       return "Testing…"
            case .success:       return "OK"
            case .failure:       return "Failed"
            }
        }

        var color: Color {
            switch self {
            case .success:       return .green
            case .failure:       return .red
            default:             return .secondary
            }
        }
    }

    private let providers: [AIProvider] = [.claude, .openAI, .gemini]

    var body: some View {
        Form {
            Section {
                Picker("Preferred provider", selection: $settings.preferredProvider) {
                    ForEach(AIProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.radioGroup)
            } header: {
                Text("Provider").fontWeight(.semibold)
            } footer: {
                Text("AI translation is used only when a string has a developer comment in the .xcstrings file. Strings without comments always use the free translation chain.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Divider().padding(.vertical, 4)

            Section {
                ForEach(providers) { provider in
                    apiKeyRow(for: provider)
                }
            } header: {
                Text("API Keys").fontWeight(.semibold)
            }
        }
        .formStyle(.grouped)
        .onAppear { loadDrafts() }
    }

    @ViewBuilder
    private func apiKeyRow(for provider: AIProvider) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(provider.keyLabel)
                .font(.subheadline)
                .foregroundStyle(.primary)

            HStack(spacing: 8) {
                Group {
                    if keyVisible[provider] == true {
                        TextField(
                            "",
                            text: draftBinding(for: provider),
                            prompt: Text("Paste key here")
                        )
                    } else {
                        SecureField(
                            "",
                            text: draftBinding(for: provider),
                            prompt: Text("Paste key here")
                        )
                    }
                }
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

                Button(keyVisible[provider] == true ? "Hide" : "Show") {
                    keyVisible[provider] = !(keyVisible[provider] ?? false)
                }
                .frame(width: 44)

                // Test: directly validates the draft key against this specific provider.
                Button(testResult[provider]?.label ?? "Test") {
                    testKey(for: provider)
                }
                .disabled(draftIsEmpty(provider) || testResult[provider] == .testing)
                .foregroundStyle(testResult[provider]?.color ?? .accentColor)

                // Save only appears when the draft differs from what's stored in Keychain.
                if isDirty(provider) {
                    Button("Save") {
                        saveKey(for: provider)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            if case .failure(let msg) = testResult[provider] {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func draftBinding(for provider: AIProvider) -> Binding<String> {
        Binding(
            get: { keyDraft[provider] ?? "" },
            set: { keyDraft[provider] = $0; testResult[provider] = .idle }
        )
    }

    private func draftIsEmpty(_ provider: AIProvider) -> Bool {
        (keyDraft[provider] ?? "").isEmpty
    }

    // Draft differs from what's currently saved in Keychain.
    private func isDirty(_ provider: AIProvider) -> Bool {
        let draft = keyDraft[provider] ?? ""
        let saved = settings.key(for: provider) ?? ""
        return draft != saved && !draft.isEmpty
    }

    private func loadDrafts() {
        for provider in providers {
            keyDraft[provider] = settings.key(for: provider) ?? ""
        }
    }

    private func saveKey(for provider: AIProvider) {
        settings.setKey(keyDraft[provider], for: provider)
        // Force isDirty to re-evaluate by nudging the draft to match saved.
        keyDraft[provider] = settings.key(for: provider) ?? ""
    }

    // Sends a real "Hello" → French request directly to the selected provider
    // using the current draft key, without affecting any saved state.
    private func testKey(for provider: AIProvider) {
        guard let key = keyDraft[provider], !key.isEmpty else { return }
        testResult[provider] = .testing
        Task {
            do {
                try await TranslationService.shared.test(provider: provider, apiKey: key)
                testResult[provider] = .success
            } catch {
                testResult[provider] = .failure(error.localizedDescription)
            }
        }
    }
}
