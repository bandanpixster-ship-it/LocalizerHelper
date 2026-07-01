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
        VStack(spacing: 16) {
            Image(systemName: iconName)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 64, height: 64)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(spacing: 6) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .background(
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.05),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
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
