//
//  CrisisResourceCard.swift
//  MeetMemento
//
//  Static crisis resource card (spec 026 / 019 R7 / REQ-SUR-004).
//  Authored content only — never model-generated counseling.
//

import SwiftUI

struct CrisisResourceCard: View {
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @Environment(\.openURL) private var openURL

    var content: CrisisResourceContent = CrisisResourceProvider.content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(content.title)
                .font(type.h5)
                .foregroundStyle(theme.foreground)

            Text(content.body)
                .font(type.body2)
                .foregroundStyle(theme.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach(content.resources) { resource in
                    Button {
                        if let url = resource.url {
                            openURL(url)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(resource.name)
                                .font(type.body2Bold)
                                .foregroundStyle(theme.primary)
                            Text(resource.detail)
                                .font(type.caption)
                                .foregroundStyle(theme.mutedForeground)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .disabled(resource.url == nil)
                    .accessibilityLabel(resource.name)
                    .accessibilityHint(resource.detail)
                }
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous)
                .fill(theme.cardBackground)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("safety.crisisResourceCard")
    }
}

#Preview {
    CrisisResourceCard()
        .useTheme()
        .useTypography()
        .padding()
}
