//
//  AuditSummaryView.swift
//  LocalizerHelper
//
//  Created by Bandan's MacBook Pro on 17/06/26.
//


import SwiftUI

struct AuditSummaryView: View {
    let errors: Int
    let warnings: Int
    let ignored: Int

    var body: some View {
        HStack(spacing: 12) {
            summaryChip(count: errors, label: "errors", color: .red)
            summaryChip(count: warnings, label: "warnings", color: .orange)
            summaryChip(count: ignored, label: "ignored", color: .secondary)
        }
        .font(.caption)
    }

    private func summaryChip(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .fontWeight(.semibold)
                .foregroundStyle(color)
            Text(label)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.5), in: Capsule())
    }
}

#Preview {
    AuditSummaryView(errors: 3, warnings: 5, ignored: 2)
        .padding()
}
