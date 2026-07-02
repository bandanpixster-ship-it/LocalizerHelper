//
//  LanguageOption.swift
//  LocalizerHelper
//
//  Created by Bandan's MacBook Pro on 23/06/26.
//


import SwiftUI

struct LanguageOption: Identifiable {
    let code: String
    let displayName: String
    var id: String { code }

    // Apple's official App Store Connect / Xcode localization list (developer.apple.com/help/
    // app-store-connect/reference/app-store-localizations). Previously this was derived from
    // `Locale.availableIdentifiers`, which pulls in every locale macOS knows about — hundreds of
    // entries the App Store / Xcode localization pickers don't actually support. Using Apple's
    // curated list instead means every code here is one Xcode and the App Store genuinely accept.
    static let all: [LanguageOption] = {
        let currentLocale = Locale(identifier: "en")
        return appleSupportedCodes
            .map { code in
                let name = currentLocale.localizedString(forIdentifier: code)
                    ?? currentLocale.localizedString(forLanguageCode: code)
                    ?? code
                return LanguageOption(code: code, displayName: name)
            }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }()

    private static let appleSupportedCodes: [String] = [
        "ar", "bn", "ca", "zh-Hans", "zh-Hant", "hr", "cs", "da", "nl",
        "en-AU", "en-CA", "en-GB", "en-US", "fi", "fr", "fr-CA", "de", "el",
        "gu", "he", "hi", "hu", "id", "it", "ja", "kn", "ko", "ms", "ml",
        "mr", "no", "or", "pl", "pt-BR", "pt-PT", "pa", "ro", "ru", "sk",
        "sl", "es-MX", "es-ES", "sv", "ta", "te", "th", "tr", "uk", "ur", "vi",
    ]
}
