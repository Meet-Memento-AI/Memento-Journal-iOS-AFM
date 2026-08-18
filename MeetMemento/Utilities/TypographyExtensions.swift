//
//  TypographyExtensions.swift
//  MeetMemento
//
//  Created by Claude Code
//  Convenience modifiers for Typography environment access
//

import SwiftUI

// MARK: - Typography View Modifiers

extension View {
    // MARK: - Headings

    /// Apply H1 typography style (40pt bold)
    func typographyH1() -> some View {
        modifier(H1Modifier())
    }

    /// Apply H2 typography style (32pt bold)
    func typographyH2() -> some View {
        modifier(H2Modifier())
    }

    /// Apply H3 typography style (24pt semibold)
    func typographyH3() -> some View {
        modifier(H3Modifier())
    }

    /// Apply H4 typography style (20pt semibold)
    func typographyH4() -> some View {
        modifier(H4Modifier())
    }

    /// Apply H5 typography style (16pt semibold)
    func typographyH5() -> some View {
        modifier(H5Modifier())
    }

    // MARK: - Body Text

    /// Apply Body1 typography style (16pt medium)
    func typographyBody1() -> some View {
        modifier(Body1Modifier())
    }

    /// Apply Body2 typography style (14pt medium)
    func typographyBody2() -> some View {
        modifier(Body2Modifier())
    }

    // MARK: - Small Text

    /// Apply Caption typography style (13pt regular)
    func typographyCaption() -> some View {
        modifier(CaptionModifier())
    }

    /// Apply Caption Bold typography style (13pt bold)
    func typographyCaptionBold() -> some View {
        modifier(CaptionBoldModifier())
    }

    /// Apply Body1 Bold typography style (16pt bold)
    func typographyBody1Bold() -> some View {
        modifier(Body1BoldModifier())
    }

    /// Apply Body2 Bold typography style (14pt bold)
    func typographyBody2Bold() -> some View {
        modifier(Body2BoldModifier())
    }
}

// MARK: - Typography Modifiers

private struct H1Modifier: ViewModifier {
    @Environment(\.typography) private var typography
    func body(content: Content) -> some View {
        content
            .font(typography.h1)
            .lineSpacing(typography.size4XL * 0.2)
    }
}

private struct H2Modifier: ViewModifier {
    @Environment(\.typography) private var typography
    func body(content: Content) -> some View {
        content
            .font(typography.h2)
            .lineSpacing(typography.size3XL * 0.2)
    }
}

private struct H3Modifier: ViewModifier {
    @Environment(\.typography) private var typography
    func body(content: Content) -> some View {
        content
            .font(typography.h3)
            .lineSpacing(typography.size2XL * 0.2)
    }
}

private struct H4Modifier: ViewModifier {
    @Environment(\.typography) private var typography
    func body(content: Content) -> some View {
        content
            .font(typography.h4)
            .lineSpacing(typography.h4LineSpacing)
    }
}

private struct H5Modifier: ViewModifier {
    @Environment(\.typography) private var typography
    func body(content: Content) -> some View {
        content
            .font(typography.h5)
            .lineSpacing(typography.h5LineSpacing)
    }
}

private struct Body1Modifier: ViewModifier {
    @Environment(\.typography) private var typography
    func body(content: Content) -> some View {
        content.font(typography.body1)
            .lineSpacing(typography.bodyLineSpacing)
    }
}

private struct Body2Modifier: ViewModifier {
    @Environment(\.typography) private var typography
    func body(content: Content) -> some View {
        content.font(typography.body2)
            .lineSpacing(typography.bodyLineSpacing(for: typography.sizeMD))
    }
}

private struct CaptionModifier: ViewModifier {
    @Environment(\.typography) private var typography
    func body(content: Content) -> some View {
        content
            .font(typography.caption)
            .lineSpacing(max(0, typography.sizeSM * 0.5))
    }
}

private struct CaptionBoldModifier: ViewModifier {
    @Environment(\.typography) private var typography
    func body(content: Content) -> some View {
        content
            .font(typography.captionBold)
            .lineSpacing(max(0, typography.sizeSM * 0.5))
    }
}

private struct Body1BoldModifier: ViewModifier {
    @Environment(\.typography) private var typography
    func body(content: Content) -> some View {
        content
            .font(typography.body1Bold)
            .lineSpacing(typography.bodyLineSpacing)
    }
}

private struct Body2BoldModifier: ViewModifier {
    @Environment(\.typography) private var typography
    func body(content: Content) -> some View {
        content
            .font(typography.body2Bold)
            .lineSpacing(typography.bodyLineSpacing(for: typography.sizeMD))
    }
}
