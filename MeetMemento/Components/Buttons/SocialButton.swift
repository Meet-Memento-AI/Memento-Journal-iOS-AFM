//
//  SocialButton.swift
//  MeetMemento
//
//  Generic social sign-in button.
//

import SwiftUI

public struct SocialButton: View {
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    let title: String
    let systemImage: String?
    var action: () -> Void

    public init(title: String, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage).font(.system(size: 16, weight: .bold)) }
                Text(title).font(type.button).fontWeight(.semibold)
            }
            .frame(height: 48)
            .frame(maxWidth: .infinity)
            .background(theme.primary)
            .foregroundStyle(theme.primaryForeground)
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.button, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: theme.radius.button, style: .continuous)
                    .stroke(theme.ring.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}

#Preview("Light") {
    VStack(spacing: 12) {
        SocialButton(title: "Continue with Google", systemImage: "globe") {}
        SocialButton(title: "Continue with Apple", systemImage: "apple.logo") {}
    }
    .padding()
    .useTheme()
    .useTypography()
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    VStack(spacing: 12) {
        SocialButton(title: "Continue with Google", systemImage: "globe") {}
        SocialButton(title: "Continue with Apple", systemImage: "apple.logo") {}
    }
    .padding()
    .useTheme()
    .useTypography()
    .preferredColorScheme(.dark)
}
