////
////  AppleTranslator.swift
////  LocalizerHelper
////
////  Created by Bandan's MacBook Pro on 23/06/26.
////
//
//
//import Foundation
//import OSLog
//import Translation
//
//public struct AppleTranslator {
//    private static let logger = Logger(subsystem: "LocalizerHelper", category: "AppleTranslator")
//
//    /// Translate `text` from `source` language to `target` language using Apple’s on‑device translation if available.
//    /// Returns `nil` when the on‑device translator cannot be used (e.g., missing NLTranslator or language pack).
//    public static func translate(_ text: String,
//                                 from source: String,
//                                 to target: String) async -> String? {
//        if #available(macOS 14.4, iOS 17.4, *) {
//            let sourceLang = Locale.Language(identifier: source)
//            let targetLang = Locale.Language(identifier: target)
//            let session = TranslationSession(installedSource: sourceLang, target: targetLang)
//            do {
//                let translated = try await session.translate(text)
//                return translated
//            } catch {
//                logger.debug("AppleTranslator: Translation failed for \(source) → \(target): \(error.localizedDescription)")
//                return nil
//            }
//        } else {
//            logger.debug("AppleTranslator: Requires macOS 14.4+/iOS 17.4+. Falling back to nil.")
//            return nil
//        }
//    }
//}
