# Fonts Directory

This directory contains custom font files for the MeetMemento app.

## Installed Fonts

### Figtree (Default UI — h3–h6, body, caption) ✅
- **Figtree-Regular.ttf** - Captions, micro
- **Figtree-Medium.ttf** - Body, labels, emphasized caption
- **Figtree-SemiBold.ttf** - Emphasized body
- **Figtree-Bold.ttf** - Section headings (h3–h5), h6, bold body, buttons
- **Figtree-VariableFont_wght.ttf** - Variable source (SIL OFL 1.1)

Default typography uses Figtree for UI copy. See `Typography.swift`.

### Lora (Display + onboarding) ✅
- **Lora-Regular.ttf** - Body text on onboarding
- **Lora-Medium.ttf** - Emphasized body on onboarding
- **Lora-SemiBold.ttf** - Onboarding h3–h5
- **Lora-Bold.ttf** - h1/h2 display face app-wide; bold body on onboarding

Use `Typography.onboarding` (e.g. on WelcomeView and onboarding flow) to get Lora throughout.

### Manrope (legacy)
Manrope files remain in the bundle so leftover call sites do not break. Default UI type is Figtree.

### Sora (optional / legacy)
- Sora font files may remain in the bundle for reference but are not used by default typography.

## Installation Steps

✅ **Font files are in place!** Add them to Xcode and ensure Info.plist UIAppFonts includes:
- Figtree-Regular, Figtree-Medium, Figtree-SemiBold, Figtree-Bold, Figtree-VariableFont_wght
- Lora-Regular, Lora-Medium, Lora-SemiBold, Lora-Bold
- Manrope-Regular, Manrope-Medium, Manrope-Bold (legacy)

## Font PostScript Names (Typography.swift)

**Default:**
- `Lora-Bold` (h1/h2 display)
- `Figtree-Bold` (h3–h5)
- `Figtree-Regular`, `Figtree-Medium`, `Figtree-SemiBold`, `Figtree-Bold` (h6, body, caption, micro)

**Onboarding (Lora):**
- `Lora-Bold` (h1/h2)
- `Lora-SemiBold` (h3–h5)
- `Lora-Regular`, `Lora-Medium`, `Lora-Bold` (body, caption, micro, h6)

## Testing

After adding fonts, test with:
```swift
// Check available fonts
for family in UIFont.familyNames.sorted() {
    print("Family: \(family)")
    for name in UIFont.fontNames(forFamilyName: family) {
        print("  Font: \(name)")
    }
}
```
