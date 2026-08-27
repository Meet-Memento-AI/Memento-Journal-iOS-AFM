//
//  JournalPhotoThumbnail.swift
//  MeetMemento
//
//  The composer's cover-photo preview (AddEntryView). Mirrors the saved
//  JournalCard photo: 160pt tall, corners concentric with a 24pt card at
//  `JournalCard.photoInset`. **Keep the two in visual sync.**
//

import SwiftUI

struct JournalPhotoThumbnail: View {
    let image: Image
    /// When true, shows a removal badge in the top-trailing corner.
    var removable: Bool = false
    var onRemove: (() -> Void)? = nil

    @Environment(\.theme) private var theme

    var body: some View {
        image
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(height: 160)
            .frame(maxWidth: .infinity)
            // Same concentric radius the card uses for its cover photo.
            .clipShape(RoundedRectangle(
                cornerRadius: theme.radius.xl - JournalCard.photoInset,
                style: .continuous
            ))
            .overlay(alignment: .topTrailing) {
                if removable {
                    removeBadge
                        .padding(8)
                }
            }
    }

    private var removeBadge: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onRemove?()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold)) // icon-size: not user text
                .foregroundStyle(theme.foreground)
                .frame(width: 28, height: 28)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove photo")
        .accessibilityHint("Double-tap to remove the attached photo")
    }
}

// MARK: - Previews

// Uses an opaque filled rectangle rather than an SF Symbol: a symbol renders
// as a vector glyph on a transparent canvas under `.aspectRatio(.fill)`, which
// misrepresents how a real (opaque, fully tiling) photo looks here.
#Preview("With remove badge") {
    JournalPhotoThumbnail(
        image: Image(systemName: "photo.fill"),
        removable: true,
        onRemove: {}
    )
    .background(Color.gray)
    .padding()
    .useTheme()
}

#Preview("No remove badge") {
    JournalPhotoThumbnail(image: Image(systemName: "photo.fill"))
        .background(Color.gray)
        .padding()
        .useTheme()
}
