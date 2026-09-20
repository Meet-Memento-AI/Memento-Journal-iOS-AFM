//
//  SelectableThemeTag.swift
//  MeetMemento
//
//  Capsule tag for the onboarding theme picker (Figma 618:3691 / 608:2240).
//  Two states: unselected (sunken gray) and selected (brand copper tint with a
//  leading plus). AI-suggested themes simply start in the selected state.
//

import SwiftUI

struct SelectableThemeTag: View {
    let text: String
    let isSelected: Bool
    var onTap: (() -> Void)?

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: Spacing.xxs) {
                if isSelected {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold)) // icon-size: not user text
                        .transition(.scale.combined(with: .opacity))
                }
                Text(text)
                    .font(isSelected ? type.body2Medium : type.body2)
            }
            .foregroundStyle(isSelected ? theme.themeTagSelectedForeground : theme.mutedForeground)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                Capsule().fill(isSelected ? theme.themeTagSelectedBackground : theme.secondary)
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Previews

#Preview("Tag states — Light") {
    HStack(spacing: Spacing.xs) {
        SelectableThemeTag(text: "Mindfulness", isSelected: false)
        SelectableThemeTag(text: "Anxiety", isSelected: true)
    }
    .padding()
    .useTheme()
    .useTypography()
}

#Preview("Tag states — Dark") {
    HStack(spacing: Spacing.xs) {
        SelectableThemeTag(text: "Mindfulness", isSelected: false)
        SelectableThemeTag(text: "Anxiety", isSelected: true)
    }
    .padding()
    .useTheme()
    .useTypography()
    .preferredColorScheme(.dark)
}
