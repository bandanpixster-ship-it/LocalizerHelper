//
//  TranslationService.swift
//  LocalizerHelper
//
//  Created by Bandan's MacBook Pro on 19/06/26.
//


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

    // MARK: - Public entry point

    func translate(text: String, to language: String, comment: String? = nil, key: String? = nil) async throws -> String {
        guard !isEmojiOnly(text) else { return text }

        let (protected, placeholders) = protectPlaceholders(text)

        // If a comment exists and an AI provider is configured, try AI first.
        if let comment, let key, AISettings.shared.hasAnyKey {
            do {
                let result = try await translateViaAI(text: protected, comment: comment, key: key, to: language)
                return restorePlaceholders(result, placeholders: placeholders)
            } catch {
                Self.logger.debug("AI translation failed (\(error.localizedDescription, privacy: .public)), falling back to free chain")
            }
        }

        let result = try await freeChain(text: protected, to: language)
        return restorePlaceholders(result, placeholders: placeholders)
    }

    // MARK: - Provider test (used by Settings UI to validate a key before saving)

    func test(provider: AIProvider, apiKey: String) async throws {
        // Temporarily stash the key, run one real translation, restore original.
        let original = AISettings.shared.key(for: provider)
        let originalProvider = AISettings.shared.preferredProvider
        AISettings.shared.setKey(apiKey, for: provider)
        AISettings.shared.preferredProvider = provider
        defer {
            AISettings.shared.setKey(original, for: provider)
            AISettings.shared.preferredProvider = originalProvider
        }
        let result = try await translateViaAI(text: "Hello", comment: "Settings test", key: "test", to: "fr")
        guard !result.isEmpty else { throw TranslationError.unexpectedResponse }
    }

    // MARK: - Batch AI translation (single call → all languages)

    /// Uses AI to generate a short developer comment for a localization key, given its source code line.
    func generateComment(sourceLine: String, key: String) async throws -> String {
        guard AISettings.shared.preferredProvider != .none, AISettings.shared.hasAnyKey else {
            throw TranslationError.noAIProviderConfigured
        }
        let system = "You are a developer writing comments for iOS/macOS localization keys. " +
                     "Return ONLY the comment text — one concise sentence, no quotes, no explanation."
        let user = "Write a developer comment for the localization key \"\(key)\".\n" +
                   "It appears in this Swift source line:\n\(sourceLine)"
        return try await batchAIRequest(system: system, user: user)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Translates `text` into every language in `languages` with one AI API call.
    /// Returns a dict of [languageCode: translation]. Any language missing from the
    /// response is silently omitted — callers should fall back to the free chain for those.
    func translateBatch(text: String, comment: String?, key: String, to languages: [String]) async throws -> [String: String] {
        guard !languages.isEmpty else { return [:] }
        guard AISettings.shared.preferredProvider != .none, AISettings.shared.hasAnyKey else {
            throw TranslationError.noAIProviderConfigured
        }

        let (protected, placeholders) = protectPlaceholders(text)
        let normalizedLanguages = languages.map { normalizedLanguageCode($0) }
        let langList = normalizedLanguages.joined(separator: ", ")

        let hasPlaceholders = protected.contains("__PH")
        var systemPrompt = "You are a professional iOS/macOS app localizer. Return ONLY valid JSON — no markdown, no code fences, no explanation."
        if hasPlaceholders {
            systemPrompt += " The string contains placeholder tokens like __PH0__. Copy them into every translation exactly as-is — do not translate or remove them."
        }

        var userPrompt = "Translate this iOS app string to the following languages.\n"
        userPrompt += "Key: \(key)\n"
        if let comment { userPrompt += "Context: \(comment)\n" }
        userPrompt += "String: \(protected)\n\n"
        userPrompt += "Return a JSON object with BCP-47 language codes as keys and translated strings as values:\n"
        userPrompt += "{\(normalizedLanguages.map { "\"\($0)\": \"...\"" }.joined(separator: ", "))}"

        let raw = try await batchAIRequest(system: systemPrompt, user: userPrompt)
        let parsed = try parseJSONTranslations(raw)

        // Restore placeholders in every translated value.
        return parsed.mapValues { restorePlaceholders($0, placeholders: placeholders) }
    }

    private func batchAIRequest(system: String, user: String) async throws -> String {
        var lastError: Error = TranslationError.noAIProviderConfigured
        let delays: [UInt64] = [2_000_000_000, 5_000_000_000] // 2s, 5s
        // Loop runs delays.count + 1 times: initial attempt + one retry per delay.
        for attempt in 0...delays.count {
            do {
                switch AISettings.shared.preferredProvider {
                case .claude:  return try await claudeBatchRequest(system: system, user: user)
                case .openAI:  return try await openAIBatchRequest(system: system, user: user)
                case .gemini:  return try await geminiBatchRequest(system: system, user: user)
                case .ollama, .lmStudio, .mlx:
                    let p = AISettings.shared.preferredProvider
                    return try await localServerRequest(
                        baseURL: AISettings.shared.baseURL(for: p),
                        model: AISettings.shared.localModel(for: p),
                        system: system, user: user
                    )
                case .none:    throw TranslationError.noAIProviderConfigured
                }
            } catch TranslationError.httpError(429) where attempt < delays.count {
                Self.logger.debug("AI rate limited (429), retrying in \(delays[attempt] / 1_000_000_000)s (attempt \(attempt + 1))")
                try await Task.sleep(nanoseconds: delays[attempt])
                lastError = TranslationError.httpError(429)
            } catch {
                throw error
            }
        }
        throw lastError
    }

    private func localServerRequest(baseURL: String, model: String, system: String, user: String) async throws -> String {
        guard !model.isEmpty else { throw TranslationError.missingAPIKey("local model") }
        let base = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/v1/chat/completions") else { throw TranslationError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": model,
            "stream": false,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        Self.logger.debug("[LocalServer] POST \(url.absoluteString, privacy: .public) model=\(model, privacy: .public)")
        let (data, response) = try await URLSession.shared.data(for: request)
        let rawBody = String(data: data, encoding: .utf8) ?? "<non-utf8>"
        if let http = response as? HTTPURLResponse {
            Self.logger.debug("[LocalServer] status=\(http.statusCode) body=\(rawBody, privacy: .public)")
            if !(200..<300).contains(http.statusCode) {
                throw TranslationError.httpError(http.statusCode)
            }
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = message["content"] as? String else {
            Self.logger.error("[LocalServer] unexpected response: \(rawBody, privacy: .public)")
            print("[LocalServer] unexpected response: \(rawBody)")
            throw TranslationError.unexpectedResponse
        }
        return text
    }

    private func claudeBatchRequest(system: String, user: String) async throws -> String {
        guard let apiKey = AISettings.shared.claudeKey, !apiKey.isEmpty else {
            throw TranslationError.missingAPIKey("Claude")
        }
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { throw TranslationError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": "claude-haiku-4-5",
            "max_tokens": 2048,
            "system": system,
            "messages": [["role": "user", "content": user]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw TranslationError.httpError(http.statusCode)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = (json["content"] as? [[String: Any]])?.first,
              let text = content["text"] as? String else { throw TranslationError.unexpectedResponse }
        return text
    }

    private func openAIBatchRequest(system: String, user: String) async throws -> String {
        guard let apiKey = AISettings.shared.openAIKey, !apiKey.isEmpty else {
            throw TranslationError.missingAPIKey("OpenAI")
        }
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else { throw TranslationError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw TranslationError.httpError(http.statusCode)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = message["content"] as? String else { throw TranslationError.unexpectedResponse }
        return text
    }

    private func geminiBatchRequest(system: String, user: String) async throws -> String {
        guard let apiKey = AISettings.shared.geminiKey, !apiKey.isEmpty else {
            throw TranslationError.missingAPIKey("Gemini")
        }
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else { throw TranslationError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let prompt = "\(system)\n\n\(user)"
        let body: [String: Any] = ["contents": [["parts": [["text": prompt]]]]]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw TranslationError.httpError(http.statusCode)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else { throw TranslationError.unexpectedResponse }
        return text
    }

    // Strips markdown fences if the AI wrapped the JSON, then decodes it.
    private func parseJSONTranslations(_ raw: String) throws -> [String: String] {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip markdown code fences
        if cleaned.hasPrefix("```") {
            let lines = cleaned.components(separatedBy: "\n")
            cleaned = lines.dropFirst().joined(separator: "\n")
            if cleaned.hasSuffix("```") { cleaned = String(cleaned.dropLast(3)) }
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Extract outermost JSON object in case model adds preamble text
        if let start = cleaned.firstIndex(of: "{"), let end = cleaned.lastIndex(of: "}") {
            cleaned = String(cleaned[start...end])
        }

        // Attempt parse, then retry after JSON repair if needed
        if let result = attemptJSONParse(cleaned), !result.isEmpty { return result }
        let repaired = repairJSON(cleaned)
        if let result = attemptJSONParse(repaired), !result.isEmpty { return result }

        Self.logger.error("[parseJSON] could not parse: \(cleaned, privacy: .public)")
        throw TranslationError.unexpectedResponse
    }

    private func attemptJSONParse(_ text: String) -> [String: String]? {
        guard let data = text.data(using: .utf8) else { return nil }
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] { return dict }
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return dict.compactMapValues { $0 as? String }
        }
        return nil
    }

    /// Repairs common LLM JSON output issues before parsing.
    private func repairJSON(_ json: String) -> String {
        var result = json
        // Fix missing opening quote on keys: `pt-BR": "val"` → `"pt-BR": "val"`
        // Matches a key-like token right after { or , that is missing its opening quote
        result = result.replacingOccurrences(
            of: #"(?<=[{,]\s*)([A-Za-z][A-Za-z0-9_-]*)":"#,
            with: "\"$1\":",
            options: .regularExpression
        )
        // Remove trailing commas before closing brace
        result = result.replacingOccurrences(of: #",\s*\}"#, with: "}", options: .regularExpression)
        return result
    }

    // MARK: - AI routing

    private func translateViaAI(text: String, comment: String, key: String, to language: String) async throws -> String {
        let settings = AISettings.shared
        switch settings.preferredProvider {
        case .claude:
            return try await translateViaClaude(text: text, comment: comment, key: key, to: language)
        case .openAI:
            return try await translateViaOpenAI(text: text, comment: comment, key: key, to: language)
        case .gemini:
            return try await translateViaGemini(text: text, comment: comment, key: key, to: language)
        case .ollama, .lmStudio, .mlx:
            let system = "You are a professional translator. Return ONLY the translated text, no explanation."
            let user = "Translate to \(language): \(text)"
            return try await localServerRequest(
                baseURL: settings.baseURL(for: settings.preferredProvider),
                model: settings.localModel(for: settings.preferredProvider),
                system: system, user: user
            )
        case .none:
            throw TranslationError.noAIProviderConfigured
        }
    }

    // MARK: - Claude

    private func translateViaClaude(text: String, comment: String, key: String, to language: String) async throws -> String {
        guard let apiKey = AISettings.shared.claudeKey, !apiKey.isEmpty else {
            throw TranslationError.missingAPIKey("Claude")
        }
        let targetCode = normalizedLanguageCode(language)
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw TranslationError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let prompt = buildAIPrompt(text: text, comment: comment, key: key, targetCode: targetCode)
        let body: [String: Any] = [
            "model": "claude-haiku-4-5",
            "max_tokens": 1024,
            "system": aiSystemPrompt,
            "messages": [["role": "user", "content": prompt]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw TranslationError.httpError(http.statusCode)
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = (json["content"] as? [[String: Any]])?.first,
            let translated = content["text"] as? String,
            !translated.isEmpty
        else {
            throw TranslationError.unexpectedResponse
        }

        Self.logger.debug("AI (Claude) translated key '\(key, privacy: .public)' → \(targetCode, privacy: .public)")
        return translated.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - OpenAI

    private func translateViaOpenAI(text: String, comment: String, key: String, to language: String) async throws -> String {
        guard let apiKey = AISettings.shared.openAIKey, !apiKey.isEmpty else {
            throw TranslationError.missingAPIKey("OpenAI")
        }
        let targetCode = normalizedLanguageCode(language)
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw TranslationError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let prompt = buildAIPrompt(text: text, comment: comment, key: key, targetCode: targetCode)
        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": aiSystemPrompt],
                ["role": "user", "content": prompt]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw TranslationError.httpError(http.statusCode)
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let translated = message["content"] as? String,
            !translated.isEmpty
        else {
            throw TranslationError.unexpectedResponse
        }

        Self.logger.debug("AI (OpenAI) translated key '\(key, privacy: .public)' → \(targetCode, privacy: .public)")
        return translated.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Gemini

    private func translateViaGemini(text: String, comment: String, key: String, to language: String) async throws -> String {
        guard let apiKey = AISettings.shared.geminiKey, !apiKey.isEmpty else {
            throw TranslationError.missingAPIKey("Gemini")
        }
        let targetCode = normalizedLanguageCode(language)
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else { throw TranslationError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let prompt = "\(aiSystemPrompt)\n\n\(buildAIPrompt(text: text, comment: comment, key: key, targetCode: targetCode))"
        let body: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw TranslationError.httpError(http.statusCode)
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = json["candidates"] as? [[String: Any]],
            let content = candidates.first?["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]],
            let translated = parts.first?["text"] as? String,
            !translated.isEmpty
        else {
            throw TranslationError.unexpectedResponse
        }

        Self.logger.debug("AI (Gemini) translated key '\(key, privacy: .public)' → \(targetCode, privacy: .public)")
        return translated.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - AI prompt helpers

    private var aiSystemPrompt: String {
        "You are a professional iOS/macOS app localizer. Translate UI strings accurately and naturally. " +
        "Return ONLY the translated string — no quotes, no explanation, no extra text. " +
        "Preserve any placeholder tokens like __PLACEHOLDER_0__ exactly as-is."
    }

    private func buildAIPrompt(text: String, comment: String, key: String, targetCode: String) -> String {
        "Translate to \(targetCode).\nKey: \(key)\nContext: \(comment)\nString: \(text)"
    }

    // MARK: - Free chain (Google / MyMemory / LibreTranslate)

    // Short strings (≤2 words): Google is better at single terms and common UI labels.
    // Longer strings (3+ words): MyMemory first — more stable under bulk load.
    private func freeChain(text: String, to language: String) async throws -> String {
        let wordCount = text.split(separator: " ").count
        if wordCount <= 2 {
            return try await attemptFreeChain(primary: translateViaGoogle, fallback1: translateViaMyMemory, text: text, language: language)
        } else {
            return try await attemptFreeChain(primary: translateViaMyMemory, fallback1: translateViaGoogle, text: text, language: language)
        }
    }

    private func attemptFreeChain(
        primary: (String, String) async throws -> String,
        fallback1: (String, String) async throws -> String,
        text: String,
        language: String
    ) async throws -> String {
        do {
            return try await primary(text, language)
        } catch {
            Self.logger.debug("Primary free service failed (\(error.localizedDescription, privacy: .public)), trying next")
            do {
                return try await fallback1(text, language)
            } catch {
                Self.logger.debug("Second free service failed (\(error.localizedDescription, privacy: .public)), falling back to LibreTranslate")
                return try await translateViaLibreTranslate(text, language)
            }
        }
    }

    // MARK: - MyMemory

    private func translateViaMyMemory(_ text: String, _ language: String) async throws -> String {
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

        if translated.lowercased() == text.lowercased() {
            throw TranslationError.unsupportedLanguagePair(targetCode)
        }

        Self.logger.debug("Translated via MyMemory (en→\(targetCode, privacy: .public))")
        return translated
    }

    // MARK: - Google Translate (unofficial public endpoint)

    private func translateViaGoogle(_ text: String, _ language: String) async throws -> String {
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

        Self.logger.debug("Translated via Google (en→\(targetCode, privacy: .public))")
        return translated
    }

    // MARK: - LibreTranslate (open-source, public instance — last resort)

    private func translateViaLibreTranslate(_ text: String, _ language: String) async throws -> String {
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

        Self.logger.debug("Translated via LibreTranslate (en→\(targetCode, privacy: .public))")
        return translated
    }

    // MARK: - Placeholder protection

    // Tokens like %@, %d, %1$@, %2$s get corrupted by translation APIs — swap them out first.
    private func protectPlaceholders(_ text: String) -> (protected: String, placeholders: [String]) {
        var placeholders: [String] = []
        var result = ""
        var index = text.startIndex

        // First pass: protect Swift \(...) interpolations by scanning for balanced parens
        while index < text.endIndex {
            let c = text[index]
            let next = text.index(after: index)
            if c == "\\" && next < text.endIndex && text[next] == "(" {
                var depth = 0
                var interp = "\\"
                var i = next
                while i < text.endIndex {
                    let ch = text[i]
                    interp.append(ch)
                    if ch == "(" { depth += 1 }
                    else if ch == ")" {
                        depth -= 1
                        if depth == 0 { i = text.index(after: i); break }
                    }
                    i = text.index(after: i)
                }
                let token = "__PH\(placeholders.count)__"
                placeholders.append(interp)
                result.append(contentsOf: token)
                index = i
            } else {
                result.append(c)
                index = next
            }
        }

        // Second pass: protect printf-style %d, %s, %@ placeholders
        let pattern = #"%\d+\$[a-zA-Z@]+|%[-+0-9.*]*l{0,2}[a-zA-Z@]"#
        var searchRange = result.startIndex..<result.endIndex
        while let matchRange = result.range(of: pattern, options: .regularExpression, range: searchRange) {
            let placeholder = String(result[matchRange])
            let token = "__PH\(placeholders.count)__"
            placeholders.append(placeholder)
            result.replaceSubrange(matchRange, with: token)
            let newStart = result.index(matchRange.lowerBound, offsetBy: token.count)
            searchRange = newStart..<result.endIndex
        }

        return (result, placeholders)
    }

    private func restorePlaceholders(_ text: String, placeholders: [String]) -> String {
        var result = text
        for (i, placeholder) in placeholders.enumerated() {
            result = result.replacingOccurrences(of: "__PH\(i)__", with: placeholder)
        }
        // Strip any phantom __PHx__ tokens the model hallucinated when the source had none
        result = result.replacingOccurrences(of: #"__PH\d+__\s*"#, with: "", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Emoji detection

    private func isEmojiOnly(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        return text.unicodeScalars.allSatisfy { scalar in
            !scalar.properties.isAlphabetic && scalar.properties.numericType == nil && !CharacterSet.whitespaces.contains(scalar)
        }
    }

    // MARK: - Language code normalisation

    private func normalizedLanguageCode(_ code: String) -> String {
        let lower = code.lowercased().replacingOccurrences(of: "_", with: "-")
        switch lower {
        case "zh-hans", "zh-cn", "zh-sg": return "zh-CN"
        case "zh-hant", "zh-tw", "zh-hk", "zh-mo": return "zh-TW"
        case "pt-br":            return "pt-BR"
        case "pt-pt", "pt":      return "pt-PT"
        // Legacy/alias codes Google requires
        case "he":               return "iw"
        case "nb", "no":         return "no"
        case "id", "in":         return "id"
        case "yi", "ji":         return "yi"
        case "zh":               return "zh-CN"
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
    case missingAPIKey(String)
    case noAIProviderConfigured

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Could not construct translation request URL."
        case .httpError(let code):
            if code == 429 {
                return "Rate limit reached (HTTP 429). Wait a moment and try again. Gemini free tier allows ~15 requests/min."
            }
            return "Translation service returned HTTP \(code)."
        case .unexpectedResponse:
            return "Translation service returned an unrecognised response."
        case .unsupportedLanguagePair(let lang):
            return "Language '\(lang)' is not supported by the translation service."
        case .quotaExceeded:
            return "Daily translation quota exceeded (5 000 chars/day on the free tier)."
        case .missingAPIKey(let provider):
            return "\(provider) API key is not configured. Add it in Settings → AI Translation."
        case .noAIProviderConfigured:
            return "No AI provider is selected. Choose one in Settings → AI Translation."
        }
    }
}
