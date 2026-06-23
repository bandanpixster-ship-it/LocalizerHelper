//
//  ProjectTreeView.swift
//  LocalizerHelper
//
//  Created by Bandan's MacBook Pro on 17/06/26.
//


import SwiftUI

struct ProjectTreeView: View {
    let root: FileNode
    @Binding var selection: FileNode?

    var body: some View {
        List(selection: $selection) {
            OutlineGroup(root, children: \.childrenIfDirectory) { node in
                Label {
                    Text(node.name)
                } icon: {
                    Image(systemName: iconName(for: node))
                        .foregroundStyle(iconColor(for: node))
                }
                .tag(node)
                .contextMenu {
                    Button(action: {
                        NSWorkspace.shared.selectFile(node.url.path, inFileViewerRootedAtPath: node.url.deletingLastPathComponent().path)
                    }) {
                        Label("Open in Finder", systemImage: "folder")
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func iconName(for node: FileNode) -> String {
        switch node.fileKind {
        case .directory: return "folder"
        case .swift: return "chevron.left.forwardslash.chevron.right"
        case .strings: return "text.alignleft"
        case .xcstrings: return "character.book.closed"
        case .other: return "doc"
        }
    }

    private func iconColor(for node: FileNode) -> Color {
        switch node.fileKind {
        case .directory: return .secondary
        case .swift: return .orange
        case .strings, .xcstrings: return .accentColor
        case .other: return .secondary
        }
    }
}

private extension FileNode {
    var childrenIfDirectory: [FileNode]? {
        isDirectory ? children : nil
    }
}

#Preview {
    ProjectTreeView(
        root: FileNode(
            name: "MyApp",
            url: URL(fileURLWithPath: "/tmp/MyApp"),
            isDirectory: true,
            children: [
                FileNode(name: "ContentView.swift", url: URL(fileURLWithPath: "/tmp/ContentView.swift"), isDirectory: false, fileKind: .swift)
            ],
            fileKind: .directory
        ),
        selection: .constant(nil)
    )
}
