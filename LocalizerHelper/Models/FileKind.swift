//
//  FileKind.swift
//  LocalizerHelper
//
//  Created by Bandan's MacBook Pro on 17/06/26.
//


import Foundation

enum FileKind: Hashable {
    case directory
    case swift
    case strings
    case xcstrings
    case other

    static func from(url: URL, isDirectory: Bool) -> FileKind {
        if isDirectory { return .directory }
        switch url.pathExtension.lowercased() {
        case "swift": return .swift
        case "strings": return .strings
        case "xcstrings": return .xcstrings
        default: return .other
        }
    }
}
