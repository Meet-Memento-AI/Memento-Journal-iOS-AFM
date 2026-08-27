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

    /// Densifies `.regular` frost the same way the composer and Welcome CTA do:
    /// a light canvas tint *through* the material, never an opaque fill under it.
    /// `.interactive()` is intentionally off — it scales the glass and paints a
    /// second rim, which is the radius mismatch on press.
    private static let glassFrostTintOpacity: Double = 0.24

    // MARK: - Body
    // Kept deliberately short: the previous single ~14-modifier chain exceeded
    // the type-checker's budget in the Previews thunk build ("unable to
    // type-check this expression in reasonable time"). Each ViewModifier body
    // is its own type-checking unit.
    var body: some View {
        card
            .modifier(JournalCardInteractionModifier(
                isInteractive: isInteractive,
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

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: theme.radius.xl, style: .continuous)
    }

    /// Untinted interactive glass is what made the fill and the specular edge
    /// disagree on press. This is static `.regular` frost, tinted for density,
    /// in the same continuous 24pt rect every other state uses.
    private var glassMaterial: Glass {
        .regular.tint(theme.background.opacity(Self.glassFrostTintOpacity))
    }

    private var card: some View {
        Group {
            if let photoImage {
                photoCardBody(photoImage)
            } else {
                plainCardBody
            }
        }
    }

    /// One continuous 24pt rect for content clip, glass, hit target, and the
    /// system container (press highlight, context-menu preview). No
    /// `.interactive()` — it re-paints a second rim.
    private func cardChrome<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(cardShape)
            .glassEffect(glassMaterial, in: cardShape)
            .contentShape(cardShape)
            .containerShape(cardShape)
    }

    // MARK: - Card chrome (photo vs. plain)

    /// The no-photo card. Figma node 702:2190: a 16pt-padded column with a 12pt
    /// gap between the text block and the date chip, and a 4pt gap inside the
    /// text block. Glass — not an opaque gradient — lifts the card off the
    /// journal canvas. Applied to this stack (the view that contains the type),
    /// never as a sibling `.background`, so title and excerpt get vibrancy.
    private var plainCardBody: some View {
        cardChrome {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                textBlock
                dateChip
            }
            .padding(Spacing.md)
        }
    }

    /// With-photo layout: cover image above the same text block and date chip
    /// as the plain card. One `Spacing.md` pad on every edge — including the
    /// top — so the photo shares the title's margin instead of sitting 4pt
    /// from the glass while the type sits 16pt in.
    ///
    /// Photo corners are concentric with the card: radius is
    /// `theme.radius.xl − photoInset` (24 − 16 = 8).
    private func photoCardBody(_ image: Image) -> some View {
        cardChrome {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 160)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(
                        cornerRadius: theme.radius.xl - JournalCard.photoInset,
                        style: .continuous
                    ))

                textBlock
                dateChip
            }
            .padding(Spacing.md)
        }
    }

    /// Inset from the card edge to the cover photo. Same token as the text
    /// padding (`Spacing.md`) so photo and type share one margin. Shared with
    /// the composer's preview (`JournalPhotoThumbnail`) for the concentric
    /// corner radius.
    static let photoInset: CGFloat = Spacing.md

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
    @Environment(\.theme) private var theme
    let isInteractive: Bool
    var onTap: (() -> Void)?
    var onEditTapped: (() -> Void)?
    var onDeleteTapped: (() -> Void)?

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: theme.radius.xl, style: .continuous)
    }

    func body(content: Content) -> some View {
        if isInteractive {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onTap?()
            } label: {
                content
            }
            // Identity style: `.plain` can still dim, and `.interactive()` glass
            // paints a second rim. The fill must not change on press.
            .buttonStyle(JournalCardButtonStyle())
            .buttonBorderShape(.roundedRectangle(radius: theme.radius.xl))
            .containerShape(cardShape)
            .modifier(JournalCardContextMenuModifier(
                isInteractive: true,
                onEditTapped: onEditTapped,
                onDeleteTapped: onDeleteTapped
            ))
        } else {
            content
                .allowsHitTesting(false)
        }
    }
}

private struct JournalCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
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
    @Environment(\.theme) private var theme
    let isInteractive: Bool
    var onEditTapped: (() -> Void)?
    var onDeleteTapped: (() -> Void)?

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: theme.radius.xl, style: .continuous)
    }

    func body(content: Content) -> some View {
        if isInteractive {
            content
                .contentShape(.contextMenuPreview, cardShape)
                .contextMenu {
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
        // Journal canvas behind the card so glass has something to refract.
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
