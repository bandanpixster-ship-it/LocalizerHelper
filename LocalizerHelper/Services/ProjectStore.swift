//
//  ProjectStore.swift
//  LocalizerHelper
//
//  Created by Bandan's MacBook Pro on 17/06/26.
//


import Foundation

struct ProjectStore: Sendable {
    enum LastProjectLoadResult {
        case found(URL)
        case missing
    }

    private let fileManager = FileManager.default

    func projectID(for rootURL: URL) -> String {
        if let xcodeproj = findSingleXcodeProject(in: rootURL) {
            return xcodeproj.deletingPathExtension().lastPathComponent
        }
        let name = rootURL.lastPathComponent
        return name.isEmpty ? "UntitledProject" : name
    }

    func saveLastProjectURL(_ url: URL) throws {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let configDir = support.appendingPathComponent("LocalizerHelper", isDirectory: true)
        try fileManager.createDirectory(at: configDir, withIntermediateDirectories: true)
        let bookmark = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let configURL = configDir.appendingPathComponent("last-project.bookmark")
        try bookmark.write(to: configURL, options: .atomic)
    }

    func loadLastProjectURL() -> LastProjectLoadResult {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let configURL = support
            .appendingPathComponent("LocalizerHelper", isDirectory: true)
            .appendingPathComponent("last-project.bookmark")
        guard let bookmark = try? Data(contentsOf: configURL) else { return .missing }
        guard let url = resolveBookmark(bookmark) else { return .missing }
        return .found(url)
    }

    func makeBookmark(for url: URL) -> Data? {
        try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    func resolveBookmark(_ data: Data) -> URL? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        return url
    }

    private func findSingleXcodeProject(in rootURL: URL) -> URL? {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return nil }
        let projects = contents.filter { $0.pathExtension == "xcodeproj" }
        guard projects.count == 1 else { return nil }
        return projects[0]
    }
}
