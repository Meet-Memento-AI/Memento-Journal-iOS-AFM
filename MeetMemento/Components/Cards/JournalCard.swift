import SwiftUI

/// A tiny, self-contained UI component with **pure inputs** so it can preview instantly
/// without booting your app, networking, or hitting storage.
struct JournalCard: View {
    // MARK: - Inputs (pure data only)
    let title: String
    let excerpt: String
    let date: Date
    /// The entry's decrypted cover photo, if any. Kept a plain synchronous
    /// `Image?` — no async/decrypt logic here — so this view keeps its "pure
    /// inputs, previews instantly" contract; the caller (YourEntriesView) owns
    /// the lazy decrypt+cache.
    var photoImage: Image? = nil

    /// Optional actions (no-op by default so previews never depend on app state)
    var onTap: (() -> Void)? = nil
    var onEditTapped: (() -> Void)? = nil
    var onDeleteTapped: (() -> Void)? = nil
    /// When false, all gestures and context menu are disabled (e.g. carousel preview in WelcomeView).
    var isInteractive: Bool = true

    // MARK: - Environment
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @Environment(\.colorScheme) private var colorScheme
     
    // MARK: - State
    @State private var isPressed = false

    // MARK: - Body
    var body: some View {
        Group {
            if let photoImage {
                photoCardBody(photoImage)
            } else {
                plainCardBody
            }
        }
        .pressEffect(isPressed: $isPressed, scale: 0.98, duration: Spacing.Duration.fast)
        .contentShape(Rectangle())
        .onTapGesture {
            guard isInteractive else { return }
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            onTap?()
        }
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            guard isInteractive else { return }
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }, perform: {})
        .modifier(JournalCardContextMenuModifier(isInteractive: isInteractive, onEditTapped: onEditTapped, onDeleteTapped: onDeleteTapped))
        .allowsHitTesting(isInteractive)
        // MARK: - Accessibility
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(isInteractive ? "Double-tap to open" : "")
        .accessibilityAddTraits(isInteractive ? [.isButton] : [])
        .accessibilityAction(named: "Open") {
            onTap?()
        }
        .accessibilityAction(named: "Edit") {
            onEditTapped?()
        }
        .accessibilityAction(named: "Delete") {
            onDeleteTapped?()
        }
    }

    // MARK: - Card chrome (photo vs. plain)

    /// Today's shipped card — unchanged. Used when there's no photo.
    private var plainCardBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .hPadding(Spacing.lg)
                .padding(.top, Spacing.lg)

            Text(excerpt)
                .typographyBody1()
                .foregroundStyle(theme.mutedForeground)
                .lineLimit(5)
                .multilineTextAlignment(.leading)
                .hPadding(Spacing.lg)
                .padding(.top, Spacing.sm)

            footer
                .hPadding(Spacing.lg)
                .vPadding(Spacing.md)
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [theme.secondary, theme.card], // Use semantic tokens
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(colorScheme == .dark ? GrayScale.gray900 : .white, lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
    }

    /// With-photo layout: a cover image inset evenly inside the card with the
    /// SAME corner radius on all four corners, sitting above the text content.
    /// (This deliberately departs from Figma node 395:5120, which tucked the
    /// image's bottom edge under an overlapping panel so only its top corners
    /// were rounded — uniform rounding was preferred.)
    ///
    /// The 4pt inset and `theme.radius.lg` (20) are concentric with the card's
    /// own 24pt radius (24 − 4 = 20), so the image's curve stays parallel to
    /// the card's rather than visually fighting it.
    private func photoCardBody(_ image: Image) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 160)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
                .padding(JournalCard.photoInset)

            header
                .hPadding(Spacing.md)
                .padding(.top, Spacing.sm)

            Text(excerpt)
                .typographyBody1()
                .foregroundStyle(theme.mutedForeground)
                .lineLimit(5)
                .multilineTextAlignment(.leading)
                .hPadding(Spacing.md)
                .padding(.top, Spacing.xs)

            footer
                .hPadding(Spacing.md)
                .padding(.top, Spacing.xs)
                .padding(.bottom, Spacing.md)
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [theme.secondary, theme.card], // same tokens as the plain card
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(colorScheme == .dark ? GrayScale.gray900 : .white, lineWidth: 2)
        )
        .shadow(color: Color(red: 51 / 255, green: 51 / 255, blue: 51 / 255).opacity(0.16), radius: 8, x: 0, y: 4)
    }

    /// Even inset around the cover photo. Shared with the composer's preview
    /// (`JournalPhotoThumbnail`) so the two stay visually identical.
    static let photoInset: CGFloat = 4

    // MARK: - Subviews
    private var header: some View {
        Text(title)
            .typographyH5()
            .foregroundStyle(theme.foreground)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(type.body2)
                .fontWeight(.bold)
                .foregroundStyle(theme.primary)
                .cornerRadius(16)
            Text(formattedDate)
                .typographyCaptionBold()
                .foregroundStyle(theme.mutedForeground)

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Journal entry date \(formattedDate)")
    }

    // MARK: - Date Formatting
    private var formattedDate: String {
        let calendar = Calendar.current
        let day = calendar.component(.day, from: date)
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMMM"
        let monthName = monthFormatter.string(from: date)

        return "\(monthName) \(day)\(ordinalSuffix(for: day))"
    }

    private func ordinalSuffix(for day: Int) -> String {
        switch day {
        case 1, 21, 31:
            return "st"
        case 2, 22:
            return "nd"
        case 3, 23:
            return "rd"
        default:
            return "th"
        }
    }

    private var accessibilityLabel: String {
        let photoSuffix = photoImage != nil ? ", with photo" : ""
        return "Journal card, \(title)\(photoSuffix). Dated \(formattedDate). \(excerpt)"
    }
}

