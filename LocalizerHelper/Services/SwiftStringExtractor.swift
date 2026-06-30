//
//  SwiftStringExtractor.swift
//  LocalizerHelper
//
//  Created by Bandan's MacBook Pro on 17/06/26.
//


import Foundation

struct SwiftStringExtractor: Sendable {
    func extract(from source: String) -> [SwiftStringLiteral] {
        let sourceLines = source.components(separatedBy: "\n")
        var results: [SwiftStringLiteral] = []
        var index = source.startIndex
        var lineNumber = 1

        while index < source.endIndex {
            let char = source[index]

            if char == "\n" {
                lineNumber += 1
                index = source.index(after: index)
                continue
            }

            if char == "\"" {
                let isMultiline = source[index...].hasPrefix("\"\"\"")
                if let extracted = isMultiline
                    ? extractMultilineLiteral(from: source, start: index, lineNumber: lineNumber)
                    : extractSingleLineLiteral(from: source, start: index, lineNumber: lineNumber)
                {
                    let sourceLine = lineNumber <= sourceLines.count
                    ? sourceLines[lineNumber - 1].trimmingCharacters(in: .whitespaces)
                    : ""
                    let lit = extracted.literal
                    let trimmedDisplay = lit.displayPattern.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !isNonLocalizableContent(trimmedDisplay)
                        && !isHexString(trimmedDisplay)
                        && !isImageOrColorLiteral(in: source, before: index)
                        && !isInsideLoggingCall(in: source, before: index) {
                        results.append(SwiftStringLiteral(
                            id: lit.id,
                            raw: lit.raw,
                            displayPattern: lit.displayPattern,
                            hasInterpolation: lit.hasInterpolation,
                            lineNumber: lit.lineNumber,
                            sourceLine: sourceLine
                        ))
                    }
                    index = extracted.endIndex
                    lineNumber += extracted.newlinesCrossed
                    continue
                }
            }

            index = source.index(after: index)
        }

        return results
    }

    func extract(fileURL: URL) throws -> [SwiftStringLiteral] {
        let source = try String(contentsOf: fileURL, encoding: .utf8)
        return extract(from: source)
    }

    private struct ExtractedLiteral {
        let literal: SwiftStringLiteral
        let endIndex: String.Index
        let newlinesCrossed: Int
    }

    private func extractSingleLineLiteral(
        from source: String,
        start: String.Index,
        lineNumber: Int
    ) -> ExtractedLiteral? {
        var index = source.index(after: start)
        var content = ""
        var display = ""
        var hasInterpolation = false
        var newlines = 0

        while index < source.endIndex {
            let char = source[index]

            if char == "\\" {
                let next = source.index(after: index)
                guard next < source.endIndex else { break }
                let escaped = source[next]
                switch escaped {
                case "n":
                    content.append("\\n")
                    display.append("\n")
                case "t":
                    content.append("\\t")
                    display.append("\t")
                case "r":
                    content.append("\\r")
                case "\"":
                    content.append("\\\"")
                    display.append("\"")
                case "\\":
                    content.append("\\\\")
                    display.append("\\")
                case "(":
                    if let interpolation = readInterpolation(from: source, start: next) {
                        hasInterpolation = true
                        content.append("\\(\(interpolation.raw))")
                        display.append("{\(interpolation.display)}")
                        index = interpolation.endIndex
                        continue
                    } else {
                        content.append("\\(")
                        display.append("(")
                    }
                default:
                    content.append("\\")
                    content.append(escaped)
                    display.append(escaped)
                }
                index = source.index(after: next)
                continue
            }

            if char == "\"" {
                let raw = "\"\(content)\""
                let end = source.index(after: index)
                return ExtractedLiteral(
                    literal: SwiftStringLiteral(
                        raw: raw,
                        displayPattern: display,
                        hasInterpolation: hasInterpolation,
                        lineNumber: lineNumber
                    ),
                    endIndex: end,
                    newlinesCrossed: newlines
                )
            }

            if char == "\n" {
                newlines += 1
            }

            content.append(char)
            display.append(char)
            index = source.index(after: index)
        }

        return nil
    }

