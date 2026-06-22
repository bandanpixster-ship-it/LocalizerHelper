import Foundation

struct ProjectScanner: Sendable {
    static let excludedDirectoryNames: Set<String> = [
        "Pods", "DerivedData", ".git",
        "build", ".build",       // Xcode custom build output & Swift PM
        "Carthage",              // Carthage dependencies
    ]

    func scan(at rootURL: URL) throws -> FileNode {
        let name = rootURL.lastPathComponent
        return try scanNode(at: rootURL, name: name, isDirectory: true)
    }

    private func scanNode(at url: URL, name: String, isDirectory: Bool) throws -> FileNode {
        let kind = FileKind.from(url: url, isDirectory: isDirectory)

        guard isDirectory else {
            return FileNode(name: name, url: url, isDirectory: false, fileKind: kind)
        }

        let contents = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        let sorted = contents.sorted { lhs, rhs in
            let lhsIsDir = (try? lhs.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let rhsIsDir = (try? rhs.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if lhsIsDir != rhsIsDir { return lhsIsDir && !rhsIsDir }
            return lhs.lastPathComponent.localizedCaseInsensitiveCompare(rhs.lastPathComponent) == .orderedAscending
        }

        var children: [FileNode] = []
        for childURL in sorted {
            let childName = childURL.lastPathComponent
            let childIsDirectory = (try? childURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false

            if childIsDirectory, Self.excludedDirectoryNames.contains(childName) {
                continue
            }

            children.append(try scanNode(at: childURL, name: childName, isDirectory: childIsDirectory))
        }

        return FileNode(name: name, url: url, isDirectory: true, children: children, fileKind: kind)
    }
}