// MARK: - Context menu only when interactive
private struct JournalCardContextMenuModifier: ViewModifier {
    let isInteractive: Bool
    var onEditTapped: (() -> Void)?
    var onDeleteTapped: (() -> Void)?

    func body(content: Content) -> some View {
        if isInteractive {
            content.contextMenu {
                Button(action: { onEditTapped?() }) {
                    Label("Edit", systemImage: "pencil")
                }
                Button(role: .destructive, action: { onDeleteTapped?() }) {
                    Label("Delete", systemImage: "trash")
                }
            }
        } else {
            content
        }
    }
}

// MARK: - Sample Data (for previews & local playgrounds)
extension JournalCard {
    static let sampleTitle = "Morning Reflection"
    static let sampleExcerpt = "I woke up feeling a bit groggy and not entirely refreshed. The alarm felt a bit harsh, and I struggled to get out of bed. Once I did, I noticed that the sky .."
}

// MARK: - SIDE-CAR PREVIEW HARNESS
// Keep previews in the same file for convenience, or move into `JournalCard+Preview.swift`.
// Import NOTHING from your app target here besides SwiftUI and this view file.
private struct JournalCardHarness: View {
    // Create January 2026 date for preview
    private var previewDate: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 15
        return Calendar.current.date(from: components) ?? .now
    }

    var body: some View {
        JournalCard(
            title: JournalCard.sampleTitle,
            excerpt: JournalCard.sampleExcerpt,
            date: previewDate,
            onTap: { /* no-op for harness */ },
            onEditTapped: { /* no-op for harness */ },
            onDeleteTapped: { /* no-op for harness */ }
        )
        .frame(maxWidth: .infinity) // allow card to stretch
        .background(Color(uiColor: .systemBackground))
        .useTheme()
        .useTypography()
    }
}



#Preview("JournalCard · light") {
    JournalCardHarness()
}


#Preview("JournalCard · long text") {
    JournalCard(
        title: "Weekly review and planning checklist for Q4",
        excerpt: "What went well: shipped UI preview harnesses, stabilized Xcode canvas. What to improve: fewer side effects in initializers, mock services end-to-end. Next: polish the on-device flows before release.",
        date: .now.addingTimeInterval(-36_00)
    )
    .padding()
    .background(Color(uiColor: .systemBackground))
    .useTheme()
    .useTypography()
}

private enum JournalCardPreviewAssets {
    /// Opaque stand-in for a real photo. An SF Symbol can't be used here: under
    /// `.aspectRatio(.fill)` it renders as a vector glyph on a transparent
    /// canvas, which misrepresents how an opaque photo tiles the 160pt strip.
    /// A shape can't be used either — `photoImage` is an `Image`, which SwiftUI
    /// cannot build from a `Rectangle`, so a bitmap is unavoidable.
    ///
    /// Intrinsic size is irrelevant (the card scales it with `.resizable()` +
    /// `.aspectRatio(.fill)`), so this is deliberately tiny, and `static let`
    /// means it renders once rather than per preview instantiation.
    static let photo: Image = {
        let size = CGSize(width: 4, height: 3)
        let uiImage = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return Image(uiImage: uiImage)
    }()
}

#Preview("JournalCard · with photo") {
    JournalCard(
        title: JournalCard.sampleTitle,
        excerpt: JournalCard.sampleExcerpt,
        date: .now,
        photoImage: JournalCardPreviewAssets.photo
    )
    .padding()
    .background(Color(uiColor: .systemBackground))
    .useTheme()
    .useTypography()
}

#Preview("JournalCard · with photo, dark") {
    JournalCard(
        title: JournalCard.sampleTitle,
        excerpt: JournalCard.sampleExcerpt,
        date: .now,
        photoImage: JournalCardPreviewAssets.photo
    )
    .padding()
    .background(Color(uiColor: .systemBackground))
    .useTheme()
    .useTypography()
    .preferredColorScheme(.dark)
}
