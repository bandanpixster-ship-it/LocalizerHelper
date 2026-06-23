//
//  GlobalIgnoreEntry.swift
//  LocalizerHelper
//
//  Created by Bandan's MacBook Pro on 22/06/26.
//


import Foundation

struct GlobalIgnoreEntry: Codable, Identifiable, Hashable {
    var id: UUID
    let key: String
    let language: String? // nil = all languages

    init(id: UUID = UUID(), key: String, language: String?) {
        self.id = id
        self.key = key
        self.language = language
    }
}
