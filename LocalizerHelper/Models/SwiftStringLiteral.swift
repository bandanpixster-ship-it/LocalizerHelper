//
//  SwiftStringsLiteral.swift
//  LocalizerHelper
//
//  Created by Bandan's MacBook Pro on 17/06/26.
//


import Foundation

struct SwiftStringLiteral: Identifiable, Hashable {
    let id: UUID
    let raw: String
    let displayPattern: String
    let hasInterpolation: Bool
    let lineNumber: Int
    let sourceLine: String

    init(
        id: UUID = UUID(),
        raw: String,
        displayPattern: String,
        hasInterpolation: Bool,
        lineNumber: Int,
        sourceLine: String = ""
    ) {
        self.id = id
        self.raw = raw
        self.displayPattern = displayPattern
        self.hasInterpolation = hasInterpolation
        self.lineNumber = lineNumber
        self.sourceLine = sourceLine
    }

    /// The string with Swift interpolations replaced by `%@` / `%1$@` format specifiers.
    /// Use this as the localization key and default EN value instead of `raw`.
    var localizationTemplate: String {
        // Strip surrounding quotes
        var inner = raw
        if inner.hasPrefix("\"\"\"") && inner.hasSuffix("\"\"\"") {
            inner = String(inner.dropFirst(3).dropLast(3))
        } else if inner.hasPrefix("\"") && inner.hasSuffix("\"") {
            inner = String(inner.dropFirst().dropLast())
        }
        guard hasInterpolation else { return inner }

        // Scan and replace each \(...) with a numbered placeholder first,
        // then convert to %@ (single) or %1$@, %2$@… (multiple).
        var result = ""
        var index = inner.startIndex
        var count = 0

        while index < inner.endIndex {
            let c = inner[index]
            let next = inner.index(after: index)
            if c == "\\" && next < inner.endIndex && inner[next] == "(" {
                // Skip to matching closing paren
                var depth = 0
                var i = next
                while i < inner.endIndex {
                    if inner[i] == "(" { depth += 1 }
                    else if inner[i] == ")" {
                        depth -= 1
                        if depth == 0 { i = inner.index(after: i); break }
                    }
                    i = inner.index(after: i)
                }
                count += 1
                result += "__ARG\(count)__"
                index = i
            } else {
                result.append(c)
                index = next
            }
        }

        // Single arg → plain %@; multiple → positional %1$@, %2$@…
        if count == 1 {
            return result.replacingOccurrences(of: "__ARG1__", with: "%@")
        } else {
            for i in 1...count {
                result = result.replacingOccurrences(of: "__ARG\(i)__", with: "%\(i)$@")
            }
            return result
        }
    }
}
