//
//  BottomTab.swift
//  MeetMemento
//
//  Individual tab component following Apple HIG tab bar styling
//  Uses native SF Symbols and system typography
//

import SwiftUI

public struct BottomTab: View {
    public let title: String
    public let systemImage: String
    public let isSelected: Bool
    public var onTap: (() -> Void)?
    
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @Environment(\.colorScheme) private var colorScheme
    
    public init(
        title: String,
        systemImage: String,
        isSelected: Bool,
        onTap: (() -> Void)? = nil
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.onTap = onTap
    }
    
    public var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap?()
        } label: {
            VStack(spacing: 4) {
                // SF Symbol icon following native tab bar sizing
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .bold)) // icon-size: not user text
                    .symbolVariant(isSelected ? .fill : .none)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(
                        isSelected
                            ? theme.primary
                            : Color.primary.opacity(0.6)
                    )
                
                // Label text following native tab bar typography
                Text(title)
                    .font(isSelected ? type.microMedium : type.micro)
                    .foregroundStyle(
                        isSelected
                            ? theme.primary
                            : Color.primary.opacity(0.6)
                    )
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Previews

#Preview("BottomTab • Selected") {
    BottomTab(
        title: "Journal",
        systemImage: "book.closed.fill",
        isSelected: true
    )
    .padding()
    .useTheme()
    .useTypography()
}

#Preview("BottomTab • Unselected") {
    BottomTab(
        title: "Insights",
        systemImage: "sparkles",
        isSelected: false
    )
    .padding()
    .useTheme()
    .useTypography()
}