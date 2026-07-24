//
//  Chip.swift
//  MeetMemento
//
//  Reusable chip component for selectable tags/options
//

import SwiftUI

/// A selectable chip component styled according to design tokens
public struct Chip: View {
    let text: String
    let isSelected: Bool
    let onTap: () -> Void
    
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    
    public init(
        text: String,
        isSelected: Bool,
        onTap: @escaping () -> Void
    ) {
        self.text = text
        self.isSelected = isSelected
        self.onTap = onTap
    }
    
    public var body: some View {
        Button(action: onTap) {
            Text(text)
                .font(type.h6)
                .foregroundStyle(isSelected ? theme.primaryForeground : theme.foreground)
                .padding(.vertical, 12)
                .padding(.horizontal, 20)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(isSelected ? theme.primary : theme.cardBackground)
                        .shadow(
                            color: isSelected ? theme.primary.opacity(0.2) : Color.clear,
                            radius: 4,
                            x: 0,
                            y: 2
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(
                            isSelected ? Color.clear : theme.border.opacity(0.5),
                            lineWidth: 1.5
                        )
                )
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint(isSelected ? "Double-tap to deselect" : "Double-tap to select")
    }
}

// MARK: - Previews

#Preview("Chip • Unselected") {
    Chip(
        text: "Self awareness",
        isSelected: false,
        onTap: {}
    )
    .useTheme()
    .useTypography()
    .padding()
}

#Preview("Chip • Selected") {
    Chip(
        text: "Self awareness",
        isSelected: true,
        onTap: {}
    )
    .useTheme()
    .useTypography()
    .padding()
}

#Preview("Chip • Dark Mode") {
    VStack(spacing: 16) {
        Chip(
            text: "Emotion mapping",
            isSelected: false,
            onTap: {}
        )
        
        Chip(
            text: "Emotion mapping",
            isSelected: true,
            onTap: {}
        )
    }
    .useTheme()
    .useTypography()
    .padding()
    .background(Color.black)
    .preferredColorScheme(.dark)
}
