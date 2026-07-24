//
//  JournalToast.swift
//  MeetMemento
//
//  Toast notification component for journal entry actions.
//

import SwiftUI

struct JournalToast: View {
    let message: String
    var onDismiss: (() -> Void)?

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20)) // icon-size: not user text
                .foregroundStyle(theme.primary)

            Text(message)
                .font(type.body2)
                .foregroundStyle(theme.foreground)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            Capsule()
                .fill(theme.card)
                .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
        )
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                onDismiss?()
            }
        }
    }
}

// MARK: - Previews

#Preview("Toast • Light") {
    ZStack {
        Color.gray.opacity(0.2)
            .ignoresSafeArea()

        VStack {
            Spacer()
            JournalToast(message: "Entry saved")
                .padding(.bottom, 100)
        }
    }
    .useTheme()
}

#Preview("Toast • Dark") {
    ZStack {
        Color.black
            .ignoresSafeArea()

        VStack {
            Spacer()
            JournalToast(message: "Entry saved")
                .padding(.bottom, 100)
        }
    }
    .useTheme()
    .preferredColorScheme(.dark)
}
