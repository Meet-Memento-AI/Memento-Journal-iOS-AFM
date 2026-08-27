# Component Template

This template demonstrates best practices for creating new card components using MeetMemento's utility system.

## Basic Card Component Template

```swift
import SwiftUI

/// A card component that displays [description of what this card does].
///
/// Features:
/// - Standard card styling with rounded corners
/// - Interactive press effects with haptic feedback
/// - Semantic spacing and typography
public struct ExampleCard: View {
    // MARK: - Inputs (pure data only for easy previews)

    let title: String
    let subtitle: String
    var icon: String? = nil

    /// Optional tap action for navigation/interaction
    var onTap: (() -> Void)? = nil

    // MARK: - Environment

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    // MARK: - State

    @State private var isPressed = false

    // MARK: - Initializer

    public init(
        title: String,
        subtitle: String,
        icon: String? = nil,
        onTap: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.onTap = onTap
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Header
            HStack(spacing: Spacing.sm) {
                if let icon {
                    Image(systemName: icon)
                        .typographyH4()
                        .foregroundStyle(theme.primary)
                }

                Text(title)
                    .typographyH4()
                    .foregroundStyle(theme.foreground)

                Spacer()
            }

            // Content
            Text(subtitle)
                .typographyBody2()
                .foregroundStyle(theme.mutedForeground)
                .lineLimit(3)
        }
        .hPadding(Spacing.md)
        .vPadding(Spacing.md)
        .cardStyle(radius: 24, border: false, shadow: true)
        .pressEffect(isPressed: $isPressed)
        .contentShape(Rectangle())
        .onTapGesture {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            onTap?()
        }
        .onLongPressGesture(minimumDuration: 0, pressing: { pressing in
            withAnimation(.easeInOut(duration: Spacing.Duration.fast)) {
                isPressed = pressing
            }
        }, perform: {})
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Helpers

    private var accessibilityLabel: String {
        var label = title
        if let icon { label = "\\(icon), " + label }
        label += ", \\(subtitle)"
        return label
    }
}

// MARK: - Sample Data (for previews)

extension ExampleCard {
    static let sampleTitle = "Sample Title"
    static let sampleSubtitle = "This is a sample subtitle that demonstrates how the card looks."
}

// MARK: - Preview

#Preview("Light") {
    VStack(spacing: Spacing.md) {
        ExampleCard(
            title: ExampleCard.sampleTitle,
            subtitle: ExampleCard.sampleSubtitle,
            icon: "sparkles",
            onTap: { print("Tapped") }
        )

        ExampleCard(
            title: "No Icon Example",
            subtitle: "This card doesn't have an icon."
        )
    }
    .padding()
    .background(theme.background)
    .useTheme()
    .useTypography()
}

#Preview("Dark") {
    VStack(spacing: Spacing.md) {
        ExampleCard(
            title: ExampleCard.sampleTitle,
            subtitle: ExampleCard.sampleSubtitle,
            icon: "sparkles"
        )
    }
    .padding()
    .background(theme.background)
    .useTheme()
    .useTypography()
    .preferredColorScheme(.dark)
}
```

## Key Patterns

### 1. Use Semantic Spacing

```swift
// Horizontal padding
.hPadding(Spacing.md)  // 16pt

// Vertical padding
.vPadding(Spacing.lg)  // 20pt

// Specific edge
.padding(.top, Spacing.xl)  // 24pt

// Stack spacing
VStack(spacing: Spacing.sm) { }  // 12pt
```

### 2. Use Typography Modifiers

```swift
// Headings
Text("Title").typographyH3()      // Section heading
Text("Subtitle").typographyH5()   // Minor heading

// Body text
Text("Content").typographyBody1()      // Primary text
Text("Details").typographyBody2()      // Secondary text

// Small text
Text("Caption").typographyCaption()    // Regular caption
Text("Label").typographyCaptionBold()  // Bold caption
```

### 3. Use Card Styling Modifier

```swift
// Basic card (no border, with shadow)
.cardStyle()

// Card with border and shadow
.cardStyle(radius: 24, border: true, shadow: true)

// Card without shadow
.cardStyle(radius: 16, border: false, shadow: false)
```

### 4. Use Press Effects

```swift
@State private var isPressed = false

var body: some View {
    VStack { }
        .pressEffect(isPressed: $isPressed)
        .onLongPressGesture(minimumDuration: 0, pressing: { pressing in
            withAnimation {
                isPressed = pressing
            }
        }, perform: {})
}
```

### 5. Use Opacity Constants

```swift
// Disabled state
.opacity(Spacing.Opacity.disabled)  // 0.6

// Borders
.stroke(color, lineWidth: 1)
    .opacity(Spacing.Opacity.border)  // 0.15

// Overlays
.background(color.opacity(Spacing.Opacity.overlay))  // 0.2

// Muted text
.foregroundStyle(color.opacity(Spacing.Opacity.muted))  // 0.95
```

### 6. Use Animation Durations

```swift
// Fast animations (quick transitions)
.animation(.easeInOut(duration: Spacing.Duration.fast))  // 0.1s

// Standard animations (default)
.animation(.easeInOut(duration: Spacing.Duration.standard))  // 0.15s

// Slow animations (deliberate transitions)
.animation(.easeInOut(duration: Spacing.Duration.slow))  // 0.3s
```

## Advanced: Custom Gradient Card

For cards with custom backgrounds, you can skip `.cardStyle()` and use custom styling while still using spacing and typography:

```swift
VStack {
    // Content with typography modifiers
}
.vPadding(Spacing.md)
.hPadding(Spacing.md)
.background(
    RoundedRectangle(cornerRadius: 24, style: .continuous)
        .fill(
            LinearGradient(
                gradient: Gradient(colors: [color1, color2]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
)
.overlay(
    RoundedRectangle(cornerRadius: 24, style: .continuous)
        .stroke(
            .white.opacity(Spacing.Opacity.border),
            lineWidth: 1
        )
)
.shadow(color: .black.opacity(Spacing.Opacity.border), radius: 12, x: 0, y: 6)
.pressEffect(isPressed: $isPressed)
```

## Checklist for New Components

- [ ] Use semantic spacing constants (Spacing.md, Spacing.lg, etc.)
- [ ] Use typography modifiers (.typographyH3(), .typographyBody1(), etc.)
- [ ] Use opacity constants (Spacing.Opacity.disabled, etc.)
- [ ] Use animation duration constants (Spacing.Duration.fast, etc.)
- [ ] Apply `.cardStyle()` for standard cards
- [ ] Apply `.pressEffect()` for interactive elements
- [ ] Include accessibility labels
- [ ] Create sample data for previews
- [ ] Add both light and dark mode previews
- [ ] Document component with clear comments

---

**See Also:** `README.md` for detailed documentation on all utilities.
