import Foundation

struct SwiftStringLiteral: Identifiable, Hashable {
    let id: UUID
    let raw: String
    let displayPattern: String
    let hasInterpolation: Bool
    let lineNumber: Int

    init(
        id: UUID = UUID(),
        raw: String,
        displayPattern: String,
        hasInterpolation: Bool,
        lineNumber: Int
    ) {
        self.id = id
        self.raw = raw
        self.displayPattern = displayPattern
        self.hasInterpolation = hasInterpolation
        self.lineNumber = lineNumber
    }
}
