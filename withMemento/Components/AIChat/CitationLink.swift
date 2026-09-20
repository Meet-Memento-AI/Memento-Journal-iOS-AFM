//
//  CitationLink.swift
//  MeetMemento
//
//  Citation link button styled as a tag for AI chat responses.
//
//  This MUST stay a `Button`. An ancestor keyboard-dismiss `.onTapGesture` wraps
//  the whole chat scroll view (AIChatView), and a plain `.onTapGesture` here
//  loses to it — the tap never arrives and the citations modal silently stops
//  opening. A SwiftUI `Button` is backed by UIKit control machinery and wins.
//  Replacing this with a tap gesture cost a full debugging cycle once already.
//  It also carries the `.isButton` trait the accessibility hint below promises.
//

import SwiftUI

public struct CitationLink: View {
    let count: Int
    var onTap: (() -> Void)?

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    public init(
        count: Int,
        onTap: (() -> Void)? = nil
    ) {
        self.count = count
        self.onTap = onTap
    }

    public var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 6) {
                Text("Reviewed your journals")
                    .font(type.body2)
                    .fontWeight(.bold)

                Image(systemName: "chevron.right")
                    .font(type.caption)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(BrandColors.brandOnText)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Double-tap to view journal citations")
    }
}

// MARK: - Previews

#Preview("Single Citation") {
    CitationLink(count: 1) {
        AppLogger.log("Citation tapped")
    }
    .useTheme()
    .useTypography()
}

#Preview("Multiple Citations") {
    CitationLink(count: 5) {
        AppLogger.log("Citations tapped")
    }
    .useTheme()
    .useTypography()
}

#Preview("Many Citations") {
    CitationLink(count: 12) {
        AppLogger.log("Citations tapped")
    }
    .useTheme()
    .useTypography()
}
