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
        HStack(spacing: 10) {
            summaryChip(count: errors, label: "Errors", color: .red)
            summaryChip(count: warnings, label: "Warnings", color: .orange)
            summaryChip(count: ignored, label: "Ignored", color: .secondary)
        }
        .font(.caption)
    }

    private func summaryChip(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Text("\(count)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(color.opacity(0.14), lineWidth: 1)
        )
    }
}

#Preview {
    AuditSummaryView(errors: 3, warnings: 5, ignored: 2)
        .padding()
}
