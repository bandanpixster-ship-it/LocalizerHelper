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
                    results.append(SwiftStringLiteral(
                        id: lit.id,
                        raw: lit.raw,
                        displayPattern: lit.displayPattern,
                        hasInterpolation: lit.hasInterpolation,
                        lineNumber: lit.lineNumber,
                        sourceLine: sourceLine
                    ))
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
}