    private func extractMultilineLiteral(
        from source: String,
        start: String.Index,
        lineNumber: Int
    ) -> ExtractedLiteral? {
        var index = source.index(start, offsetBy: 3)
        var content = ""
        var display = ""
        var hasInterpolation = false
        var newlines = 0

        while index < source.endIndex {
            if source[index...].hasPrefix("\"\"\"") {
                let raw = "\"\"\"\(content)\"\"\""
                let end = source.index(index, offsetBy: 3)
                return ExtractedLiteral(
                    literal: SwiftStringLiteral(
                        raw: raw,
                        displayPattern: display.trimmingCharacters(in: .whitespacesAndNewlines),
                        hasInterpolation: hasInterpolation,
                        lineNumber: lineNumber
                    ),
                    endIndex: end,
                    newlinesCrossed: newlines
                )
            }

            if source[index] == "\\" {
                let next = source.index(after: index)
                guard next < source.endIndex else { break }
                if source[next] == "(" {
                    if let interpolation = readInterpolation(from: source, start: next) {
                        hasInterpolation = true
                        content.append("\\(\(interpolation.raw))")
                        display.append("{\(interpolation.display)}")
                        index = interpolation.endIndex
                        continue
                    }
                }
            }

            if source[index] == "\n" {
                newlines += 1
            }

            content.append(source[index])
            display.append(source[index])
            index = source.index(after: index)
        }

        return nil
    }

    private struct InterpolationResult {
        let raw: String
        let display: String
        let endIndex: String.Index
    }

    private func readInterpolation(from source: String, start: String.Index) -> InterpolationResult? {
        guard source[start] == "(" else { return nil }
        var depth = 0
        var index = start
        var raw = ""
        var display = ""
        var inString = false
        var stringDelimiter: Character?

        while index < source.endIndex {
            let char = source[index]
            raw.append(char)

            if inString {
                if char == "\\" {
                    let next = source.index(after: index)
                    if next < source.endIndex {
                        raw.append(source[next])
                        display.append(source[next])
                        index = next
                    }
                } else if char == stringDelimiter {
                    inString = false
                    stringDelimiter = nil
                }
                index = source.index(after: index)
                continue
            }

            switch char {
            case "\"", "'":
                inString = true
                stringDelimiter = char
            case "(":
                depth += 1
                if depth > 1 { display.append(char) }
            case ")":
                depth -= 1
                if depth == 0 {
                    let end = source.index(after: index)
                    let innerDisplay = display.trimmingCharacters(in: .whitespacesAndNewlines)
                    return InterpolationResult(raw: raw, display: innerDisplay.isEmpty ? "…" : innerDisplay, endIndex: end)
                }
                display.append(char)
            default:
                if depth > 0 { display.append(char) }
            }

            index = source.index(after: index)
        }

        return nil
    }

    // MARK: - Non-Localizable Content Filter

    /// Returns true for strings that are clearly not human-readable text requiring localization.
    /// Kept conservative — only cuts obvious non-text to avoid hiding real strings.
    private func isNonLocalizableContent(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        // Single character — too short to be user-facing text
        if trimmed.count == 1 { return true }

        // Pure numeric (integers, floats, hex literals like 0xFF)
        if trimmed.allSatisfy({ $0.isNumber || $0 == "." || $0 == "-" || $0 == "x" || $0 == "X" }) { return true }

        // URLs
        let urlPrefixes = ["http://", "https://", "ftp://", "file://"]
        if urlPrefixes.contains(where: { trimmed.hasPrefix($0) }) { return true }

        // File paths (absolute or home-relative)
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~/") { return true }

        // File extension only (e.g. ".swift", ".json")
        if trimmed.hasPrefix(".") && !trimmed.contains(" ") && trimmed.count <= 10 { return true }

        // Bundle identifier pattern: all-lowercase with 2+ dot-separated segments, no spaces
        // e.g. "com.example.app", "com.apple.foundation"
        if !trimmed.contains(" ") {
            let parts = trimmed.split(separator: ".")
            if parts.count >= 3 && parts.allSatisfy({ seg in
                !seg.isEmpty && seg.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
            }) && parts[0].allSatisfy({ $0.isLowercase || $0.isNumber }) {
                return true
            }
        }

        return false
    }

    // MARK: - Image, Color, and Hex Filtering Helpers

    private func isHexString(_ text: String) -> Bool {
        guard text.hasPrefix("#") else { return false }
        let hexChars = text.dropFirst()
        guard hexChars.count == 3 || hexChars.count == 4 || hexChars.count == 6 || hexChars.count == 8 else { return false }
        return hexChars.allSatisfy { $0.isHexDigit }
    }

    private func isImageOrColorLiteral(in source: String, before index: String.Index) -> Bool {
        var cur = index
        while cur > source.startIndex {
            let prev = source.index(before: cur)
            let char = source[prev]
            if char.isWhitespace {
                cur = prev
            } else {
                break
            }
        }

        guard cur > source.startIndex else { return false }
        let prevCharIndex = source.index(before: cur)
        let prevChar = source[prevCharIndex]

        if prevChar == "(" {
            return checkSymbolBeforeParen(in: source, before: prevCharIndex)
        } else if prevChar == ":" {
            return checkLabelAndSymbolBeforeColon(in: source, before: prevCharIndex)
        }

        return false
    }

