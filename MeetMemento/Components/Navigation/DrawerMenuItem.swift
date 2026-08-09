//
//  DrawerMenuItem.swift
//  MeetMemento
//
//  Reusable menu item row component for the slide-out drawer menu.
//

import SwiftUI

/// A menu item row with icon, title, and tap handler for the drawer menu.
public struct DrawerMenuItem: View {
    let icon: String
    let title: String
    let onTap: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    public init(icon: String, title: String, onTap: @escaping () -> Void) {
        self.icon = icon
        self.title = title
        self.onTap = onTap
    }

    public var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap()
        } label: {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .bold)) // icon-size: not user text
                    .foregroundStyle(theme.foreground)
                    .frame(width: 28, height: 28)

                Text(title)
                    .font(type.body1)
                    .foregroundStyle(theme.foreground)

                Spacer()
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview("DrawerMenuItem • Light") {
    VStack(spacing: 0) {
        DrawerMenuItem(icon: "person", title: "About yourself") {}
        DrawerMenuItem(icon: "slider.horizontal.3", title: "Your journal themes") {}
    }
    .background(Color.white)
    .useTheme()
    .useTypography()
}

#Preview("DrawerMenuItem • Dark") {
    VStack(spacing: 0) {
        DrawerMenuItem(icon: "person", title: "About yourself") {}
        DrawerMenuItem(icon: "slider.horizontal.3", title: "Your journal themes") {}
    }
    .background(Color.black)
    .useTheme()
    .useTypography()
    .preferredColorScheme(.dark)
}
