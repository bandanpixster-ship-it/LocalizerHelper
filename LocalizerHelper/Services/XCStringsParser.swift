import Foundation

struct XCStringsParser: Sendable {
    func parse(fileURL: URL) throws -> [LocalizationEntry] {
        let data = try Data(contentsOf: fileURL)
        let document = try JSONDecoder().decode(XCStringsDocument.self, from: data)
        let tableName = tableName(from: fileURL)
        var entriesByKeyLanguage: [String: [String: LocalizationEntry]] = [:]

        for (key, stringEntry) in document.strings {
            guard let localizations = stringEntry.localizations else { continue }
            for (language, localization) in localizations {
                guard let value = localization.stringUnit?.value else { continue }
                let normalizedLanguage = normalizeLanguage(language)
                let locKey = LocalizationKey(key: key, tableName: tableName)
                entriesByKeyLanguage[key, default: [:]][normalizedLanguage] = LocalizationEntry(
                    key: locKey,
                    language: normalizedLanguage,
                    value: value,
                    sourceFile: fileURL,
                    comment: stringEntry.comment
                )
            }
        }

        return entriesByKeyLanguage.values.flatMap(\.values)
    }

    private func tableName(from url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        return name.isEmpty ? "Localizable" : name
    }

    private func normalizeLanguage(_ code: String) -> String {
        if code == "Base" { return "en" }
        return code
    }
}

private struct XCStringsDocument: Decodable {
    let sourceLanguage: String?
    let strings: [String: XCStringsEntry]
}

private struct XCStringsEntry: Decodable {
    let comment: String?
    let localizations: [String: XCStringsLocalization]?
}

private struct XCStringsLocalization: Decodable {
    let stringUnit: XCStringsStringUnit?
}

private struct XCStringsStringUnit: Decodable {
    let value: String
}
