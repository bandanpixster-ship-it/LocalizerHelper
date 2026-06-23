//
//  AISettingsView.swift
//  LocalizerHelper
//
//  Created by Bandan's MacBook Pro on 22/06/26.
//


import SwiftUI

struct AISettingsView: View {
    @State private var settings = AISettings.shared
    @State private var keyDraft: [AIProvider: String] = [:]
    @State private var keyVisible: [AIProvider: Bool] = [:]
    @State private var testResult: [AIProvider: TestState] = [:]
    @State private var localState: [AIProvider: LocalProviderState] = [:]

    enum TestState: Equatable {
        case idle, testing, success, failure(String)

        var label: String {
            switch self {
            case .idle:    return "Test"
            case .testing: return "Testing…"
            case .success: return "OK"
            case .failure: return "Failed"
            }
        }

        var color: Color {
            switch self {
            case .success: return .green
            case .failure: return .red
            default:       return .secondary
            }
        }
    }

    struct LocalProviderState {
        var baseURLDraft: String = ""
        var models: [String] = []
        var isFetching = false
        var fetchError: String?
        var testState: TestState = .idle
    }

    private let cloudProviders: [AIProvider] = [.claude, .openAI, .gemini]
    private let localProviders: [AIProvider] = [.ollama, .lmStudio, .mlx]

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
                Text("AI translation is used only when a string has a developer comment. Strings without comments use the free translation chain.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Divider().padding(.vertical, 4)

            if settings.preferredProvider.isLocalServer {
                localProviderSection(for: settings.preferredProvider)
            } else {
                Section {
                    ForEach(cloudProviders) { provider in
                        apiKeyRow(for: provider)
                    }
                } header: {
                    Text("API Keys").fontWeight(.semibold)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            loadDrafts()
            for p in localProviders {
                localState[p] = LocalProviderState(baseURLDraft: settings.baseURL(for: p))
            }
            if settings.preferredProvider.isLocalServer {
                fetchModels(for: settings.preferredProvider)
            }
        }
        .onChange(of: settings.preferredProvider) { _, new in
            if new.isLocalServer {
                if localState[new] == nil {
                    localState[new] = LocalProviderState(baseURLDraft: settings.baseURL(for: new))
                }
                if localState[new]?.models.isEmpty == true {
                    fetchModels(for: new)
                }
            }
        }
    }

    // MARK: - Local provider section

    @ViewBuilder
    private func localProviderSection(for provider: AIProvider) -> some View {
        let state = Binding<LocalProviderState>(
            get: { localState[provider] ?? LocalProviderState(baseURLDraft: settings.baseURL(for: provider)) },
            set: { localState[provider] = $0 }
        )

        Section {
            VStack(alignment: .leading, spacing: 12) {
                // Base URL
                HStack {
                    Text("Base URL")
                        .frame(width: 70, alignment: .leading)
                        .foregroundStyle(.secondary)
                    TextField(provider.defaultBaseURL, text: state.baseURLDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .onSubmit { saveBaseURL(for: provider, state: state) }
                    Button("Save") { saveBaseURL(for: provider, state: state) }
                        .disabled(
                            state.wrappedValue.baseURLDraft == settings.baseURL(for: provider) ||
                            state.wrappedValue.baseURLDraft.isEmpty
                        )
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }

                Divider()

                // Model picker
                HStack {
                    Text("Model")
                        .frame(width: 70, alignment: .leading)
                        .foregroundStyle(.secondary)

                    if state.wrappedValue.models.isEmpty {
                        Text(
                            state.wrappedValue.isFetching ? "Fetching models…" :
                            state.wrappedValue.fetchError != nil ? "Could not connect" :
                            "No models found"
                        )
                        .foregroundStyle(.secondary)
                    } else {
                        let modelBinding = Binding<String>(
                            get: { settings.localModel(for: provider) },
                            set: { settings.setLocalModel($0, for: provider) }
                        )
                        Picker("", selection: modelBinding) {
                            Text("Select a model").tag("")
                            ForEach(state.wrappedValue.models, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .labelsHidden()
                    }

                    Spacer()

                    Button { fetchModels(for: provider) } label: {
                        if state.wrappedValue.isFetching {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise").font(.caption)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(state.wrappedValue.isFetching)
                    .help("Fetch available models from the running \(provider.displayName) instance")
                }

                if let err = state.wrappedValue.fetchError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }

                Divider()

                // Test
                HStack {
                    Spacer()
                    if state.wrappedValue.testState == .testing {
                        ProgressView().controlSize(.small)
                    }
                    Button(state.wrappedValue.testState.label) { testLocalProvider(provider, state: state) }
                        .disabled(settings.localModel(for: provider).isEmpty || state.wrappedValue.testState == .testing)
                        .foregroundStyle(state.wrappedValue.testState.color)
                    if state.wrappedValue.testState == .success {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                    if case .failure(let msg) = state.wrappedValue.testState {
                        Text(msg).font(.caption).foregroundStyle(.red)
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text(provider.displayName).fontWeight(.semibold)
        } footer: {
            Text(footerText(for: provider))
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    private func footerText(for provider: AIProvider) -> String {
        switch provider {
        case .ollama:
            return "Ollama runs locally — no API key required. Install from ollama.com and run `ollama pull llama3.1` to get started."
        case .lmStudio:
            return "LM Studio runs locally — no API key required. Open LM Studio, load a model, and start the local server on port 1234."
        case .mlx:
            return "MLX runs on Apple Silicon — no API key required. Start the server with `mlx_lm.server --model <model>` (default port 8080)."
        default:
            return ""
        }
    }

    // MARK: - Cloud API key rows

    @ViewBuilder
    private func apiKeyRow(for provider: AIProvider) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(provider.keyLabel)
                .font(.subheadline)
                .foregroundStyle(.primary)

            HStack(spacing: 8) {
                Group {
                    if keyVisible[provider] == true {
                        TextField("", text: draftBinding(for: provider), prompt: Text("Paste key here"))
                    } else {
                        SecureField("", text: draftBinding(for: provider), prompt: Text("Paste key here"))
                    }
                }
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

                Button(keyVisible[provider] == true ? "Hide" : "Show") {
                    keyVisible[provider] = !(keyVisible[provider] ?? false)
                }
                .frame(width: 44)

                Button(testResult[provider]?.label ?? "Test") { testKey(for: provider) }
                    .disabled(draftIsEmpty(provider) || testResult[provider] == .testing)
                    .foregroundStyle(testResult[provider]?.color ?? .accentColor)

                if isDirty(provider) {
                    Button("Save") { saveKey(for: provider) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(testResult[provider] == .testing)
                }
            }

            // Reserve a fixed height so layout doesn't shift when test result appears/clears
            Group {
                if case .failure(let msg) = testResult[provider] {
                    Text(msg).font(.caption).foregroundStyle(.red)
                } else {
                    Text(" ").font(.caption)
                }
            }
            .frame(minHeight: 16, alignment: .leading)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Local provider helpers

    private func fetchModels(for provider: AIProvider) {
        localState[provider, default: LocalProviderState(baseURLDraft: settings.baseURL(for: provider))].isFetching = true
        localState[provider]?.fetchError = nil
        Task {
            do {
                let models = try await AISettings.shared.fetchModels(for: provider)
                await MainActor.run {
                    localState[provider]?.models = models
                    localState[provider]?.isFetching = false
                    if !models.isEmpty && settings.localModel(for: provider).isEmpty {
                        settings.setLocalModel(models[0], for: provider)
                    }
                }
            } catch {
                await MainActor.run {
                    localState[provider]?.fetchError = "Could not reach \(provider.displayName) at \(settings.baseURL(for: provider)). Make sure it is running."
                    localState[provider]?.isFetching = false
                }
            }
        }
    }

    private func saveBaseURL(for provider: AIProvider, state: Binding<LocalProviderState>) {
        settings.setBaseURL(state.wrappedValue.baseURLDraft, for: provider)
        localState[provider]?.models = []
        fetchModels(for: provider)
    }

    private func testLocalProvider(_ provider: AIProvider, state: Binding<LocalProviderState>) {
        localState[provider]?.testState = .testing
        Task {
            do {
                try await TranslationService.shared.test(provider: provider, apiKey: "")
                await MainActor.run { localState[provider]?.testState = .success }
            } catch {
                await MainActor.run { localState[provider]?.testState = .failure(error.localizedDescription) }
            }
        }
    }

    // MARK: - Cloud key helpers

    private func draftBinding(for provider: AIProvider) -> Binding<String> {
        Binding(
            get: { keyDraft[provider] ?? "" },
            set: { keyDraft[provider] = $0; testResult[provider] = .idle }
        )
    }

    private func draftIsEmpty(_ provider: AIProvider) -> Bool {
        (keyDraft[provider] ?? "").isEmpty
    }

    private func isDirty(_ provider: AIProvider) -> Bool {
        let draft = keyDraft[provider] ?? ""
        let saved = settings.key(for: provider) ?? ""
        return draft != saved && !draft.isEmpty
    }

    private func loadDrafts() {
        for provider in cloudProviders {
            keyDraft[provider] = settings.key(for: provider) ?? ""
        }
    }

    private func saveKey(for provider: AIProvider) {
        settings.setKey(keyDraft[provider], for: provider)
        keyDraft[provider] = settings.key(for: provider) ?? ""
    }

    private func testKey(for provider: AIProvider) {
        guard let key = keyDraft[provider], !key.isEmpty else { return }
        testResult[provider] = .testing
        Task {
            do {
                try await TranslationService.shared.test(provider: provider, apiKey: key)
                await MainActor.run { testResult[provider] = .success }
            } catch {
                await MainActor.run { testResult[provider] = .failure(error.localizedDescription) }
            }
        }
    }
}
