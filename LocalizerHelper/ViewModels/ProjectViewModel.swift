//
//  ProjectViewModel.swift
//  LocalizerHelper
//
//  Created by Bandan's MacBook Pro on 17/06/26.
//


import AppKit
import Combine
import Foundation
import Observation
import os.log

private struct RegexCacheKey: Equatable {
    let searchText: String
    let matchCase: Bool
}

nonisolated enum ScanProgress: Equatable {
    case idle
    case scanningFiles(count: Int)
    case parsingLocalizationFiles(completed: Int, total: Int)

    var label: String {
        switch self {
        case .idle:
            return ""
        case .scanningFiles(let count):
            return count == 0 ? "Scanning project…" : "Scanning… \(count) files found"
        case .parsingLocalizationFiles(let completed, let total):
            guard total > 0 else { return "Parsing localization files…" }
            return "Parsing localization files… \(completed)/\(total)"
        }
    }
}

nonisolated enum BulkTranslateProgress: Equatable {
    case idle
    case running(completed: Int, total: Int, failed: Int)

    var label: String {
        switch self {
        case .idle:
            return ""
        case .running(let completed, let total, let failed):
            let base = "Translating… \(completed)/\(total)"
            return failed > 0 ? "\(base) (\(failed) failed)" : base
        }
    }
}

@MainActor
@Observable
final class ProjectViewModel {
    var rootURL: URL?
    var rootNode: FileNode?
    var selectedNode: FileNode?
    private var selectionHistory: [FileNode] = []
    var catalog = LocalizationCatalog()
    var auditResults: [KeyAuditResult] = []
    var swiftLiterals: [SwiftStringLiteral] = []
    var searchText = ""
    var searchMatchCase = false
    var searchWholeWord = false
    var searchScope: SearchScope = .all
    var detailFilter: DetailFilter = .all
    var isScanning = false
    var scanProgress: ScanProgress = .idle
    var bulkTranslateProgress: BulkTranslateProgress = .idle
    var scanError: String?
    var unreadableFiles: [URL] = []
    var pendingProjectURL: URL?
    var showOpenProjectChoice = false

    private var securityScopedURL: URL?
    private var scanTask: Task<Void, Never>?
    private var auditTask: Task<Void, Never>?
    private var bulkTranslateTask: Task<Void, Never>?
    @ObservationIgnored private var cachedWholeWordRegex: NSRegularExpression?
    @ObservationIgnored private var cachedWholeWordRegexKey: RegexCacheKey?
    private var ignoreStoreCancellable: AnyCancellable?
    private let scanner = ProjectScanner()
    private let projectStore = ProjectStore()
    private let auditor = LocalizationAuditor()
    private let swiftExtractor = SwiftStringExtractor()
    private let parsers = LocalizationParsers()
    private let fileUpdater = LocalizationFileUpdater()
    private static let logger = Logger(subsystem: "com.LocalizerHelper.ViewModel", category: "Operations")

