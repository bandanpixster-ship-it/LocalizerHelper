import AppKit
import Foundation
import Observation
import os.log

@MainActor
@Observable
final class ProjectViewModel {
    var rootURL: URL?
    var rootNode: FileNode?
    var selectedNode: FileNode?
    var catalog = LocalizationCatalog()
    var auditResults: [KeyAuditResult] = []
    var ignoredKeys: Set<LocalizationKey> = []
    var swiftLiterals: [SwiftStringLiteral] = []
    var searchText = ""
    var detailFilter: DetailFilter = .all
    var isScanning = false
    var scanError: String?
    var unreadableFiles: [URL] = []

    private var securityScopedURL: URL?
    private var scanTask: Task<Void, Never>?
    private let scanner = ProjectScanner()
    private let projectStore = ProjectStore()
    private let auditor = LocalizationAuditor()
    private let swiftExtractor = SwiftStringExtractor()
    private let parsers = LocalizationParsers()
    private let fileUpdater = LocalizationFileUpdater()
    private static let logger = Logger(subsystem: "com.LocalizerHelper.ViewModel", category: "Operations")

    var projectID: String? {
        rootURL.map { projectStore.projectID(for: $0) }
    }

    var issueSummary: (errors: Int, warnings: Int, ignored: Int) {
        var errors = 0
        var warnings = 0
        var ignored = 0
        for result in filteredAuditResults {
            for issue in result.issues {
                switch issue.severity {
                case .error: errors += 1
                case .warning: warnings += 1
                case .ignored: ignored += 1
                case .ok: break
                }
            }
        }
        return (errors, warnings, ignored)
    }

    var filteredAuditResults: [KeyAuditResult] {
        guard let selectedNode else { return [] }
        let scopedEntries = catalog.entriesForNode(selectedNode)
        let scopedKeys = Set(scopedEntries.map(\.key))
        var results = auditResults.filter { scopedKeys.contains($0.key) }

        if !searchText.isEmpty {
            results = results.filter {
                $0.key.key.localizedCaseInsensitiveContains(searchText)
                    || $0.englishValue.localizedCaseInsensitiveContains(searchText)
            }
        }

        switch detailFilter {
        case .all:
            return results
        case .errors:
            return results.filter { $0.issues.contains(where: { $0.severity == .error }) }
        case .warnings:
            return results.filter { $0.issues.contains(where: { $0.severity == .warning }) }
        case .ignored:
            return results.filter { $0.issues.contains(where: { $0.severity == .ignored }) }
        }
    }

    var filteredSwiftLiterals: [SwiftStringLiteral] {
        guard searchText.isEmpty else {
            return swiftLiterals.filter {
                $0.displayPattern.localizedCaseInsensitiveContains(searchText)
                    || $0.raw.localizedCaseInsensitiveContains(searchText)
            }
        }
        return swiftLiterals
    }

