//
//  ProjectScanner.swift
//  LocalizerHelper
//
//  Created by Bandan's MacBook Pro on 17/06/26.
//


import Foundation

nonisolated struct ProjectScanner: Sendable {
    static let excludedDirectoryNames: Set<String> = [
        "Pods", "DerivedData", ".git",
        "build", ".build",       // Xcode custom build output & Swift PM
        "Carthage",              // Carthage dependencies
    ]

    func scan(at rootURL: URL, progress: ScanProgressCounter? = nil) async throws -> FileNode {
        let name = rootURL.lastPathComponent
        return try await scanNode(at: rootURL, name: name, isDirectory: true, progress: progress)
    }

    // Subdirectories are scanned concurrently via a task group — each recursive call is
    // independent I/O (directory listing + stat calls), so overlapping them across cores
    // speeds up large projects without any shared mutable state.
    private func scanNode(at url: URL, name: String, isDirectory: Bool, progress: ScanProgressCounter?) async throws -> FileNode {
        let kind = FileKind.from(url: url, isDirectory: isDirectory)

        guard isDirectory else {
            progress?.increment()
            return FileNode(name: name, url: url, isDirectory: false, fileKind: kind)
        }

        let contents = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        let candidates: [(url: URL, name: String, isDirectory: Bool)] = contents.compactMap { childURL in
            let childName = childURL.lastPathComponent
            let childIsDirectory = (try? childURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if childIsDirectory, Self.excludedDirectoryNames.contains(childName) {
                return nil
            }
            return (childURL, childName, childIsDirectory)
        }

        var children = try await withThrowingTaskGroup(of: FileNode.self) { group in
            for candidate in candidates {
                group.addTask {
                    try await self.scanNode(at: candidate.url, name: candidate.name, isDirectory: candidate.isDirectory, progress: progress)
                }
            }
            var results: [FileNode] = []
            for try await node in group {
                results.append(node)
            }
            return results
        }

        children.sort { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory && !rhs.isDirectory }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        return FileNode(name: name, url: url, isDirectory: true, children: children, fileKind: kind)
    }
}
