//
//  InsightsEmptyState.swift
//  MeetMemento
//
//  Reusable empty state view for InsightsView
//

import SwiftUI

struct InsightsEmptyState: View {
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: icon)
                .font(.system(size: 36)) // icon-size: not user text
                .foregroundStyle(theme.overlayText)

            Text(title)
                .font(type.h3)
                .fontWeight(.semibold)
                .foregroundStyle(theme.overlayText)

            Text(message)
                .font(type.body1)
                .foregroundStyle(theme.overlayTextSecondary)

            Spacer()
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 16)
    }
}

#Preview {
    InsightsEmptyState(
        icon: "sparkles",
        title: "No insights yet",
        message: "Your insights will appear here after journaling."
    )
    .background(Color.purple)
    .useTheme()
    .useTypography()
}
