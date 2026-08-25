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
     
    // MARK: - State
    @State private var isPressed = false

    // MARK: - Body
    // Kept deliberately short: the previous single ~14-modifier chain exceeded
    // the type-checker's budget in the Previews thunk build ("unable to
    // type-check this expression in reasonable time"). Each ViewModifier body
    // is its own type-checking unit.
    var body: some View {
        card
            .modifier(JournalCardInteractionModifier(
                isInteractive: isInteractive,
                isPressed: $isPressed,
                onTap: onTap,
                onEditTapped: onEditTapped,
                onDeleteTapped: onDeleteTapped
            ))
            .modifier(JournalCardAccessibilityModifier(
                isInteractive: isInteractive,
                label: accessibilityLabel,
                onTap: onTap,
                onEditTapped: onEditTapped,
                onDeleteTapped: onDeleteTapped
            ))
    }

    private var card: some View {
        Group {
            if let photoImage {
                photoCardBody(photoImage)
            } else {
                plainCardBody
            }
        }
        .pressEffect(isPressed: $isPressed, scale: 0.98, duration: Spacing.Duration.fast)
        .contentShape(Rectangle())
    }

    // MARK: - Card chrome (photo vs. plain)

    /// The no-photo card. Figma node 702:2190: a 16pt-padded column with a 12pt
    /// gap between the text block and the date chip, and a 4pt gap inside the
    /// text block. No border and no shadow — the gradient alone lifts the card
    /// off the journal canvas.
    private var plainCardBody: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            textBlock
            dateChip
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardSurface)
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
        VStack(alignment: .leading, spacing: Spacing.sm) {
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 160)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
                .padding(JournalCard.photoInset)

            textBlock
            dateChip
        }
        // Asymmetric on purpose: the image carries its own 4pt inset and sits
        // flush to the card's top edge, so only the sides and bottom take the
        // plain card's 16pt padding.
        .padding(.horizontal, Spacing.md)
        .padding(.bottom, Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardSurface)
    }

    /// Vertical wash that *darkens* downward, per Figma. Both stops are theme
    /// tokens, so the card follows light/dark instead of staying near-white on
    /// the dark canvas as it used to.
    private var journalCardGradient: LinearGradient {
        LinearGradient(
            colors: [theme.journalCardGradientStart, theme.journalCardGradientEnd],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Shared by the plain and photo cards so they stay the same surface.
    /// `theme.radius.xl` is 24 — the literal this replaces.
    private var cardSurface: some View {
        RoundedRectangle(cornerRadius: theme.radius.xl, style: .continuous)
            .fill(journalCardGradient)
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

    /// Title over excerpt at Figma's 4pt gap.
    private var textBlock: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            header
            excerptText
        }
    }

    private var excerptText: some View {
        Text(excerpt)
            .typographyBody1()
            .foregroundStyle(theme.cardForeground)
            .lineLimit(4)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The date as a capsule chip. `Spacer(minLength: 0)` keeps the chip hugging
    /// its content instead of stretching to the card's width.
    private var dateChip: some View {
        HStack(spacing: 0) {
            HStack(spacing: Spacing.xxs) {
                // Figma draws `tabler:calendar`; the SF Symbol is the same
                // outlined-calendar glyph and keeps the card on the project's
                // SF Symbols convention.
                Image(systemName: "calendar")
                    .font(type.body2)
                Text(formattedDate)
                    .font(type.body2Medium)
            }
            .foregroundStyle(theme.journalCardChipForeground)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xxs)
            .background(Capsule().fill(theme.journalCardChipBackground))

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Journal entry date \(formattedDate)")
    }

    // MARK: - Date Formatting
    private var formattedDate: String {
        let calendar = Calendar.current
        let day = calendar.component(.day, from: date)
        // One formatter for both fields — Figma reads "Saturday, October 4th".
        // The ordinal suffix below is English-only, as it already was.
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM"
        let weekdayAndMonth = formatter.string(from: date)

        return "\(weekdayAndMonth) \(day)\(ordinalSuffix(for: day))"
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

// MARK: - Gestures & hit-testing (split out of `body` for type-checker performance)
private struct JournalCardInteractionModifier: ViewModifier {
    let isInteractive: Bool
    @Binding var isPressed: Bool
    var onTap: (() -> Void)?
    var onEditTapped: (() -> Void)?
    var onDeleteTapped: (() -> Void)?

    func body(content: Content) -> some View {
        content
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
    }
}

// MARK: - Accessibility (split out of `body` for type-checker performance)
private struct JournalCardAccessibilityModifier: ViewModifier {
    let isInteractive: Bool
    let label: String
    var onTap: (() -> Void)?
    var onEditTapped: (() -> Void)?
    var onDeleteTapped: (() -> Void)?

    // Typed helpers keep literal inference out of the modifier chain — the
    // `[.isButton] : []` ternary inline was a solver hot spot.
    private var traits: AccessibilityTraits { isInteractive ? .isButton : [] }
    private var hint: String { isInteractive ? "Double-tap to open" : "" }

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)
            .accessibilityHint(hint)
            .accessibilityAddTraits(traits)
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
        .padding()
        // The real journal canvas, not `.systemBackground`: with the border and
        // shadow gone, the card only separates from `secondaryBackground`.
        .background(Theme.light.secondaryBackground)
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
    .background(Theme.light.secondaryBackground)
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
    .background(Theme.light.secondaryBackground)
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
    .background(Theme.dark.secondaryBackground)
    .useTheme()
    .useTypography()
    .preferredColorScheme(.dark)
}

#Preview("JournalCard · dark") {
    JournalCard(
        title: JournalCard.sampleTitle,
        excerpt: JournalCard.sampleExcerpt,
        date: .now
    )
    .padding()
    .background(Theme.dark.secondaryBackground)
    .useTheme()
    .useTypography()
    .preferredColorScheme(.dark)
}
