//
//  LocalizationAuditor.swift
//  LocalizerHelper
//
//  Created by Bandan's MacBook Pro on 17/06/26.
//


import Foundation

nonisolated struct LocalizationAuditor: Sendable {
    func audit(
        catalog: LocalizationCatalog,
        ignoredKeys: Set<LocalizationKey> = []
    ) -> [KeyAuditResult] {
        let grouped = catalog.entriesByKey
        let duplicateWarnings = duplicateAcrossFilesIssues(from: grouped)

        var results: [KeyAuditResult] = []
        for (key, keyEntries) in grouped {
            let englishEntries = keyEntries.filter { $0.language == "en" }

            // Support both patterns:
            //  • Key-value: has an en.lproj / Base.lproj file → use its value as base
            //  • Key-as-string: no English file → the key itself IS the base string
            let baseValue = englishEntries.first?.value ?? key.key

            // Use the English entry's file for grouping when available; otherwise pick
            // the alphabetically first language so the choice is stable across runs.
            let representativeSourceFile = englishEntries.first?.sourceFile
                ?? keyEntries.min(by: { $0.language < $1.language })!.sourceFile

            let translations = Dictionary(keyEntries.map { ($0.language, $0.value) }, uniquingKeysWith: { _, last in last })

            // Languages to audit: everything except "en".
            // • Key-value projects: catalog.languages contains "en" → this gives non-English languages.
            // • Key-as-string projects: catalog.languages has no "en" → this gives every language.
            let nonBaseLanguages = Set(catalog.languages.filter { $0 != "en" })

            var issues: [AuditIssue] = duplicateWarnings[key] ?? []

            if ignoredKeys.contains(key) {
                issues.append(AuditIssue(
                    ruleID: .untranslatedCopy,
                    severity: .ignored,
                    key: key,
                    message: "\"\(key.key)\" is ignored for untranslated-copy checks"
                ))
            }

            for language in nonBaseLanguages.sorted() {
                if let translation = translations[language] {
                    if translation.isEmpty {
                        issues.append(AuditIssue(
                            ruleID: .missingTranslation,
                            severity: .error,
                            key: key,
                            language: language,
                            message: "\"\(key.key)\" is empty in \(language)"
                        ))
                    } else if translation == baseValue, !ignoredKeys.contains(key) {
                        issues.append(AuditIssue(
                            ruleID: .untranslatedCopy,
                            severity: .error,
                            key: key,
                            language: language,
                            message: "\"\(key.key)\" in \(language) matches base — missing translation"
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
                englishValue: baseValue,
                comment: englishEntries.first?.comment,
                translations: translations,
                issues: issues,
                sourceFile: representativeSourceFile
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
