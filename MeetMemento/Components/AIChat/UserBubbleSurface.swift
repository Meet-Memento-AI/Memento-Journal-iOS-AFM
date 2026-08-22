//
//  UserBubbleSurface.swift
//  MeetMemento
//
//  The user message bubble's visual, factored out so `ChatMessageBubble` and
//  the send choreography's flying ghost render from one definition.
//

import SwiftUI
import UIKit

/// The filled, rounded surface a user's message sits in.
///
/// This exists to be shared. `SendFlightGhost` stands in for the real row for
/// the ~0.4s of the send flight and then hands off to it; if the two drifted by
/// even a point of padding or a step of font weight, that handoff would flicker.
/// Sharing one view makes the drift impossible rather than merely unlikely.
///
/// The corner radius is a parameter because the ghost interpolates it (32 → 20)
/// as it travels from the composer capsule to the bubble. Callers that are not
/// animating should pass `nil` and get the resting radius.
extension UserBubbleSurface {
    /// Minimum empty gutter to the leading edge of a user row — the
    /// `Spacer(minLength:)` in `ChatMessageBubble`'s user branch.
    static let leadingGutter: CGFloat = 60
    /// Spacing between that spacer and the bubble, i.e. the user row's
    /// `HStack` spacing.
    static let rowSpacing: CGFloat = 12

    /// Widest a user bubble can be inside a transcript column of `columnWidth`.
    ///
    /// Shared so the flying ghost wraps its text at *exactly* the width the
    /// real row will. Missing the `rowSpacing` term here made the ghost
    /// measure 12pt wider than the row it hands off to, which for text near a
    /// wrap boundary rendered one fewer line than the row — a visible reflow at
    /// the handoff.
    static func maxWidth(inColumnWidth columnWidth: CGFloat) -> CGFloat {
        max(0, columnWidth - leadingGutter - rowSpacing)
    }
}

struct UserBubbleSurface: View {
    let text: String
    /// Resting radius (`theme.radius.lg`) when nil.
    var cornerRadius: CGFloat?
    /// Photos attached to this user turn. Shown above the text when present.
    var imageJPEGs: [Data] = []

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    init(text: String, cornerRadius: CGFloat? = nil, imageJPEGs: [Data] = []) {
        self.text = text
        self.cornerRadius = cornerRadius
        self.imageJPEGs = imageJPEGs
    }

    private var hasText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !imageJPEGs.isEmpty {
                bubblePhotoRow
            }
            if hasText {
                Text(text)
                    .font(type.body1.weight(.medium))
                    .foregroundStyle(theme.foreground)
                    .lineSpacing(type.bodyLineSpacing)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
        .background(theme.secondary)
        .clipShape(
            RoundedRectangle(
                cornerRadius: cornerRadius ?? theme.radius.lg,
                style: .continuous
            )
        )
    }

    /// Compact thumbs in the transcript — the composer uses 112pt inside the
    /// glass; the bubble is a record of the send, not a second composer.
    private var bubblePhotoRow: some View {
        HStack(spacing: 6) {
            ForEach(Array(imageJPEGs.enumerated()), id: \.offset) { _, jpeg in
                if let image = UIImage(data: jpeg) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 72)
                        .clipShape(
                            RoundedRectangle(cornerRadius: theme.radius.button, style: .continuous)
                        )
                        .accessibilityLabel("Attached photo")
                }
            }
        }
    }
}

#Preview("Resting") {
    UserBubbleSurface(text: "Enter an AI user input here.")
        .padding()
        .useTheme()
        .useTypography()
}

#Preview("Composer radius") {
    UserBubbleSurface(text: "Mid-flight, at the composer's radius.", cornerRadius: 32)
        .padding()
        .useTheme()
        .useTypography()
}
