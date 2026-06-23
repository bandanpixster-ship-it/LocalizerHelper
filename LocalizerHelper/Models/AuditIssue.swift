//
//  AuditIssue.swift
//  LocalizerHelper
//
//  Created by Bandan's MacBook Pro on 17/06/26.
//


import Foundation

enum AuditSeverity: String, Hashable, CaseIterable {
    case error
    case warning
    case ignored
    case ok
}

enum AuditRuleID: String, Hashable {
    case missingTranslation = "missing_translation"
    case untranslatedCopy = "untranslated_copy"
    case missingLanguage = "missing_language"
    case duplicateAcrossFiles = "duplicate_across_files"
}

struct AuditIssue: Identifiable, Hashable {
    let id: UUID
    let ruleID: AuditRuleID
    let severity: AuditSeverity
    let key: LocalizationKey
    let language: String?
    let message: String
    let sourceFiles: [URL]

    init(
        id: UUID = UUID(),
        ruleID: AuditRuleID,
        severity: AuditSeverity,
        key: LocalizationKey,
        language: String? = nil,
        message: String,
        sourceFiles: [URL] = []
    ) {
        self.id = id
        self.ruleID = ruleID
        self.severity = severity
        self.key = key
        self.language = language
        self.message = message
        self.sourceFiles = sourceFiles
    }
}

struct KeyAuditResult: Identifiable, Hashable {
    let id: UUID
    let key: LocalizationKey
    let englishValue: String
    let comment: String?
    let translations: [String: String]
    let issues: [AuditIssue]
    let sourceFile: URL

    var highestSeverity: AuditSeverity {
        if issues.contains(where: { $0.severity == .error }) { return .error }
        if issues.contains(where: { $0.severity == .warning }) { return .warning }
        if issues.contains(where: { $0.severity == .ignored }) { return .ignored }
        return .ok
    }

    init(
        id: UUID = UUID(),
        key: LocalizationKey,
        englishValue: String,
        comment: String? = nil,
        translations: [String: String],
        issues: [AuditIssue],
        sourceFile: URL
    ) {
        self.id = id
        self.key = key
        self.englishValue = englishValue
        self.comment = comment
        self.translations = translations
        self.issues = issues
        self.sourceFile = sourceFile
    }
}

enum SearchScope: String, CaseIterable, Identifiable {
    case all = "all"
    case keys = "keys"
    case values = "values"
    case translations = "translations"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:          return "All"
        case .keys:         return "Keys"
        case .values:       return "Values"
        case .translations: return "Translations"
        }
    }

    var icon: String {
        switch self {
        case .all:          return "magnifyingglass"
        case .keys:         return "key"
        case .values:       return "textformat"
        case .translations: return "globe"
        }
    }
}

enum DetailFilter: String, CaseIterable, Identifiable {
    case all
    case errors
    case warnings
    case ignored
    case aiReady

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .errors: return "Errors"
        case .warnings: return "Warnings"
        case .ignored: return "Ignored"
        case .aiReady: return "AI Ready"
        }
    }
}
