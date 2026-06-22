import Foundation
import os.log

struct TranslationService {
    private static let logger = Logger(subsystem: "com.LocalizerHelper.TranslationService", category: "Translation")
    static let shared = TranslationService()

    // MyMemory free tier: 5 000 chars/day, no key required.
    // Docs: https://mymemory.translated.net/doc/spec.php
    private static let myMemoryBase = "https://api.mymemory.translated.net/get"

    func translate(text: String, to language: String) async throws -> String {
        return try await translateViaMyMemory(text: text, to: language)
    }

    // MARK: - MyMemory

    private func translateViaMyMemory(text: String, to language: String) async throws -> String {
        let targetCode = normalizedLanguageCode(language)
        let langpair = "en|\(targetCode)"

        var components = URLComponents(string: Self.myMemoryBase)!
        components.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "langpair", value: langpair)
        ]

        guard let url = components.url else {
            throw TranslationError.invalidURL
        }

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

        // MyMemory echoes back the source text when the language pair is unsupported
        if translated.lowercased() == text.lowercased() {
            throw TranslationError.unsupportedLanguagePair(targetCode)
        }

        // Quota exceeded returns a message in the translated field
        if let status = json["responseStatus"] as? Int, status == 403 {
            throw TranslationError.quotaExceeded
        }

        Self.logger.debug("Translated '\(text)' → '\(translated)' [\(targetCode)]")
        return translated
    }

    // MARK: - Language code normalisation

    /// Maps Apple/Xcode locale identifiers to the BCP-47 codes MyMemory expects.
    private func normalizedLanguageCode(_ code: String) -> String {
        let lower = code.lowercased().replacingOccurrences(of: "_", with: "-")
        switch lower {
        case "zh-hans", "zh-cn": return "zh-CN"
        case "zh-hant", "zh-tw": return "zh-TW"
        case "pt-br":            return "pt-BR"
        case "pt-pt", "pt":      return "pt-PT"
        default:
            // Strip region if present (e.g. "en-US" → "en") for broad language codes
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
            return "Language '\(lang)' is not supported by the translation service."
        case .quotaExceeded:
            return "Daily translation quota exceeded (5 000 chars/day on the free tier)."
        }
    }
}
