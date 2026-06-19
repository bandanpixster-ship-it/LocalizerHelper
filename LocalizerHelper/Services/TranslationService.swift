import Foundation
import os.log

struct TranslationService {
    private static let logger = Logger(subsystem: "com.LocalizerHelper.TranslationService", category: "Translation")
    static let shared = TranslationService()

    func translate(text: String, to language: String) async throws -> String {
        // First attempt online translation via LibreTranslate (or any JSON‑API based service)
        do {
            return try await translateViaNetwork(text: text, to: language)
        } catch {
            Self.logger.error("Network translation failed: \(error.localizedDescription). Falling back to Python script.")
        }

        // Fallback: Execute bundled Python script
        guard let scriptURL = Bundle.main.url(forResource: "translate_text", withExtension: "py") ?? findScriptInBundleOrWorkspace() else {
            throw NSError(domain: "TranslationService", code: 1, userInfo: [NSLocalizedDescriptionKey: "translate_text.py script not found"])
        }

        Self.logger.debug("Executing script: \(scriptURL.path) with target: \(language)")

        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = [scriptURL.path, "--text", text, "--target", language]

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            try process.run()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                Self.logger.error("Python script failed: \(errStr)")
                throw NSError(domain: "TranslationService", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errStr.isEmpty ? "Unknown python error" : errStr])
            }

            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let outStr = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return outStr
        }.value
    }

    // MARK: - Network translation using a public API
    private func translateViaNetwork(text: String, to language: String) async throws -> String {
        // Example endpoint – LibreTranslate public instance (replace with your preferred service)
        let endpoint = URL(string: "https://libretranslate.de/translate")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "q": text,
            "source": "en",
            "target": language,
            "format": "text"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, _) = try await URLSession.shared.data(for: request)

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let translated = json["translatedText"] as? String
        else {
            throw NSError(domain: "TranslationService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid translation response"])
        }
        return translated
    }

    private func findScriptInBundleOrWorkspace() -> URL? {
        // Fallback search in working directory or main bundle path
        let fm = FileManager.default
        let bundlePath = Bundle.main.bundleURL
        let possibleUrls = [
            bundlePath.appendingPathComponent("translate_text.py"),
            bundlePath.appendingPathComponent("Contents/Resources/translate_text.py"),
            URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("LocalizerHelper/translate_text.py"),
            URL(fileURLWithPath: "/Users/bandhansdevice/Development/LocalizerHelper/LocalizerHelper/translate_text.py")
        ]
        for url in possibleUrls {
            if fm.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }
}
