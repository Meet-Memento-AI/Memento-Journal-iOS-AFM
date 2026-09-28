//
//  InlineCitationBadge.swift
//  MeetMemento
//
//  Small numbered badge for citation references, used in the bottom sheet timeline.
//

import SwiftUI

struct InlineCitationBadge: View {
    let ref: Int

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    var body: some View {
        Text("\(ref)")
            .font(type.microBold)
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(theme.primary)
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

// MARK: - Previews

#Preview("Citation Badge 1") {
    InlineCitationBadge(ref: 1)
        .useTheme()
        .useTypography()
}

#Preview("Citation Badge 3") {
    InlineCitationBadge(ref: 3)
        .useTheme()
        .useTypography()
}
