# MeetMemento Utilities

This directory contains reusable utilities and helper functions that promote code consistency and reduce duplication across the app.

## Table of Contents

- [Spacing](#spacing)
- [Typography Extensions](#typography-extensions)
- [View Modifiers](#view-modifiers)
- [Best Practices](#best-practices)

## Spacing

**File:** `Spacing.swift`

Semantic spacing scale for consistent padding, margins, and gaps throughout the app.

### Spacing Scale

```swift
Spacing.xxs  // 4pt  - Minimal gaps
Spacing.xs   // 8pt  - Tight spacing
Spacing.sm   // 12pt - Compact
Spacing.md   // 16pt - Standard (default for most UI)
Spacing.lg   // 20pt - Comfortable
Spacing.xl   // 24pt - Spacious
Spacing.xxl  // 32pt - Section breaks
Spacing.xxxl // 40pt - Major sections
```

### Opacity Constants

```swift
Spacing.Opacity.disabled  // 0.6  - Disabled state
Spacing.Opacity.subtle    // 0.3  - Subtle overlays/backgrounds
Spacing.Opacity.muted     // 0.95 - Muted text/UI elements
Spacing.Opacity.border    // 0.15 - Border opacity
Spacing.Opacity.overlay   // 0.2  - Overlay backgrounds
```

### Animation Durations

```swift
Spacing.Duration.fast     // 0.1s - Quick transitions
Spacing.Duration.standard // 0.15s - Default duration
Spacing.Duration.slow     // 0.3s - Deliberate transitions
```

### Usage Example

```swift
VStack {
    Text("Title")
        .hPadding(Spacing.md)          // Horizontal: 16pt
        .padding(.top, Spacing.xl)      // Top: 24pt

    Divider()
        .opacity(Spacing.Opacity.border) // 0.15
}
.vPadding(Spacing.lg)  // Vertical: 20pt
```

## Typography Extensions

**File:** `TypographyExtensions.swift`

Convenience modifiers for easy access to the Typography environment system.

### Available Modifiers

#### Headings
```swift
.typographyH1()  // 40pt bold - Major display heading
.typographyH2()  // 32pt bold - Secondary display heading
.typographyH3()  // 24pt semibold - Section heading
.typographyH4()  // 20pt semibold - Subsection heading
.typographyH5()  // 16pt semibold - Minor heading
```

#### Body Text
```swift
.typographyBody1()      // 16pt medium - Primary body text
.typographyBody1Bold()  // 16pt bold - Strong body text
.typographyBody2()      // 14pt medium - Secondary body text
.typographyBody2Bold()  // 14pt bold - Strong secondary text
```

#### Small Text
```swift
.typographyCaption()      // 13pt regular - Caption text
.typographyCaptionBold()  // 13pt bold - Strong caption
```

### Usage Example

```swift
VStack(alignment: .leading) {
    Text("Section Title")
        .typographyH3()
        .foregroundStyle(theme.foreground)

    Text("This is the main content of the section.")
        .typographyBody1()
        .foregroundStyle(theme.mutedForeground)

    Text("Caption text")
        .typographyCaption()
        .foregroundStyle(theme.mutedForeground)
}
```

### Migration from Custom Fonts

**Before:**
```swift
Text("Title")
    .font(.custom("Manrope-Bold", size: 16))
```

**After:**
```swift
Text("Title")
    .typographyH5()  // 16pt semibold/bold
```

## View Modifiers

**File:** `ViewModifiers.swift`

Reusable view modifiers for consistent UI patterns.

### Card Styling

Apply standard card styling with rounded corners, background, optional border, and shadow.

```swift
.cardStyle(
    radius: CGFloat = 24,     // Corner radius
    border: Bool = false,     // Show border
    shadow: Bool = true       // Show shadow
)
```

**Example:**
```swift
VStack {
    // Card content
}
.padding(Spacing.md)
.cardStyle(radius: 24, border: true, shadow: true)
```

### Press Effects

Apply press/scale animation effect for interactive elements.

```swift
.pressEffect(
    isPressed: Binding<Bool>,           // Binding to pressed state
    scale: CGFloat = 0.98,              // Scale factor when pressed
    duration: CGFloat = Spacing.Duration.fast
)
```

**Example:**
```swift
@State private var isPressed = false

var body: some View {
    VStack {
        // Interactive content
    }
    .cardStyle()
    .pressEffect(isPressed: $isPressed)
    .onLongPressGesture(minimumDuration: 0, pressing: { pressing in
        withAnimation {
            isPressed = pressing
        }
    }, perform: {})
}
```

### Haptic Feedback

Add haptic feedback to tap gestures.

```swift
.hapticTap(
    style: UIImpactFeedbackGenerator.FeedbackStyle = .light,
    action: @escaping () -> Void
)
```

**Example:**
```swift
Button("Tap me") {}
    .hapticTap(style: .light) {
        print("Tapped with haptic!")
    }
```

### Spacing Shortcuts

Convenient horizontal and vertical padding helpers.

```swift
.hPadding(_ value: CGFloat = Spacing.md)  // Horizontal padding
.vPadding(_ value: CGFloat = Spacing.md)  // Vertical padding
```

**Example:**
```swift
VStack {
    Text("Content")
}
.hPadding(Spacing.lg)    // 20pt horizontal
.vPadding(Spacing.md)    // 16pt vertical
```

## Best Practices

### 1. Use Semantic Spacing

**Don't:**
```swift
.padding(.horizontal, 16)
.padding(.top, 24)
.opacity(0.6)
```

**Do:**
```swift
.hPadding(Spacing.md)
.padding(.top, Spacing.xl)
.opacity(Spacing.Opacity.disabled)
```

### 2. Use Typography Modifiers

**Don't:**
```swift
.font(.custom("Manrope-Bold", size: 16))
```

**Do:**
```swift
.typographyH5()
```

### 3. Consolidate Card Styling

**Don't:**
```swift
.background(
    RoundedRectangle(cornerRadius: 24, style: .continuous)
        .fill(theme.cardBackground)
)
.overlay(
    RoundedRectangle(cornerRadius: 24, style: .continuous)
        .stroke(theme.border, lineWidth: 1)
)
.shadow(color: theme.shadow, radius: 8, x: 0, y: 4)
```

**Do:**
```swift
.cardStyle(radius: 24, border: true, shadow: true)
```

### 4. Use View Modifiers for Interactions

**Don't:**
```swift
.scaleEffect(isPressed ? 0.98 : 1.0)
.animation(.easeInOut(duration: 0.1), value: isPressed)
```

**Do:**
```swift
.pressEffect(isPressed: $isPressed, scale: 0.98, duration: Spacing.Duration.fast)
```

## Component Structure Template

For a template on how to create new components using these utilities, see `COMPONENT_TEMPLATE.md`.

---

**Last Updated:** February 2026
**Maintained By:** MeetMemento Engineering Team
