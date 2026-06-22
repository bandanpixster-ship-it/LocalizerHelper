import Foundation
import Security

enum AIProvider: String, CaseIterable, Identifiable, Codable {
    case claude = "claude"
    case openAI = "openai"
    case gemini = "gemini"
    case none = "none"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude:  return "Claude (Anthropic)"
        case .openAI:  return "OpenAI (ChatGPT)"
        case .gemini:  return "Gemini (Google)"
        case .none:    return "None — use free services"
        }
    }

    var keyLabel: String {
        switch self {
        case .claude:  return "Claude API Key"
        case .openAI:  return "OpenAI API Key"
        case .gemini:  return "Gemini API Key"
        case .none:    return ""
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

    // MARK: - API keys (Keychain)

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

    var hasAnyKey: Bool {
        (claudeKey?.isEmpty == false) ||
        (openAIKey?.isEmpty == false) ||
        (geminiKey?.isEmpty == false)
    }

    func key(for provider: AIProvider) -> String? {
        switch provider {
        case .claude:  return claudeKey
        case .openAI:  return openAIKey
        case .gemini:  return geminiKey
        case .none:    return nil
        }
    }

    func setKey(_ value: String?, for provider: AIProvider) {
        switch provider {
        case .claude:  claudeKey = value
        case .openAI:  openAIKey = value
        case .gemini:  geminiKey = value
        case .none:    break
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
