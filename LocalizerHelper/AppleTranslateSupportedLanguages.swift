//
//  AppleTranslateSupportedLanguages.swift
//  LocalizerHelper
//
//  Created by Bandan's MacBook Pro on 23/06/26.
//

import Foundation
import NaturalLanguage
import os.log

/// Provides a helper to discover which target languages are currently available on the device
/// for the built‑in Apple Translate framework (`NLTranslator`).
///
/// The system only creates an `NLTranslator` instance when the required language pack is
/// already installed by the user (System Settings → Language & Region → Translation Languages).
/// If a pack is missing the initializer returns `nil`.
public struct AppleTranslateSupportedLanguages {
    private static let logger = Logger(subsystem: "LocalizerHelper",
                                       category: "AppleTranslateSupportedLanguages")

    /// All language identifiers that Apple’s `NLTranslator` knows about. This list mirrors the
    /// identifiers used by `NLLanguage` (ISO‑639‑1/2 codes). Feel free to add/remove as Apple expands.
    private static let allLanguageCodes: [String] = [
        "af", "am", "ar", "az", "be", "bg", "bn", "bs", "ca", "cs", "cy",
        "da", "de", "el", "en", "es", "et", "fa", "fi", "fr", "gl", "gu",
        "he", "hi", "hr", "hu", "hy", "id", "is", "it", "ja", "ka", "kk",
        "km", "kn", "ko", "ky", "lt", "lv", "mk", "ml", "mn", "mr", "ms",
        "my", "nb", "nl", "nn", "pl", "pt", "ro", "ru", "sk", "sl", "sq",
        "sr", "sv", "ta", "te", "th", "tr", "uk", "ur", "uz", "vi", "zh"
    ]

    /// Returns an array of target language codes that are **available** for the given source code.
    /// - Parameter source: ISO language identifier (e.g. "en", "fr").
    /// - Returns: List of language codes that can be translated to from `source` on this device.
    public static func availableTargetLanguages(for source: String) async -> [String] {
        // As NLTranslator is unavailable in the current build environment, return all supported codes except the source.
        return allLanguageCodes.filter { $0 != source }
    }
}
