//
//  AISettings.swift
//  LocalizerHelper
//
//  Created by Bandan's MacBook Pro on 22/06/26.
//

import Foundation
import Security

enum AIProvider: String, CaseIterable, Identifiable, Codable {
    case claude   = "claude"
    case openAI   = "openai"
    case gemini   = "gemini"
    case ollama   = "ollama"
    case lmStudio = "lmstudio"
    case mlx      = "mlx"
    case none     = "none"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude:   return "Claude (Anthropic)"
        case .openAI:   return "OpenAI (ChatGPT)"
        case .gemini:   return "Gemini (Google)"
        case .ollama:   return "Ollama (Local — Free)"
        case .lmStudio: return "LM Studio (Local — Free)"
        case .mlx:      return "MLX (Apple Silicon — Free)"
        case .none:     return "None — use free services"
        }
    }

    var keyLabel: String {
        switch self {
        case .claude:  return "Claude API Key"
        case .openAI:  return "OpenAI API Key"
        case .gemini:  return "Gemini API Key"
        default:       return ""
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .claude, .openAI, .gemini: return true
        default:                        return false
        }
    }

    var isLocalServer: Bool {
        switch self {
        case .ollama, .lmStudio, .mlx: return true
        default:                       return false
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .ollama:   return "http://localhost:11434"
        case .lmStudio: return "http://localhost:1234"
        case .mlx:      return "http://localhost:8080"
        default:        return ""
        }
    }
}

@Observable
final class AISettings {
    static let shared = AISettings()

    var preferredProvider: AIProvider {
        didSet { UserDefaults.standard.set(preferredProvider.rawValue, forKey: Keys.preferredProvider) }
    }

    private enum Keys {
        static let preferredProvider = "ai.preferredProvider"
        static let claudeKey  = "com.LocalizerHelper.ai.claude"
        static let openAIKey  = "com.LocalizerHelper.ai.openai"
        static let geminiKey  = "com.LocalizerHelper.ai.gemini"
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Keys.preferredProvider) ?? ""
        preferredProvider = AIProvider(rawValue: raw) ?? .none
    }

    // MARK: - Cloud API keys (Keychain)

    var claudeKey: String? {
        get { keychainRead(Keys.claudeKey) }
        set { keychainWrite(Keys.claudeKey, value: newValue) }
    }

    var openAIKey: String? {
        get { keychainRead(Keys.openAIKey) }
        set { keychainWrite(Keys.openAIKey, value: newValue) }
    }

    var geminiKey: String? {
        get { keychainRead(Keys.geminiKey) }
        set { keychainWrite(Keys.geminiKey, value: newValue) }
    }

    // MARK: - Local server settings (UserDefaults — not sensitive)

    func baseURL(for provider: AIProvider) -> String {
        let stored = UserDefaults.standard.string(forKey: "ai.\(provider.rawValue).baseURL")
        return stored ?? provider.defaultBaseURL
    }

    func setBaseURL(_ url: String, for provider: AIProvider) {
        UserDefaults.standard.set(url, forKey: "ai.\(provider.rawValue).baseURL")
    }

    func localModel(for provider: AIProvider) -> String {
        UserDefaults.standard.string(forKey: "ai.\(provider.rawValue).model") ?? ""
    }

    func setLocalModel(_ model: String, for provider: AIProvider) {
        UserDefaults.standard.set(model, forKey: "ai.\(provider.rawValue).model")
    }

    // MARK: - State

    var hasAnyKey: Bool {
        switch preferredProvider {
        case .ollama, .lmStudio, .mlx:
            return !localModel(for: preferredProvider).isEmpty
        case .claude: return claudeKey?.isEmpty == false
        case .openAI: return openAIKey?.isEmpty == false
        case .gemini: return geminiKey?.isEmpty == false
        case .none:   return false
        }
    }

    func key(for provider: AIProvider) -> String? {
        switch provider {
        case .claude:  return claudeKey
        case .openAI:  return openAIKey
        case .gemini:  return geminiKey
        default:       return nil
        }
    }

    func setKey(_ value: String?, for provider: AIProvider) {
        switch provider {
        case .claude:  claudeKey = value
        case .openAI:  openAIKey = value
        case .gemini:  geminiKey = value
        default:       break
        }
    }

    // MARK: - Model fetching

    /// Ollama uses its own `/api/tags` format.
    func fetchOllamaModels(baseURL: String) async throws -> [String] {
        let base = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/api/tags") else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else { return [] }
        return models.compactMap { $0["name"] as? String }.sorted()
    }

    /// LM Studio and MLX use the OpenAI-compatible `/v1/models` format.
    func fetchOpenAICompatibleModels(baseURL: String) async throws -> [String] {
        let base = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/v1/models") else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["data"] as? [[String: Any]] else { return [] }
        return models.compactMap { $0["id"] as? String }.sorted()
    }

    func fetchModels(for provider: AIProvider) async throws -> [String] {
        let url = baseURL(for: provider)
        switch provider {
        case .ollama:             return try await fetchOllamaModels(baseURL: url)
        case .lmStudio, .mlx:    return try await fetchOpenAICompatibleModels(baseURL: url)
        default:                  return []
        }
    }

    // MARK: - Keychain helpers

    private static let keychainService = "com.LocalizerHelper.AIKeys"

    private func keychainRead(_ account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      Self.keychainService,
            kSecAttrAccount:      account,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8),
              !string.isEmpty
        else { return nil }
        return string
    }

    private func keychainWrite(_ account: String, value: String?) {
        guard let value, !value.isEmpty else {
            keychainDelete(account)
            return
        }
        guard let data = value.data(using: .utf8) else { return }

        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: Self.keychainService,
            kSecAttrAccount: account
        ]
        let attributes: [CFString: Any] = [kSecValueData: data]

        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
            SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        } else {
            var item = query
            item[kSecValueData] = data
            SecItemAdd(item as CFDictionary, nil)
        }
    }

    private func keychainDelete(_ account: String) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: Self.keychainService,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
