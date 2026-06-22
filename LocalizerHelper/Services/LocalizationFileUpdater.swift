import Foundation
import os.log

struct LocalizationFileUpdater {
    enum UpdateError: LocalizedError {
        case unsupportedFileType
        case keyNotFound(key: String)
        case languageNotFound(language: String)
        case invalidFileContents(reason: String)
        case writeFailed(reason: String)
        case fileAccessDenied(path: String)
        case fileNotFound(path: String)

        var errorDescription: String? {
            switch self {
            case .unsupportedFileType:
                return "Unsupported localization file type."
            case .keyNotFound(let key):
                return "Key '\(key)' could not be found in the file."
            case .languageNotFound(let language):
                return "Language '\(language)' entry could not be found in the file."
            case .invalidFileContents(let reason):
                return "File contents are invalid: \(reason)"
            case .writeFailed(let reason):
                return "Could not save changes to the file: \(reason)"
            case .fileAccessDenied(let path):
                return "No permission to write to: \(path)"
            case .fileNotFound(let path):
                return "File not found: \(path)"
            }
        }
    }

    private let logger = Logger(subsystem: "com.LocalizerHelper.FileUpdater", category: "Updates")

    func updateTranslation(in fileURL: URL, key: String, language: String, newValue: String) throws {
        logger.debug("Attempting to update translation: key=\(key, privacy: .public) language=\(language, privacy: .public) file=\(fileURL.path, privacy: .public)")

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else {
            logger.error("File not found at: \(fileURL.path, privacy: .public)")
            throw UpdateError.fileNotFound(path: fileURL.path)
        }

        guard fileManager.isWritableFile(atPath: fileURL.path) else {
            logger.error("No write permission for: \(fileURL.path, privacy: .public)")
            throw UpdateError.fileAccessDenied(path: fileURL.path)
        }

        let extensionName = fileURL.pathExtension.lowercased()
        logger.debug("File type: \(extensionName, privacy: .public)")

        switch extensionName {
        case "strings":
            try updateStringsFile(fileURL: fileURL, key: key, newValue: newValue)
        case "xcstrings":
            try updateXCStringsFile(fileURL: fileURL, key: key, language: language, newValue: newValue)
        default:
            logger.error("Unsupported file type: \(extensionName, privacy: .public)")
            throw UpdateError.unsupportedFileType
        }

        logger.info("Successfully updated translation for key=\(key, privacy: .public) in language=\(language, privacy: .public)")
    }

    func addTranslation(to fileURL: URL, key: String, translations: [String: String], comment: String = "") throws {
        logger.debug("Attempting to add translation: key=\(key, privacy: .public) to file=\(fileURL.path, privacy: .public)")

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else {
            logger.error("File not found at: \(fileURL.path, privacy: .public)")
            throw UpdateError.fileNotFound(path: fileURL.path)
        }

        guard fileManager.isWritableFile(atPath: fileURL.path) else {
            logger.error("No write permission for: \(fileURL.path, privacy: .public)")
            throw UpdateError.fileAccessDenied(path: fileURL.path)
        }

        let extensionName = fileURL.pathExtension.lowercased()
        switch extensionName {
        case "strings":
            let language = fileURL.deletingLastPathComponent().pathExtension == "lproj"
                ? fileURL.deletingLastPathComponent().deletingPathExtension().lastPathComponent
                : "en"
            let value = translations[language] ?? translations["en"] ?? key
            try addToStringsFile(fileURL: fileURL, key: key, value: value, comment: comment)
        case "xcstrings":
            try addToXCStringsFile(fileURL: fileURL, key: key, translations: translations, comment: comment)
        default:
            logger.error("Unsupported file type: \(extensionName, privacy: .public)")
            throw UpdateError.unsupportedFileType
        }

        logger.info("Successfully added key=\(key, privacy: .public) to file=\(fileURL.path, privacy: .public)")
    }

    private func addToStringsFile(fileURL: URL, key: String, value: String, comment: String = "") throws {
        logger.debug("Adding key to .strings file: \(fileURL.path, privacy: .public)")
        var content = try String(contentsOf: fileURL, encoding: .utf8)

        // Check for duplicates
        let escapedKey = NSRegularExpression.escapedPattern(for: key)
        let pattern = #"(?m)^([ \t]*)"# + escapedKey + #"\"[ \t]*=[ \t]*\"((?:\\.|[^\\\"\\])*)\"[ \t]*;"#
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        if let regex = try? NSRegularExpression(pattern: pattern, options: []),
           regex.firstMatch(in: content, options: [], range: range) != nil {
            throw UpdateError.invalidFileContents(reason: "Key '\(key)' already exists in this file.")
        }

        if !content.hasSuffix("\n") && !content.isEmpty {
            content.append("\n")
        }
        if !comment.isEmpty { content.append("/* \(comment) */\n") }
        content.append("\"\(escapeStringsValue(key))\" = \"\(escapeStringsValue(value))\";\n")
        try write(content: content, to: fileURL)
    }