    init() {
        ignoreStoreCancellable = GlobalIgnoreStore.shared.$entries
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.refreshAudit() }
            }
    }

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
            let entriesByKey = catalog.entriesByKey
            results = results.filter { result in
                switch searchScope {
                case .all:
                    return searchMatches(in: result.key.key)
                        || searchMatches(in: result.englishValue)
                        || translationSearchMatches(for: result.key, entriesByKey: entriesByKey)
                case .keys:
                    return searchMatches(in: result.key.key)
                case .values:
                    return searchMatches(in: result.englishValue)
                case .translations:
                    return translationSearchMatches(for: result.key, entriesByKey: entriesByKey)
                }
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
        case .aiReady:
            let entriesByKey = catalog.entriesByKey
            return results.filter { result in
                entriesByKey[result.key]?.contains { !($0.comment ?? "").isEmpty } ?? false
            }
        }
    }

    var filteredSwiftLiterals: [SwiftStringLiteral] {
        guard !searchText.isEmpty else { return swiftLiterals }
        return swiftLiterals.filter {
            searchMatches(in: $0.displayPattern) || searchMatches(in: $0.raw)
        }
    }

    var missingSwiftLiterals: [SwiftStringLiteral] {
        let knownKeys = Set(catalog.entries.map { $0.key.key })

        return filteredSwiftLiterals.filter { literal in
            let text = literal.displayPattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return false }
            guard containsUserFacingText(text) else { return false }
            // Check both the display pattern and the format-specifier template
            // so that `Hello \(name)` is recognised as present when `Hello %@` is in the catalog
            return !knownKeys.contains(text) && !knownKeys.contains(literal.localizationTemplate)
        }
    }

    // MARK: - Search helpers

    private func searchMatches(in text: String) -> Bool {
        guard !searchText.isEmpty else { return true }
        if searchWholeWord {
            guard let regex = wholeWordRegex() else { return false }
            return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
        } else {
            let compareOptions: String.CompareOptions = searchMatchCase ? [] : [.caseInsensitive]
            return text.range(of: searchText, options: compareOptions) != nil
        }
    }

    private func wholeWordRegex() -> NSRegularExpression? {
        let cacheKey = RegexCacheKey(searchText: searchText, matchCase: searchMatchCase)
        if cachedWholeWordRegexKey == cacheKey {
            return cachedWholeWordRegex
        }
        let escaped = NSRegularExpression.escapedPattern(for: searchText)
        let pattern = "\\b\(escaped)\\b"
        var options: NSRegularExpression.Options = [.useUnicodeWordBoundaries]
        if !searchMatchCase { options.insert(.caseInsensitive) }
        let regex = try? NSRegularExpression(pattern: pattern, options: options)
        cachedWholeWordRegexKey = cacheKey
        cachedWholeWordRegex = regex
        return regex
    }

    private func translationSearchMatches(for key: LocalizationKey, entriesByKey: [LocalizationKey: [LocalizationEntry]]) -> Bool {
        guard let entries = entriesByKey[key] else { return false }
        return entries.contains { $0.language != "en" && searchMatches(in: $0.value) }
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

        if rootURL != nil {
            pendingProjectURL = url
            showOpenProjectChoice = true
        } else {
            openProject(at: url)
        }
    }

    func openProjectInNewWindow(_ handler: (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "Open Project Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Open"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        handler(url)
    }

    func openPendingProjectInCurrentWindow() {
        guard let pendingProjectURL else { return }
        showOpenProjectChoice = false
        self.pendingProjectURL = nil
        openProject(at: pendingProjectURL)
    }

    func cancelPendingProjectOpen() {
        showOpenProjectChoice = false
        pendingProjectURL = nil
    }

    func openProject(at url: URL) {
        stopSecurityScopedAccess()
        _ = url.startAccessingSecurityScopedResource()
        securityScopedURL = url

        scanTask?.cancel()
        bulkTranslateTask?.cancel()
        rootURL = url
        selectedNode = nil
        selectionHistory = []
        swiftLiterals = []
        scanError = nil
        unreadableFiles = []

        let projectID = projectStore.projectID(for: url)

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
        if let selectedNode, selectedNode != node {
            selectionHistory.append(selectedNode)
        }
        selectedNode = node
        loadDetailForSelection()
    }

    var canGoBackInSelection: Bool {
        !selectionHistory.isEmpty
    }

    func goBackToPreviousSelection() {
        guard let previousNode = selectionHistory.popLast() else { return }
        selectedNode = previousNode
        loadDetailForSelection()
    }

    func selectLocalizationFile(_ url: URL) {
        guard let root = rootNode,
              let node = findNode(url: url, in: [root]) else { return }
        selectNode(node)
    }

    private func findNode(url: URL, in nodes: [FileNode]) -> FileNode? {
        for node in nodes {
            if node.url == url { return node }
            if let found = findNode(url: url, in: node.children) { return found }
        }
        return nil
    }

    func refreshProject() {
        guard let rootURL, let projectID else { return }
        scanTask?.cancel()
        bulkTranslateTask?.cancel()
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

    func saveComment(key: LocalizationKey, comment: String) {
        // Prefer xcstrings (single file, all languages). Fall back to en.lproj .strings.
        let targetFile = catalog.entries.first { $0.key == key && $0.sourceFile.pathExtension.lowercased() == "xcstrings" }?.sourceFile
            ?? catalog.entry(for: key, language: "en")?.sourceFile
        guard let fileURL = targetFile else { return }
        do {
            try fileUpdater.updateComment(in: fileURL, key: key.key, comment: comment)
            refreshCatalogEntries(for: fileURL)
            refreshAudit()
        } catch {
            scanError = error.localizedDescription
        }
    }

    func affectedFiles(for key: LocalizationKey) -> [URL] {
        Array(Set(catalog.entries.filter { $0.key == key }.map(\.sourceFile)))
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func deleteLocalization(key: LocalizationKey) {
        let files = affectedFiles(for: key)
        do {
            for fileURL in files {
                try fileUpdater.deleteKey(from: fileURL, key: key.key)
            }
            for fileURL in files {
                refreshCatalogEntries(for: fileURL)
            }
            refreshAudit()
            Self.logger.info("Deleted key '\(key.key, privacy: .public)' from \(files.count, privacy: .public) files")
        } catch {
            Self.logger.error("Delete failed: \(error.localizedDescription, privacy: .public)")
            scanError = error.localizedDescription
        }
    }

    func toggleIgnore(key: LocalizationKey) {
        let store = GlobalIgnoreStore.shared
        if store.isIgnored(key: key.key, language: "__all__") ||
           store.entries.contains(where: { $0.key == key.key && $0.language == nil }) {
            store.remove(key: key.key, language: nil)
        } else {
            store.add(key: key.key, language: nil)
        }
        refreshAudit()
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

    // Polls a background counter on a fixed cadence and forwards it to `scanProgress`,
    // rather than hopping to the main actor on every file — cheap even for huge projects.
    private func pollProgress(_ counter: ScanProgressCounter, update: @escaping @MainActor (Int) -> Void) -> Task<Void, Never> {
        Task { @MainActor in
            while !Task.isCancelled {
                update(counter.current)
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func performScan(at url: URL, projectID: String) async {
        isScanning = true
        scanProgress = .scanningFiles(count: 0)
        defer {
            isScanning = false
            scanProgress = .idle
        }

        do {
            let scanCounter = ScanProgressCounter()
            let scanPoll = pollProgress(scanCounter) { [weak self] count in
                self?.scanProgress = .scanningFiles(count: count)
            }
            defer { scanPoll.cancel() }

            let node = try await scanner.scan(at: url, progress: scanCounter)

            guard !Task.isCancelled else { return }

            let totalLocalizationFiles = LocalizationCatalog.localizationFileNodes(in: node).count
            let parseCounter = ScanProgressCounter()
            scanProgress = .parsingLocalizationFiles(completed: 0, total: totalLocalizationFiles)
            let parsePoll = pollProgress(parseCounter) { [weak self] completed in
                self?.scanProgress = .parsingLocalizationFiles(completed: completed, total: totalLocalizationFiles)
            }
            defer { parsePoll.cancel() }

            let catalog = await LocalizationCatalog.build(from: node, parsers: parsers, progress: parseCounter)

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
        auditTask?.cancel()

        let catalogSnapshot = catalog
        let auditor = auditor
        let ignoreEntries = GlobalIgnoreStore.shared.entries

        auditTask = Task {
            let computed = await Task.detached(priority: .userInitiated) {
                // Keys with a nil-language entry are globally ignored (all languages)
                let globallyIgnoredKeys = Set(
                    ignoreEntries
                        .filter { $0.language == nil }
                        .compactMap { entry in catalogSnapshot.entries.first { $0.key.key == entry.key }?.key }
                )

                let raw = auditor.audit(catalog: catalogSnapshot, ignoredKeys: globallyIgnoredKeys)

                // Post-process: convert language-specific global ignores to .ignored severity
                return raw.map { result -> KeyAuditResult in
                    let remapped = result.issues.map { issue -> AuditIssue in
                        guard let lang = issue.language, issue.severity != .ignored else { return issue }
                        guard ignoreEntries.contains(where: { $0.key == result.key.key && $0.language == lang }) else { return issue }
                        return AuditIssue(
                            ruleID: issue.ruleID,
                            severity: .ignored,
                            key: issue.key,
                            language: lang,
                            message: "\"\(result.key.key)\" in \(lang) is globally ignored"
                        )
                    }
                    return KeyAuditResult(
                        id: result.id,
                        key: result.key,
                        englishValue: result.englishValue,
                        comment: result.comment,
                        translations: result.translations,
                        issues: remapped,
                        sourceFile: result.sourceFile
                    )
                }
            }.value

            guard !Task.isCancelled else { return }
            auditResults = computed
        }
    }

    private func loadDetailForSelection() {
        guard let selectedNode else {
            swiftLiterals = []
            return
        }

        let urls = swiftFileURLs(in: selectedNode)
        guard !urls.isEmpty else {
            swiftLiterals = []
            return
        }

        let extractor = swiftExtractor
        Task {
            let results = await withTaskGroup(of: [SwiftStringLiteral].self) { group in
                for url in urls {
                    group.addTask(priority: .userInitiated) {
                        (try? extractor.extract(fileURL: url)) ?? []
                    }
                }
                var all: [SwiftStringLiteral] = []
                for await batch in group { all.append(contentsOf: batch) }
                return all.sorted { $0.lineNumber < $1.lineNumber }
            }
            swiftLiterals = results
        }
    }

    private func swiftFileURLs(in node: FileNode) -> [URL] {
        if !node.isDirectory { return node.fileKind == .swift ? [node.url] : [] }
        return node.children.flatMap { swiftFileURLs(in: $0) }
    }

    func generateComment(sourceLine: String, key: String) async throws -> String {
        Self.logger.debug("Generating comment for key=\(key, privacy: .public)")
        return try await TranslationService.shared.generateComment(sourceLine: sourceLine, key: key)
    }

    func aiTranslateBatch(key: String, sourceText: String, commentOverride: String?, languages: [String]) async throws -> [String: String] {
        let englishEntry = catalog.entries.first { $0.key.key == key && $0.language == "en" }
        let text = sourceText.isEmpty ? (englishEntry?.value ?? key) : sourceText
        let comment = commentOverride ?? englishEntry?.comment
        Self.logger.debug("AI batch translate key=\(key, privacy: .public) text=\(text, privacy: .public) comment=\(comment ?? "nil", privacy: .public) langs=\(languages.joined(separator: ","), privacy: .public)")
        return try await TranslationService.shared.translateBatch(
            text: text,
            comment: comment,
            key: key,
            to: languages
        )
    }

    func translate(text: String, to language: String, commentOverride: String? = nil) async throws -> String {
        let englishEntry = catalog.entries.first { $0.key.key == text && $0.language == "en" }
        let sourceText = englishEntry?.value ?? text
        let comment = commentOverride ?? englishEntry?.comment
        return try await TranslationService.shared.translate(
            text: sourceText,
            to: language,
            comment: comment,
            key: text
        )
    }

    // MARK: - Bulk translate

    var isBulkTranslating: Bool {
        if case .idle = bulkTranslateProgress { return false }
        return true
    }

    /// Translates every key currently visible in the table (respecting the active search/filter
    /// scope) into every non-English language, skipping languages that already have a value.
    func translateMissingStrings() {
        startBulkTranslation(onlyMissing: true)
    }

    /// Same as `translateMissingStrings`, but overwrites existing translations too.
    func translateAllStrings() {
        startBulkTranslation(onlyMissing: false)
    }

    func cancelBulkTranslate() {
        bulkTranslateTask?.cancel()
    }

    private func startBulkTranslation(onlyMissing: Bool) {
        bulkTranslateTask?.cancel()
        bulkTranslateTask = Task { await runBulkTranslation(onlyMissing: onlyMissing) }
    }

    private func runBulkTranslation(onlyMissing: Bool) async {
        struct WorkItem {
            let key: LocalizationKey
            let language: String
            let file: URL
            let sourceText: String
            let comment: String?
        }

        let scope = filteredAuditResults
        let languages = catalog.languages.filter { $0 != "en" }
        guard !scope.isEmpty, !languages.isEmpty else { return }

        let store = GlobalIgnoreStore.shared
        var work: [WorkItem] = []
        for result in scope {
            for language in languages {
                guard let file = sourceFileURL(for: result.key, language: language) else { continue }
                guard !store.isIgnored(key: result.key.key, language: language) else { continue }
                let existing = result.translations[language] ?? ""
                if onlyMissing && !existing.isEmpty { continue }
                work.append(WorkItem(key: result.key, language: language, file: file, sourceText: result.englishValue, comment: result.comment))
            }
        }
        guard !work.isEmpty else { return }

        let total = work.count
        bulkTranslateProgress = .running(completed: 0, total: total, failed: 0)

        let completedCounter = ScanProgressCounter()
        let failedCounter = ScanProgressCounter()
        let accumulator = BulkTranslationAccumulator()

        let progressPoll = pollProgress(completedCounter) { [weak self] completed in
            self?.bulkTranslateProgress = .running(completed: completed, total: total, failed: failedCounter.current)
        }
        defer { progressPoll.cancel() }

        // Bounded concurrency: translate a handful of strings at a time rather than either
        // serially (slow) or all-at-once (hammers free translation APIs into rate limits).
        let chunkSize = 6
        var index = 0
        while index < work.count {
            if Task.isCancelled { break }
            let end = min(index + chunkSize, work.count)
            let chunk = work[index..<end]

            await withTaskGroup(of: Void.self) { group in
                for item in chunk {
                    group.addTask {
                        do {
                            let value = try await TranslationService.shared.translate(
                                text: item.sourceText,
                                to: item.language,
                                comment: item.comment,
                                key: item.key.key
                            )
                            guard !value.isEmpty else { throw TranslationError.unexpectedResponse }
                            await accumulator.add(file: item.file, key: item.key.key, language: item.language, value: value)
                        } catch {
                            failedCounter.increment()
                        }
                        completedCounter.increment()
                    }
                }
            }

            let flushed = await accumulator.flushIfNeeded(threshold: 25, fileUpdater: fileUpdater)
            if !flushed.isEmpty {
                for file in flushed { refreshCatalogEntries(for: file) }
                refreshAudit()
            }
            index = end
        }

        // Always flush whatever succeeded, even if the run was cancelled partway through —
        // nothing completed should be silently lost.
        let remaining = await accumulator.flushAll(fileUpdater: fileUpdater)
        if !remaining.isEmpty {
            for file in remaining { refreshCatalogEntries(for: file) }
            refreshAudit()
        }

        bulkTranslateProgress = .idle
    }

    var localizationFiles: [URL] {
        var urls = Set<URL>()
        for entry in catalog.entries {
            urls.insert(entry.sourceFile)
        }
        return Array(urls).sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func addLanguage(code: String, to fileURL: URL) {
        addLanguages(codes: [code], to: fileURL)
    }

    func addLanguages(codes: [String], to fileURL: URL) {
        do {
            try fileUpdater.addLanguages(codes: codes, to: fileURL)
            refreshCatalogEntries(for: fileURL)
            refreshAudit()
        } catch {
            scanError = error.localizedDescription
        }
    }

    func bulkAddLocalizations(
        items: [(key: String, translations: [String: String], comment: String)],
        targetFileURL: URL,
        progress: @escaping (Int) -> Void
    ) async {
        for (index, item) in items.enumerated() {
            do {
                try fileUpdater.addTranslation(to: targetFileURL, key: item.key, translations: item.translations, comment: item.comment)
            } catch {
                // Skip duplicates and other per-key errors silently — user can add individually
                Self.logger.debug("bulkAdd skipped key=\(item.key, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
            await MainActor.run { progress(index + 1) }
        }
        refreshCatalogEntries(for: targetFileURL)
        refreshAudit()
    }

    func addLocalization(key: String, targetFileURL: URL, translations: [String: String], comment: String = "") {
        do {
            try fileUpdater.addTranslation(to: targetFileURL, key: key, translations: translations, comment: comment)
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
            panel.nameFieldStringValue = "Localizable.xcstrings"
            panel.canCreateDirectories = true
            panel.message = "Create a new .xcstrings localization catalog. Place it anywhere in your project — it holds all languages in one file."

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
