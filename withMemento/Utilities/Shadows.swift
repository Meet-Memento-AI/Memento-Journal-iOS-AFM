//
//  Shadows.swift
//  MeetMemento
//
//  Standardized shadow constants for consistent visual hierarchy.
//

import SwiftUI

// MARK: - Shadow Definition

struct Shadow {
    let color: Color
    let radius: CGFloat
    let y: CGFloat
    var x: CGFloat = 0
}

// MARK: - Shadow Presets

struct Shadows {
    /// Very subtle shadow for cards and containers
    /// Use for: loading states, background cards
    static let subtle = Shadow(color: .black.opacity(0.04), radius: 8, y: 2)

    /// Light shadow for interactive elements
    /// Use for: chips, tags, small buttons
    static let light = Shadow(color: .black.opacity(0.08), radius: 4, y: 2)

    /// Medium shadow for prominent elements
    /// Use for: FABs, dropdowns, overlays
    static let medium = Shadow(color: .black.opacity(0.1), radius: 6, y: 3)

    /// Strong shadow for elevated elements
    /// Use for: modals, popovers, drag handles
    static let strong = Shadow(color: .black.opacity(0.15), radius: 8, y: 4)

    /// Very light drop shadow for white type sitting on a treated cover
    /// (journal cards and the photo editor). Contrast without a dark plate.
    static let photoText = Shadow(
        color: .black.opacity(0.30),
        radius: 4,
        y: 1.5
    )
}

// MARK: - View Extension

extension View {
    /// Applies a standardized shadow style
    func shadow(_ style: Shadow) -> some View {
        self.shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }

    /// Drop shadow drawn *in* the glyphs (ShapeStyle `.drop`). One view type
    /// either way — a `@ViewBuilder` if/else around `TextEditor` in the
    /// zooming create destination collapsed the page to an empty plate.
    func photoCoverForeground(_ color: Color, shadowed: Bool) -> some View {
        let style: AnyShapeStyle = {
            guard shadowed else { return AnyShapeStyle(color) }
            return AnyShapeStyle(
                color.shadow(.drop(
                    color: Shadows.photoText.color,
                    radius: Shadows.photoText.radius,
                    x: Shadows.photoText.x,
                    y: Shadows.photoText.y
                ))
            )
        }()
        return foregroundStyle(style)
    }
}

// MARK: - Preview

#Preview("Shadow Styles") {
    VStack(spacing: 32) {
        shadowPreviewCard(label: "Subtle", shadow: Shadows.subtle)
        shadowPreviewCard(label: "Light", shadow: Shadows.light)
        shadowPreviewCard(label: "Medium", shadow: Shadows.medium)
        shadowPreviewCard(label: "Strong", shadow: Shadows.strong)
    }
    .padding(32)
    .background(Color.gray.opacity(0.1))
}

@ViewBuilder
private func shadowPreviewCard(label: String, shadow: Shadow) -> some View {
    VStack {
        Text(label)
            .font(.headline)
        Text("opacity: \(shadow.color.description)")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    .frame(width: 200, height: 80)
    .background(Color.white)
    .cornerRadius(12)
    .shadow(shadow)
}