    private func addToXCStringsFile(fileURL: URL, key: String, translations: [String: String], comment: String = "") throws {
        logger.debug("Adding key to .xcstrings file: \(fileURL.path, privacy: .public)")
        let data = try Data(contentsOf: fileURL)
        guard var json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw UpdateError.invalidFileContents(reason: "Failed to parse JSON structure of .xcstrings file.")
        }

        var strings = json["strings"] as? [String: Any] ?? [String: Any]()

        if strings[key] != nil {
            throw UpdateError.invalidFileContents(reason: "Key '\(key)' already exists in this file.")
        }

        var localizations = [String: Any]()
        for (lang, val) in translations {
            localizations[lang] = [
                "stringUnit": [
                    "state": "translated",
                    "value": val
                ]
            ]
        }

        var newEntry: [String: Any] = [
            "extractionState": "manual",
            "localizations": localizations
        ]
        if !comment.isEmpty { newEntry["comment"] = comment }

        strings[key] = newEntry
        json["strings"] = strings

        let outputData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try outputData.write(to: fileURL, options: .atomic)
    }

    private func updateStringsFile(fileURL: URL, key: String, newValue: String) throws {
        logger.debug("Updating .strings file: \(fileURL.path, privacy: .public)")
        do {
            var content = try String(contentsOf: fileURL, encoding: .utf8)
            logger.debug("Read file successfully, length: \(content.count, privacy: .public) characters")

            guard let updated = replaceStringsValue(in: content, key: key, newValue: newValue) else {
                logger.error("Failed to find key in .strings file: \(key, privacy: .public)")
                throw UpdateError.keyNotFound(key: key)
            }
            try write(content: updated, to: fileURL)
        } catch let error as UpdateError {
            throw error
        } catch {
            logger.error("Error reading .strings file: \(error.localizedDescription, privacy: .public)")
            throw UpdateError.writeFailed(reason: error.localizedDescription)
        }
    }

    private func updateXCStringsFile(fileURL: URL, key: String, language: String, newValue: String) throws {
        logger.debug("Updating .xcstrings file: \(fileURL.path, privacy: .public) for language: \(language, privacy: .public)")
        let data = try Data(contentsOf: fileURL)
        guard var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UpdateError.invalidFileContents(reason: "Failed to parse JSON structure of .xcstrings file.")
        }
        guard var strings = json["strings"] as? [String: Any],
              var entry = strings[key] as? [String: Any] else {
            throw UpdateError.keyNotFound(key: key)
        }
        var localizations = entry["localizations"] as? [String: Any] ?? [:]
        localizations[language] = ["stringUnit": ["state": "translated", "value": newValue]]
        entry["localizations"] = localizations
        strings[key] = entry
        json["strings"] = strings
        let outputData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try outputData.write(to: fileURL, options: .atomic)
        logger.info("Successfully updated language '\(language, privacy: .public)' for key '\(key, privacy: .public)'")
    }

    func updateComment(in fileURL: URL, key: String, comment: String) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw UpdateError.fileNotFound(path: fileURL.path)
        }
        guard fileManager.isWritableFile(atPath: fileURL.path) else {
            throw UpdateError.fileAccessDenied(path: fileURL.path)
        }
        switch fileURL.pathExtension.lowercased() {
        case "xcstrings":
            try updateCommentInXCStringsFile(fileURL: fileURL, key: key, comment: comment)
        case "strings":
            try updateCommentInStringsFile(fileURL: fileURL, key: key, comment: comment)
        default:
            throw UpdateError.unsupportedFileType
        }
    }

    private func updateCommentInXCStringsFile(fileURL: URL, key: String, comment: String) throws {
        let data = try Data(contentsOf: fileURL)
        guard var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var strings = json["strings"] as? [String: Any],
              var entry = strings[key] as? [String: Any] else {
            throw UpdateError.keyNotFound(key: key)
        }
        if comment.isEmpty {
            entry.removeValue(forKey: "comment")
        } else {
            entry["comment"] = comment
        }
        strings[key] = entry
        json["strings"] = strings
        let outputData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try outputData.write(to: fileURL, options: .atomic)
    }

    private func updateCommentInStringsFile(fileURL: URL, key: String, comment: String) throws {
        var content = try String(contentsOf: fileURL, encoding: .utf8)
        let escapedKey = NSRegularExpression.escapedPattern(for: key)

        // Pattern: optional existing comment line + the key line
        let pattern = #"([ \t]*\/\*[^\n]*\n)?([ \t]*""# + escapedKey + #""[ \t]*=[ \t]*"(?:[^"\\]|\\.)*"[ \t]*;[ \t]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            throw UpdateError.invalidFileContents(reason: "Failed to compile comment regex.")
        }

        let nsContent = content as NSString
        let nsRange = NSRange(content.startIndex..<content.endIndex, in: content)
        guard let match = regex.firstMatch(in: content, range: nsRange),
              let fullRange = Range(match.range, in: content) else {
            throw UpdateError.keyNotFound(key: key)
        }

        let keyLine = String(content[Range(match.range(at: 2), in: content)!])
        let replacement = comment.isEmpty ? keyLine : "/* \(comment) */\n\(keyLine)"
        content.replaceSubrange(fullRange, with: replacement)
        _ = nsContent // suppress unused warning
        try write(content: content, to: fileURL)
    }

    func deleteKey(from fileURL: URL, key: String) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw UpdateError.fileNotFound(path: fileURL.path)
        }
        guard fileManager.isWritableFile(atPath: fileURL.path) else {
            throw UpdateError.fileAccessDenied(path: fileURL.path)
        }
        switch fileURL.pathExtension.lowercased() {
        case "strings":
            try deleteFromStringsFile(fileURL: fileURL, key: key)
        case "xcstrings":
            try deleteFromXCStringsFile(fileURL: fileURL, key: key)
        default:
            throw UpdateError.unsupportedFileType
        }
        logger.info("Deleted key '\(key, privacy: .public)' from \(fileURL.lastPathComponent, privacy: .public)")
    }

    private func deleteFromStringsFile(fileURL: URL, key: String) throws {
        var content = try String(contentsOf: fileURL, encoding: .utf8)
        let escapedKey = NSRegularExpression.escapedPattern(for: key)
        // Match optional preceding comment line + the key = value; line + trailing newline
        let pattern = #"(?:[ \t]*\/\*[^\n]*\n)?[ \t]*""# + escapedKey + #""[ \t]*=[ \t]*"(?:[^"\\]|\\.)*"[ \t]*;[ \t]*\n?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            throw UpdateError.invalidFileContents(reason: "Failed to compile delete regex.")
        }
        let nsRange = NSRange(content.startIndex..<content.endIndex, in: content)
        guard let match = regex.firstMatch(in: content, range: nsRange),
              let matchRange = Range(match.range, in: content) else {
            throw UpdateError.keyNotFound(key: key)
        }
        content.removeSubrange(matchRange)
        try write(content: content, to: fileURL)
    }

    private func deleteFromXCStringsFile(fileURL: URL, key: String) throws {
        let data = try Data(contentsOf: fileURL)
        guard var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var strings = json["strings"] as? [String: Any] else {
            throw UpdateError.invalidFileContents(reason: "Failed to parse JSON.")
        }
        guard strings[key] != nil else {
            throw UpdateError.keyNotFound(key: key)
        }
        strings.removeValue(forKey: key)
        json["strings"] = strings
        let outputData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try outputData.write(to: fileURL, options: .atomic)
    }

    private func write(content: String, to fileURL: URL) throws {
        logger.debug("Writing content to file: \(fileURL.path, privacy: .public)")
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            logger.debug("File written successfully, size: \(content.count, privacy: .public) bytes")
        } catch {
            logger.error("Write failed: \(error.localizedDescription, privacy: .public)")
            throw UpdateError.writeFailed(reason: error.localizedDescription)
        }
    }

    private func replaceStringsValue(in content: String, key: String, newValue: String) -> String? {
        logger.debug("Searching for .strings key: \(key, privacy: .public)")
        let escapedKey = NSRegularExpression.escapedPattern(for: key)
        let pattern = #"(?m)^([ \t]*)"# + escapedKey + #""[ \t]*=[ \t]*"((?:\.|[^\"\])*)"[ \t]*;(.*)$"#

        logger.debug("Pattern: \(pattern, privacy: .public)")

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            logger.error("Failed to compile regex pattern for key: \(key, privacy: .public)")
            return nil
        }

        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        guard let match = regex.firstMatch(in: content, options: [], range: range) else {
            logger.error("No match found in .strings file for key: \(key, privacy: .public)")
            return nil
        }

        guard let valueRange = Range(match.range(at: 2), in: content) else {
            logger.error("Could not convert match range to String.Index for key: \(key, privacy: .public)")
            return nil
        }

        let currentValue = String(content[valueRange])
        logger.debug("Found value for key \(key, privacy: .public): current=\(currentValue, privacy: .public) new=\(newValue, privacy: .public)")

        let escapedValue = escapeStringsValue(newValue)
        var updated = content
        updated.replaceSubrange(valueRange, with: escapedValue)
        return updated
    }

    private func escapeStringsValue(_ value: String) -> String {
        var escaped = ""
        for character in value {
            switch character {
            case "\\": escaped.append("\\\\")
            case "\"": escaped.append("\\\"")
            case "\n": escaped.append("\\n")
            case "\t": escaped.append("\\t")
            case "\r": escaped.append("\\r")
            default: escaped.append(character)
            }
        }
        return escaped
    }

}