    private func extractPrecedingIdentifier(in source: String, before index: String.Index) -> (identifier: String, nextIndex: String.Index)? {
        var cur = index
        while cur > source.startIndex {
            let prev = source.index(before: cur)
            if source[prev].isWhitespace {
                cur = prev
            } else {
                break
            }
        }

        var idChars: [Character] = []
        while cur > source.startIndex {
            let prev = source.index(before: cur)
            let char = source[prev]
            if char.isLetter || char.isNumber || char == "_" || char == "." {
                idChars.append(char)
                cur = prev
            } else {
                break
            }
        }

        if idChars.isEmpty { return nil }
        let identifier = String(idChars.reversed())
        return (identifier, cur)
    }

    private func checkSymbolBeforeParen(in source: String, before parenIndex: String.Index) -> Bool {
        guard let symbolResult = extractPrecedingIdentifier(in: source, before: parenIndex) else {
            return false
        }

        let symbol = symbolResult.identifier
        let skipSymbols = ["Image", "UIImage", "NSImage", "Color", "UIColor", "NSColor"]
        for skipSymbol in skipSymbols {
            if symbol == skipSymbol || symbol.hasSuffix("." + skipSymbol) {
                return true
            }
        }

        let skipLowercased = [".image", ".color", "image", "color"]
        for skipLower in skipLowercased {
            if symbol == skipLower || symbol.hasSuffix("." + skipLower) {
                return true
            }
        }

        return false
    }

    private func checkLabelAndSymbolBeforeColon(in source: String, before colonIndex: String.Index) -> Bool {
        guard let labelResult = extractPrecedingIdentifier(in: source, before: colonIndex) else {
            return false
        }

        let label = labelResult.identifier

        // These labels always carry asset/symbol names regardless of the outer function
        // e.g. Label("Title", systemImage: "gear"), Button(..., systemImage: "plus")
        let alwaysSkipLabels = ["systemName", "systemImage"]
        if alwaysSkipLabels.contains(label) { return true }

        let imageOrColorLabels = ["named", "resourceName", "image", "color"]
        guard imageOrColorLabels.contains(label) else {
            return false
        }

        var cur = labelResult.nextIndex
        while cur > source.startIndex {
            let prev = source.index(before: cur)
            if source[prev].isWhitespace {
                cur = prev
            } else {
                break
            }
        }

        guard cur > source.startIndex else { return false }
        let prevCharIndex = source.index(before: cur)
        let prevChar = source[prevCharIndex]
        if prevChar == "(" {
            return checkSymbolBeforeParen(in: source, before: prevCharIndex)
        }

        return false
    }

    // MARK: - Logging Call Filter

    private func isInsideLoggingCall(in source: String, before index: String.Index) -> Bool {
        let loggingFunctions: Set<String> = [
            "print", "Swift.print",
            "debugPrint", "Swift.debugPrint",
            "NSLog",
            "os_log", "os_signpost",
            "Logger.debug", "Logger.info", "Logger.warning",
            "Logger.error", "Logger.critical", "Logger.fault",
            "Logger.notice", "Logger.log",
            "log.debug", "log.info", "log.warning",
            "log.error", "log.critical", "log.fault",
            "log.notice", "log.log"
        ]

        // Suffix components of dot-method logging functions, e.g. ".debug", ".info"
        // Used to match custom logger instances like `myLogger.debug(...)`
        let loggingMethodSuffixes: Set<String> = [
            "debug", "info", "warning", "error", "critical", "fault", "notice", "log"
        ]

        // Scan backwards to find the nearest unmatched opening paren
        var depth = 0
        var cur = index

        while cur > source.startIndex {
            cur = source.index(before: cur)
            let char = source[cur]

            switch char {
            case ")":
                depth += 1
            case "(":
                if depth == 0 {
                    guard let result = extractPrecedingIdentifier(in: source, before: cur) else {
                        return false
                    }
                    let callee = result.identifier

                    // Direct match against known logging functions
                    if loggingFunctions.contains(callee) { return true }

                    // Suffix match: anything ending in a known logging method name
                    // e.g. `myLogger.debug`, `appLog.error`
                    if let dotRange = callee.range(of: ".", options: .backwards) {
                        let suffix = String(callee[callee.index(after: dotRange.lowerBound)...])
                        if loggingMethodSuffixes.contains(suffix) { return true }
                    }

                    return false
                } else {
                    depth -= 1
                }
            default:
                break
            }
        }

        return false
    }
}
