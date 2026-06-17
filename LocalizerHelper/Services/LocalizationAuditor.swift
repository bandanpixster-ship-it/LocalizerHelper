import Foundation

struct LocalizationAuditor: Sendable {
    func audit(
        catalog: LocalizationCatalog,
        ignoredKeys: Set<LocalizationKey> = []
    ) -> [KeyAuditResult] {
        let grouped = catalog.entriesByKey
        let duplicateWarnings = duplicateAcrossFilesIssues(from: grouped)

        var results: [KeyAuditResult] = []
        for (key, keyEntries) in grouped {
            let englishEntries = keyEntries.filter { $0.language == "en" }
            guard let englishEntry = englishEntries.first else { continue }

            let translations = Dictionary(uniqueKeysWithValues: keyEntries.map { ($0.language, $0.value) })
            let nonEnglishLanguages = Set(catalog.languages.filter { $0 != "en" })

            var issues: [AuditIssue] = duplicateWarnings[key] ?? []

            if ignoredKeys.contains(key) {
                issues.append(AuditIssue(
                    ruleID: .untranslatedCopy,
                    severity: .ignored,
                    key: key,
                    message: "\"\(key.key)\" is ignored for untranslated-copy checks"
                ))
            }

            for language in nonEnglishLanguages.sorted() {
                if let translation = translations[language] {
                    if translation.isEmpty {
                        issues.append(AuditIssue(
                            ruleID: .missingTranslation,
                            severity: .error,
                            key: key,
                            language: language,
                            message: "\"\(key.key)\" is empty in \(language)"
                        ))
                    } else if translation == englishEntry.value, !ignoredKeys.contains(key) {
                        issues.append(AuditIssue(
                            ruleID: .untranslatedCopy,
                            severity: .error,
                            key: key,
                            language: language,
                            message: "\"\(key.key)\" in \(language) matches English — missing translation"
                        ))
                    }
                } else {
                    issues.append(AuditIssue(
                        ruleID: .missingLanguage,
                        severity: .warning,
                        key: key,
                        language: language,
                        message: "\"\(key.key)\" missing in \(language)"
                    ))
                }
            }

            results.append(KeyAuditResult(
                key: key,
                englishValue: englishEntry.value,
                translations: translations,
                issues: issues,
                sourceFile: englishEntry.sourceFile
            ))
        }

        return results.sorted { lhs, rhs in
            if lhs.key.tableName != rhs.key.tableName {
                return lhs.key.tableName.localizedCaseInsensitiveCompare(rhs.key.tableName) == .orderedAscending
            }
            return lhs.key.key.localizedCaseInsensitiveCompare(rhs.key.key) == .orderedAscending
        }
    }

    func auditResults(
        for entries: [LocalizationEntry],
        allLanguages: [String],
        ignoredKeys: Set<LocalizationKey>
    ) -> [KeyAuditResult] {
        audit(catalog: LocalizationCatalog(entries: entries), ignoredKeys: ignoredKeys)
    }

    private func duplicateAcrossFilesIssues(
        from grouped: [LocalizationKey: [LocalizationEntry]]
    ) -> [LocalizationKey: [AuditIssue]] {
        let keysByKeyString = Dictionary(grouping: grouped.keys, by: \.key)
        var warnings: [LocalizationKey: [AuditIssue]] = [:]

        for (_, keys) in keysByKeyString where keys.count > 1 {
            let tables = keys.map(\.tableName).sorted()
            let message = "\"\(keys[0].key)\" appears in \(tables.joined(separator: " and "))"
            let files = grouped
                .filter { keys.contains($0.key) }
                .flatMap(\.value)
                .map(\.sourceFile)

            for key in keys {
                warnings[key, default: []].append(AuditIssue(
                    ruleID: .duplicateAcrossFiles,
                    severity: .warning,
                    key: key,
                    message: message,
                    sourceFiles: Array(Set(files))
                ))
            }
        }

        return warnings
    }
}
