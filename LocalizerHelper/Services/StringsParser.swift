//
//  StringsParser.swift
//  LocalizerHelper
//
//  Created by Bandan's MacBook Pro on 17/06/26.
//


import Foundation

nonisolated struct StringsParser: Sendable {
    func parse(_ fileURL: URL) throws -> [LocalizationEntry] {
        let content = try Self.readStringsFile(at: fileURL)
        let tableName = tableName(from: fileURL)
        let language = languageCode(from: fileURL)
        var entriesByKey: [String: LocalizationEntry] = [:]

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("//") { continue }
            if trimmed.hasPrefix("/*") || trimmed.hasPrefix("*") { continue }

            guard let parsed = parseLine(trimmed) else { continue }
            let key = LocalizationKey(key: parsed.key, tableName: tableName)
            entriesByKey[parsed.key] = LocalizationEntry(
                key: key,
                language: language,
                value: parsed.value,
                sourceFile: fileURL
            )
        }

        return Array(entriesByKey.values)
    }

    private func parseLine(_ line: String) -> (key: String, value: String)? {
        guard let eqRange = line.range(of: "=") else { return nil }
        let keyPart = line[..<eqRange.lowerBound].trimmingCharacters(in: .whitespaces)
        var valuePart = line[eqRange.upperBound...].trimmingCharacters(in: .whitespaces)
        if valuePart.hasSuffix(";") {
            valuePart = String(valuePart.dropLast()).trimmingCharacters(in: .whitespaces)
        }
        guard let key = parseQuotedString(keyPart), let value = parseQuotedString(valuePart) else {
            return nil
        }
        return (key, value)
    }

    private func parseQuotedString(_ text: String) -> String? {
        guard text.first == "\"", text.last == "\"", text.count >= 2 else { return nil }
        let inner = String(text.dropFirst().dropLast())
        return unescape(inner)
    }

    private func unescape(_ text: String) -> String {
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            let char = text[index]
            if char == "\\" {
                let next = text.index(after: index)
                guard next < text.endIndex else {
                    result.append(char)
                    break
                }
                switch text[next] {
                case "n": result.append("\n")
                case "t": result.append("\t")
                case "r": result.append("\r")
                case "\"": result.append("\"")
                case "\\": result.append("\\")
                default: result.append(text[next])
                }
                index = text.index(after: next)
            } else {
                result.append(char)
                index = text.index(after: index)
            }
        }
        return result
    }

    // .strings files can be UTF-8, UTF-16 (BOM or LE/BE), or macOS Roman.
    // Try each in order; UTF-16 is the Xcode-generated default.
    private static func readStringsFile(at url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        for encoding: String.Encoding in [.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian, .macOSRoman, .isoLatin1] {
            if let string = String(data: data, encoding: encoding) {
                return string
            }
        }
        throw CocoaError(.fileReadUnknownStringEncoding)
    }

    private func tableName(from url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        return name.isEmpty ? "Localizable" : name
    }

    private func languageCode(from url: URL) -> String {
        guard let lproj = url.deletingLastPathComponent().lastPathComponent as String?,
              lproj.hasSuffix(".lproj") else { return "en" }
        let code = String(lproj.dropLast(6))
        if code == "Base" { return "en" }
        return code
    }
}
