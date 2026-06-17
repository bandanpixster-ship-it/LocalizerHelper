import SwiftUI

struct SwiftStringsDetailView: View {
    let literals: [SwiftStringLiteral]
    let pendingLiterals: [SwiftStringLiteral]

    @State private var filter: Filter = .all
    @State private var sortOrder: SortOrder = .line

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case missing = "Missing"
        case present = "Present"

        var id: String { rawValue }
    }

    enum SortOrder: String, CaseIterable, Identifiable {
        case line = "Line"
        case status = "Status"
        case pattern = "Pattern"

        var id: String { rawValue }
    }

    private struct Row: Identifiable {
        let literal: SwiftStringLiteral
        let isMissing: Bool
        var id: UUID { literal.id }
    }

    private var rows: [Row] {
        let missingIDs = Set(pendingLiterals.map { $0.id })
        var rows = literals.map { literal in
            Row(literal: literal, isMissing: missingIDs.contains(literal.id))
        }

        switch filter {
        case .all:
            break
        case .missing:
            rows.removeAll { !$0.isMissing }
        case .present:
            rows.removeAll { $0.isMissing }
        }

        switch sortOrder {
        case .line:
            rows.sort { $0.literal.lineNumber < $1.literal.lineNumber }
        case .status:
            rows.sort {
                if $0.isMissing == $1.isMissing {
                    return $0.literal.lineNumber < $1.literal.lineNumber
                }
                return $0.isMissing && !$1.isMissing
            }
        case .pattern:
            rows.sort { $0.literal.displayPattern.localizedCaseInsensitiveCompare($1.literal.displayPattern) == .orderedAscending }
        }

        return rows
    }

    var body: some View {
        if literals.isEmpty {
            ContentUnavailableView("No String Literals", systemImage: "text.quote", description: Text("No double-quoted string literals were found in this file."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("String Literal Audit")
                            .font(.title3.weight(.semibold))
                        Text("Filter and sort extracted literals, with missing Localizable items highlighted.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    HStack(spacing: 12) {
                        Picker("Filter", selection: $filter) {
                            ForEach(Filter.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 320)

                        Menu {
                            ForEach(SortOrder.allCases) { option in
                                Button(option.rawValue) {
                                    sortOrder = option
                                }
                            }
                        } label: {
                            Label("Sort: \(sortOrder.rawValue)", systemImage: "arrow.up.arrow.down")
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                Table(rows) {
                    TableColumn("Pattern") { row in
                        Text(row.literal.displayPattern)
                            .font(.body)
                            .foregroundColor(.primary)
                    }
                    TableColumn("Raw") { row in
                        Text(row.literal.raw)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    TableColumn("Status") { row in
                        Text(row.isMissing ? "Missing" : "Present")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(row.isMissing ? .orange : .green)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background((row.isMissing ? Color.orange.opacity(0.16) : Color.green.opacity(0.16)), in: RoundedRectangle(cornerRadius: 12))
                    }
                    TableColumn("Line") { row in
                        Text("\(row.literal.lineNumber)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    TableColumn("Notes") { row in
                        if row.literal.hasInterpolation {
                            Text("Contains variable")
                                .foregroundStyle(.orange)
                        } else {
                            Text("—")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
                .background(.background)
                .cornerRadius(14)

                HStack(spacing: 12) {
                    Text("Showing \(rows.count) of \(literals.count) extracted literals")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if rows.count < literals.count {
                        Text("\(literals.count - rows.count) remaining")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.horizontal, 4)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
    }
}

#Preview {
    SwiftStringsDetailView(
        literals: [
            SwiftStringLiteral(raw: "\"Hello\"", displayPattern: "Hello", hasInterpolation: false, lineNumber: 1),
            SwiftStringLiteral(raw: "\"\("name") welcome\"", displayPattern: "{name} welcome", hasInterpolation: true, lineNumber: 42),
            SwiftStringLiteral(raw: "\"Missing\"", displayPattern: "Missing", hasInterpolation: false, lineNumber: 3)
        ],
        pendingLiterals: [
            SwiftStringLiteral(raw: "\"Missing\"", displayPattern: "Missing", hasInterpolation: false, lineNumber: 3)
        ]
    )
    .frame(width: 900, height: 400)
}