    var missingSwiftLiterals: [SwiftStringLiteral] {
        let knownTexts = Set(catalog.entries.flatMap { [$0.key.key, $0.value] })

        return filteredSwiftLiterals.filter { literal in
            let text = literal.displayPattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return false }
            guard containsUserFacingText(text) else { return false }
            return !knownTexts.contains(text)
        }
    }

    private func containsUserFacingText(_ text: String) -> Bool {
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        return !letters.isEmpty && !text.hasPrefix("http") && !text.contains("\\n")
    }

    func openProject() {
        let panel = NSOpenPanel()
        panel.title = "Open Project Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Open"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        openProject(at: url)
    }

    func openProject(at url: URL) {
        stopSecurityScopedAccess()
        _ = url.startAccessingSecurityScopedResource()
        securityScopedURL = url

        scanTask?.cancel()
        rootURL = url
        selectedNode = nil
        swiftLiterals = []
        scanError = nil
        unreadableFiles = []

        let projectID = projectStore.projectID(for: url)
        ignoredKeys = projectStore.loadIgnoredKeys(projectID: projectID)

        // Save this project as the last opened
        do {
            try projectStore.saveLastProjectURL(url)
            Self.logger.debug("Saved last project URL: \\(url.path, privacy: .public)")
        } catch {
            Self.logger.error("Failed to save last project URL: \\(error.localizedDescription, privacy: .public)")
        }

        scanTask = Task {
            await performScan(at: url, projectID: projectID)
        }
    }

    func selectNode(_ node: FileNode?) {
        selectedNode = node
        loadDetailForSelection()
    }

    func refreshProject() {
        guard let rootURL, let projectID else { return }
        scanTask?.cancel()
        scanTask = Task {
            await performScan(at: rootURL, projectID: projectID)
        }
    }

    func saveTranslations(key: LocalizationKey, values: [String: String]) {
        Self.logger.debug("Starting save for key: \\(key.key, privacy: .public)")

        // For xcstrings, the same file holds all languages — use it as fallback when no entry exists for a language yet
        let xcstringsFile = catalog.entries
            .first { $0.key == key && $0.sourceFile.pathExtension.lowercased() == "xcstrings" }?
            .sourceFile

        let languageFiles: [(language: String, file: URL, existingValue: String)] = values.compactMap { language, _ in
            if let entry = catalog.entry(for: key, language: language) {
                return (language, entry.sourceFile, entry.value)
            }
            if let file = xcstringsFile {
                return (language, file, "")
            }
            Self.logger.debug("No file found for language: \\(language, privacy: .public)")
            return nil
        }

        guard !languageFiles.isEmpty else {
            Self.logger.error("No editable translations found for key: \\(key.key, privacy: .public)")
            scanError = "No editable translations were found for this key."
            return
        }

        Self.logger.debug("Found \\(languageFiles.count, privacy: .public) editable language entries")
        var updatedFiles = Set<URL>()
        do {
            for (language, file, existingValue) in languageFiles {
                let newValue = values[language] ?? ""
                if newValue != existingValue && !newValue.isEmpty {
                    Self.logger.debug("Updating \\(language, privacy: .public): \\(newValue, privacy: .public)")
                    try fileUpdater.updateTranslation(in: file, key: key.key, language: language, newValue: newValue)
                    updatedFiles.insert(file)
                } else {
                    Self.logger.debug("No change for language \\(language, privacy: .public)")
                }
            }
            for fileURL in updatedFiles {
                Self.logger.debug("Refreshing catalog for file: \\(fileURL.path, privacy: .public)")
                refreshCatalogEntries(for: fileURL)
            }
            if !updatedFiles.isEmpty {
                Self.logger.info("Successfully saved \\(updatedFiles.count, privacy: .public) files")
                refreshAudit()
            }
        } catch {
            Self.logger.error("Failed to save translations: \\(error.localizedDescription, privacy: .public)")
            scanError = error.localizedDescription
        }
    }

    func toggleIgnore(key: LocalizationKey) {
        guard let projectID else { return }
        do {
            ignoredKeys = try projectStore.toggleIgnored(key: key, projectID: projectID)
            refreshAudit()
        } catch {
            scanError = error.localizedDescription
        }
    }

    func sourceFileURL(for key: LocalizationKey, language: String) -> URL? {
        if let entry = catalog.entry(for: key, language: language) {
            return entry.sourceFile
        }
        // For xcstrings, one file holds all languages — allow editing even if this language has no entry yet
        return catalog.entries
            .first { $0.key == key && $0.sourceFile.pathExtension.lowercased() == "xcstrings" }?
            .sourceFile
    }

    private func refreshCatalogEntries(for fileURL: URL) {
        let extensionName = fileURL.pathExtension.lowercased()
        do {
            let newEntries: [LocalizationEntry]
            switch extensionName {
            case "strings":
                newEntries = try parsers.strings.parse(fileURL)
            case "xcstrings":
                newEntries = try parsers.xcstrings.parse(fileURL: fileURL)
            default:
                return
            }
            catalog.replacingEntries(for: fileURL, with: newEntries)
        } catch {
            scanError = error.localizedDescription
        }
    }

    private func performScan(at url: URL, projectID: String) async {
        isScanning = true
        defer { isScanning = false }

        do {
            let scanner = scanner
            let parsers = parsers
            let node = try await Task.detached(priority: .userInitiated) {
                try scanner.scan(at: url)
            }.value

            guard !Task.isCancelled else { return }

            let catalog = await Task.detached(priority: .userInitiated) {
                LocalizationCatalog.build(from: node, parsers: parsers)
            }.value

            guard !Task.isCancelled else { return }

            rootNode = node
            self.catalog = catalog
            selectedNode = node
            refreshAudit()
            loadDetailForSelection()
        } catch {
            if !Task.isCancelled {
                scanError = error.localizedDescription
            }
        }
    }

    private func refreshAudit() {
        auditResults = auditor.audit(catalog: catalog, ignoredKeys: ignoredKeys)
    }

    private func loadDetailForSelection() {
        guard let selectedNode else {
            swiftLiterals = []
            return
        }

        if selectedNode.fileKind == .swift {
            let fileURL = selectedNode.url
            let extractor = swiftExtractor
            Task {
                do {
                    let literals = try await Task.detached(priority: .userInitiated) {
                        try extractor.extract(fileURL: fileURL)
                    }.value
                    swiftLiterals = literals
                } catch {
                    swiftLiterals = []
                    unreadableFiles.append(fileURL)
                }
            }
        } else {
            swiftLiterals = []
        }
    }

    func translate(text: String, to language: String) async throws -> String {
        try await TranslationService.shared.translate(text: text, to: language)
    }

    var localizationFiles: [URL] {
        var urls = Set<URL>()
        for entry in catalog.entries {
            urls.insert(entry.sourceFile)
        }
        return Array(urls).sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func addLocalization(key: String, targetFileURL: URL, translations: [String: String]) {
        do {
            try fileUpdater.addTranslation(to: targetFileURL, key: key, translations: translations)
            refreshCatalogEntries(for: targetFileURL)
            refreshAudit()
        } catch {
            scanError = error.localizedDescription
        }
    }

    /// Presents an NSSavePanel and creates an empty .strings or .xcstrings file.
    /// Returns the URL of the created file, or nil if the user cancelled.
    func createLocalizationFile() async -> URL? {
        await withCheckedContinuation { continuation in
            let panel = NSSavePanel()
            panel.title = "Create Localization File"
            panel.nameFieldStringValue = "Localizable.strings"
            panel.canCreateDirectories = true
            panel.message = "Create a new localization file. Place it inside an .lproj folder (e.g. en.lproj) to associate it with a language."

            guard let window = NSApp.keyWindow else {
                continuation.resume(returning: nil)
                return
            }

            panel.beginSheetModal(for: window) { [self] result in
                guard result == .OK, let url = panel.url else {
                    continuation.resume(returning: nil)
                    return
                }

                let content: String
                if url.pathExtension.lowercased() == "xcstrings" {
                    content = "{\n  \"sourceLanguage\" : \"en\",\n  \"strings\" : {},\n  \"version\" : \"1.0\"\n}\n"
                } else {
                    content = "/* \(url.deletingPathExtension().lastPathComponent) */\n"
                }

                do {
                    try content.write(to: url, atomically: true, encoding: .utf8)
                    self.refreshCatalogEntries(for: url)
                    continuation.resume(returning: url)
                } catch {
                    self.scanError = "Could not create file: \(error.localizedDescription)"
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func stopSecurityScopedAccess() {
        securityScopedURL?.stopAccessingSecurityScopedResource()
        securityScopedURL = nil
    }
}
