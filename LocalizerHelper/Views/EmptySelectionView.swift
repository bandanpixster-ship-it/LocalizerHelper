//
//  EmptySelectionView.swift
//  LocalizerHelper
//
//  Created by Bandan's MacBook Pro on 17/06/26.
//


import SwiftUI

struct EmptySelectionView: View {
    let node: FileNode?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: iconName)
        } description: {
            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    private var title: String {
        guard let node else { return "No Project Open" }
        if node.fileKind == .swift { return "Swift File" }
        return node.name
    }

    private var subtitle: String {
        guard let node else {
            return "Choose Open Project to scan a folder for localization files."
        }
        switch node.fileKind {
        case .directory:
            return "Select a localization file or Swift source to inspect."
        case .swift:
            return "Loading string literals…"
        case .strings, .xcstrings:
            return "Localization content appears in the detail panel."
        case .other:
            return node.url.path
        }
    }

    private var iconName: String {
        guard let node else { return "folder.badge.questionmark" }
        switch node.fileKind {
        case .directory: return "folder"
        case .swift: return "swift"
        case .strings: return "text.alignleft"
        case .xcstrings: return "character.book.closed"
        case .other: return "doc"
        }
    }
}

#Preview {
    EmptySelectionView(node: nil)
}
