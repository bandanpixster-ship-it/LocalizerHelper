import Foundation
import os.log

struct TranslationService {
    private static let logger = Logger(subsystem: "com.LocalizerHelper.TranslationService", category: "Translation")
    static let shared = TranslationService()

    // MyMemory free tier: 5 000 chars/day, no key required.
    private static let myMemoryBase = "https://api.mymemory.translated.net/get"

    // Google Translate unofficial public endpoint — no key required, rate-limited per IP.
    private static let googleBase = "https://translate.googleapis.com/translate_a/single"

    // LibreTranslate public instance — open-source, no key required on this instance.
    private static let libreTranslateBase = "https://translate.fedilab.app/translate"

    func translate(text: String, to language: String) async throws -> String {
        do {
            return try await translateViaMyMemory(text: text, to: language)
        } catch {
            Self.logger.debug("MyMemory failed (\(error.localizedDescription, privacy: .public)), falling back to Google Translate")
            do {
                return try await translateViaGoogle(text: text, to: language)
            } catch {
                Self.logger.debug("Google Translate failed (\(error.localizedDescription, privacy: .public)), falling back to LibreTranslate")
                return try await translateViaLibreTranslate(text: text, to: language)
            }
        }
    }

    // MARK: - MyMemory

    private func translateViaMyMemory(text: String, to language: String) async throws -> String {
        let targetCode = normalizedLanguageCode(language)
        var components = URLComponents(string: Self.myMemoryBase)!
        components.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "langpair", value: "en|\(targetCode)")
        ]
        guard let url = components.url else { throw TranslationError.invalidURL }

        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw TranslationError.httpError(http.statusCode)
        }
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let responseData = json["responseData"] as? [String: Any],
            let translated = responseData["translatedText"] as? String
        else {
            throw TranslationError.unexpectedResponse
        }

        if let status = json["responseStatus"] as? Int, status == 403 {
            throw TranslationError.quotaExceeded
        }

        // MyMemory echoes back the source when the language pair is unsupported
        if translated.lowercased() == text.lowercased() {
            throw TranslationError.unsupportedLanguagePair(targetCode)
        }

        Self.logger.debug("Translated '\(text, privacy: .public)' → '\(translated, privacy: .public)' via MyMemory (en→\(targetCode, privacy: .public))")
        return translated
    }

    // MARK: - Google Translate (unofficial public endpoint)

    private func translateViaGoogle(text: String, to language: String) async throws -> String {
        let targetCode = normalizedLanguageCode(language)
        var components = URLComponents(string: Self.googleBase)!
        components.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: "en"),
            URLQueryItem(name: "tl", value: targetCode),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "q", value: text)
        ]
        guard let url = components.url else { throw TranslationError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw TranslationError.httpError(http.statusCode)
        }

        // Response: [ [ ["translated","source",...], ... ], null, "en", ... ]
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [Any],
            let segments = root.first as? [[Any]]
        else {
            throw TranslationError.unexpectedResponse
        }

        let translated = segments.compactMap { $0.first as? String }.joined()
        guard !translated.isEmpty else {
            throw TranslationError.unsupportedLanguagePair(targetCode)
        }

        Self.logger.debug("Translated '\(text, privacy: .public)' → '\(translated, privacy: .public)' via Google (en→\(targetCode, privacy: .public))")
        return translated
    }

    // MARK: - LibreTranslate (open-source, public instance fallback)

    private func translateViaLibreTranslate(text: String, to language: String) async throws -> String {
        let targetCode = normalizedLanguageCode(language)
        guard let url = URL(string: Self.libreTranslateBase) else { throw TranslationError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = ["q": text, "source": "en", "target": targetCode, "format": "text"]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw TranslationError.httpError(http.statusCode)
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let translated = json["translatedText"] as? String,
            !translated.isEmpty
        else {
            throw TranslationError.unexpectedResponse
        }

        Self.logger.debug("Translated '\(text, privacy: .public)' → '\(translated, privacy: .public)' via LibreTranslate (en→\(targetCode, privacy: .public))")
        return translated
    }

    // MARK: - Language code normalisation

    private func normalizedLanguageCode(_ code: String) -> String {
        let lower = code.lowercased().replacingOccurrences(of: "_", with: "-")
        switch lower {
        case "zh-hans", "zh-cn": return "zh-CN"
        case "zh-hant", "zh-tw": return "zh-TW"
        case "pt-br":            return "pt-BR"
        case "pt-pt", "pt":      return "pt-PT"
        default:
            return String(lower.prefix(2))
        }
    }
}

// MARK: - Errors

enum TranslationError: LocalizedError {
    case invalidURL
    case httpError(Int)
    case unexpectedResponse
    case unsupportedLanguagePair(String)
    case quotaExceeded

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Could not construct translation request URL."
        case .httpError(let code):
            return "Translation service returned HTTP \(code)."
        case .unexpectedResponse:
            return "Translation service returned an unrecognised response."
        case .unsupportedLanguagePair(let lang):
            return "Language '\(lang)' is not supported by either translation service."
        case .quotaExceeded:
            return "Daily translation quota exceeded (5 000 chars/day on the free tier)."
        }
    }
}
