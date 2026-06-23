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

    static let all: [LanguageOption] = {
        let currentLocale = Locale(identifier: "en")
        let codes = Set(
            Locale.availableIdentifiers.compactMap {
                Locale(identifier: $0).language.languageCode?.identifier
            }
        )
        return codes
            .map { code in
                let name = currentLocale.localizedString(forLanguageCode: code)
                    ?? Locale(identifier: code).localizedString(forLanguageCode: code)
                    ?? code
                return LanguageOption(code: code, displayName: name)
            }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }()
}
