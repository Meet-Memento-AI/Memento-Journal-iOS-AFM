//
//  EntriesTag.swift
//  MeetMemento
//
//  Created by Sebastian Mendo on 1/12/26.
//

import SwiftUI

/// A rounded pill tag that displays an icon and entry count.
/// Shows a pen icon with a variable number followed by "entries" text.
struct EntriesTag: View {
    let count: Int

    @Environment(\.typography) private var type
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            // Pen/notepad icon
            Image(systemName: "square.and.pencil")
                .font(type.captionMedium)
                .foregroundStyle(theme.primaryForeground)

            // Count + "entries" text
            Text("\(count) entries")
                .font(type.captionBold)
                .foregroundStyle(theme.primaryForeground)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(
            Capsule()
                .fill(theme.primary)
        )
        .accessibilityLabel(Text("\(count) entries"))
    }
}

// MARK: - Previews

#Preview("On Purple Background") {
    ZStack {
        PrimaryScale.primary900
            .ignoresSafeArea()

        VStack(spacing: 16) {
            EntriesTag(count: 10)
            EntriesTag(count: 5)
            EntriesTag(count: 100)
            EntriesTag(count: 1)
        }
        .padding(24)
    }
    .useTypography()
}

#Preview("Multiple Sizes") {
    ZStack {
        PrimaryScale.primary900
            .ignoresSafeArea()

        VStack(spacing: 16) {
            HStack(spacing: 12) {
                EntriesTag(count: 1)
                EntriesTag(count: 10)
                EntriesTag(count: 100)
            }

            EntriesTag(count: 1000)
        }
        .padding(24)
    }
    .useTypography()
}
