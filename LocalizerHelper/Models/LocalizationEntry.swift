//
//  LocalizationEntry.swift
//  LocalizerHelper
//
//  Created by Bandan's MacBook Pro on 17/06/26.
//


import Foundation

struct LocalizationKey: Hashable, Codable {
    let key: String
    let tableName: String
}

struct LocalizationEntry: Identifiable, Hashable {
    let id: UUID
    let key: LocalizationKey
    let language: String
    let value: String
    let sourceFile: URL
    let comment: String?

    init(
        id: UUID = UUID(),
        key: LocalizationKey,
        language: String,
        value: String,
        sourceFile: URL,
        comment: String? = nil
    ) {
        self.id = id
        self.key = key
        self.language = language
        self.value = value
        self.sourceFile = sourceFile
        self.comment = comment
    }
}

struct LocalizationCatalog {
    var entries: [LocalizationEntry]

    init(entries: [LocalizationEntry] = []) {
        self.entries = entries
    }

    var entriesByKey: [LocalizationKey: [LocalizationEntry]] {
        Dictionary(grouping: entries, by: \.key)
    }

    var entriesByFile: [URL: [LocalizationEntry]] {
        Dictionary(grouping: entries, by: \.sourceFile)
    }

    var languages: [String] {
        Array(Set(entries.map(\.language))).sorted()
    }

    func entriesForNode(_ node: FileNode) -> [LocalizationEntry] {
        if node.isDirectory {
            let urls = Set(collectLocalizationFileURLs(in: node))
            return entries.filter { urls.contains($0.sourceFile) }
        }
        guard node.fileKind == .strings || node.fileKind == .xcstrings else { return [] }
        return entries.filter { $0.sourceFile == node.url }
    }

    func entry(for key: LocalizationKey, language: String) -> LocalizationEntry? {
        entries.first { $0.key == key && $0.language == language }
    }

    mutating func replacingEntries(for sourceFile: URL, with newEntries: [LocalizationEntry]) {
        entries.removeAll { $0.sourceFile == sourceFile }
        entries.append(contentsOf: newEntries)
    }

    private func collectLocalizationFileURLs(in node: FileNode) -> [URL] {
        if !node.isDirectory {
            switch node.fileKind {
            case .strings, .xcstrings: return [node.url]
            default: return []
            }
        }
        return node.children.flatMap { collectLocalizationFileURLs(in: $0) }
    }
}

extension LocalizationCatalog {
    static func build(from root: FileNode, parsers: LocalizationParsers = .init()) -> LocalizationCatalog {
        var allEntries: [LocalizationEntry] = []
        collectEntries(from: root, into: &allEntries, parsers: parsers)
        return LocalizationCatalog(entries: allEntries)
    }

    private static func collectEntries(
        from node: FileNode,
        into entries: inout [LocalizationEntry],
        parsers: LocalizationParsers
    ) {
        if !node.isDirectory {
            switch node.fileKind {
            case .strings:
                if let parsed = try? parsers.strings.parse(node.url) {
                    entries.append(contentsOf: parsed)
                }
            case .xcstrings:
                if let parsed = try? parsers.xcstrings.parse(fileURL: node.url) {
                    entries.append(contentsOf: parsed)
                }
            default:
                break
            }
            return
        }
        for child in node.children {
            collectEntries(from: child, into: &entries, parsers: parsers)
        }
    }
}

struct LocalizationParsers: Sendable {
    var strings: StringsParser = StringsParser()
    var xcstrings: XCStringsParser = XCStringsParser()
}
