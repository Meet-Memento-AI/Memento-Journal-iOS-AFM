//
//  JournalPhotoThumbnail.swift
//  MeetMemento
//
//  The composer's cover-photo preview (AddEntryView). It is NOT literally the
//  same view the saved card uses — `JournalCard.photoCardBody` inlines its own
//  layered treatment, where the photo's bottom edge is tucked under the content
//  panel. This view deliberately mirrors that treatment's visible half
//  (full-bleed, 160pt, 24pt outer rounding) so the composer previews what the
//  saved card will actually show. **Keep the two in visual sync** — if the
//  card's photo chrome changes, change this too.
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
            // Same uniform radius and inset the card uses for its cover photo,
            // so the composer previews exactly what the saved card renders.
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
            .padding(JournalCard.photoInset)
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
                .background(Circle().fill(theme.cardBackground))
                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
        }
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
