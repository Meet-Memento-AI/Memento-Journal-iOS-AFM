//
//  TipCard.swift
//  MeetMemento
//
//  Shared tip card component for loading screens
//

import SwiftUI

struct TipCard: View {
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    let icon: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Icon container
            ZStack {
                Circle()
                    .fill(theme.primary.opacity(0.12))
                    .frame(width: 44, height: 44)

                Image(systemName: icon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(theme.primary)
            }

            // Content
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(type.body1Bold)
                    .foregroundStyle(theme.foreground)

                Text(message)
                    .font(type.body1)
                    .foregroundStyle(theme.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(theme.card)
                .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
        )
    }
}

#Preview("Tip Card") {
    TipCard(
        icon: "heart.fill",
        title: "Daily practice",
        message: "Journaling for just 5 minutes a day can improve mental clarity and reduce stress."
    )
    .padding()
    .useTheme()
    .useTypography()
}
