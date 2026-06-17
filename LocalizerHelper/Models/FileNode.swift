import Foundation

struct FileNode: Identifiable, Hashable {
    let id: UUID
    let name: String
    let url: URL
    let isDirectory: Bool
    var children: [FileNode]
    var fileKind: FileKind

    init(
        id: UUID = UUID(),
        name: String,
        url: URL,
        isDirectory: Bool,
        children: [FileNode] = [],
        fileKind: FileKind
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.isDirectory = isDirectory
        self.children = children
        self.fileKind = fileKind
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: FileNode, rhs: FileNode) -> Bool {
        lhs.id == rhs.id
    }
}
