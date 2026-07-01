//
//  ModernCard.swift
//  LocalizerHelper
//
//  Created by Bandan's MacBook Pro on 01/07/26.
//

import SwiftUI

struct ModernCard: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
            )
    }
}

extension View {
    func modernCard(padding: CGFloat = 16) -> some View {
        modifier(ModernCard(padding: padding))
    }
}
