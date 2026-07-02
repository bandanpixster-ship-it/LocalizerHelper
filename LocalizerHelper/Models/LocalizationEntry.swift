//
//  LocalizationEntry.swift
//  LocalizerHelper
//
//  Created by Bandan's MacBook Pro on 17/06/26.
//


import Foundation

nonisolated struct LocalizationKey: Hashable, Codable {
    let key: String
    let tableName: String
}

nonisolated struct LocalizationEntry: Identifiable, Hashable {
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

nonisolated struct LocalizationCatalog {
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

nonisolated extension LocalizationCatalog {
    // Each localization file is parsed independently, so files are parsed concurrently
    // via a task group rather than one at a time — this is the CPU/IO-bound step for
    // large projects (many .strings/.xcstrings files) and parallelizes cleanly.
    static func build(from root: FileNode, parsers: LocalizationParsers = .init(), progress: ScanProgressCounter? = nil) async -> LocalizationCatalog {
        let files = localizationFileNodes(in: root)

        let allEntries = await withTaskGroup(of: [LocalizationEntry].self) { group in
            for file in files {
                group.addTask {
                    defer { progress?.increment() }
                    switch file.fileKind {
                    case .strings:
                        return (try? parsers.strings.parse(file.url)) ?? []
                    case .xcstrings:
                        return (try? parsers.xcstrings.parse(fileURL: file.url)) ?? []
                    default:
                        return []
                    }
                }
            }
            var all: [LocalizationEntry] = []
            for await batch in group {
                all.append(contentsOf: batch)
            }
            return all
        }

        return LocalizationCatalog(entries: allEntries)
    }

    static func localizationFileNodes(in node: FileNode) -> [FileNode] {
        if !node.isDirectory {
            switch node.fileKind {
            case .strings, .xcstrings: return [node]
            default: return []
            }
        }
        return node.children.flatMap { localizationFileNodes(in: $0) }
    }
}

nonisolated struct LocalizationParsers: Sendable {
    var strings: StringsParser = StringsParser()
    var xcstrings: XCStringsParser = XCStringsParser()
}
