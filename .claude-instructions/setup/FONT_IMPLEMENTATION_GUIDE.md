# Font Implementation Guide

## Overview
This guide walks you through implementing the Recoleta and Manrope fonts in the withMemento app.

## Current Status
✅ Typography system implemented  
✅ Info.plist configured  
✅ Font directory structure created  
⏳ Font files need to be added  

## Step 1: Add Font Files

### Download Fonts
1. **Recoleta Black**: Download from the provided file
2. **Manrope**: Download from [Google Fonts](https://fonts.google.com/specimen/Manrope)

### File Structure
Place font files in: `/withMemento/Resources/Fonts/`
```
withMemento/
└── Resources/
    └── Fonts/
        ├── Recoleta-Black.ttf (or .otf)
        ├── Manrope-Regular.ttf (or .otf)
        ├── Manrope-Medium.ttf (or .otf)
        └── README.md
```

## Step 2: Add to Xcode Project

### In Xcode:
1. **Drag & Drop**: Drag font files from Finder into Xcode
2. **Target Membership**: Ensure fonts are added to "withMemento" target
3. **Bundle Resources**: Verify fonts appear in Build Phases > Copy Bundle Resources

### Verification:
- Fonts should appear in Xcode project navigator
- Files should be listed in target membership
- No red file references (missing files)

## Step 3: Verify Info.plist

The Info.plist is already configured with:
```xml
<key>UIAppFonts</key>
<array>
    <string>Recoleta-Black.ttf</string>
    <string>Manrope-Regular.ttf</string>
    <string>Manrope-Medium.ttf</string>
</array>
```

**Note**: If your font files have different extensions (.otf vs .ttf), update the Info.plist accordingly.

## Step 4: Test Font Installation

### Using FontDebugger
1. Add FontDebugger to a view temporarily:
```swift
struct TestView: View {
    var body: some View {
        FontDebugger.createFontPreviewView()
    }
}
```

2. Run the app and check console output
3. Look for your fonts in the debug output

### Manual Testing
```swift
// Test individual fonts
let recoletaFont = UIFont(name: "Recoleta-Black", size: 24)
let manropeFont = UIFont(name: "Manrope-Regular", size: 16)

print("Recoleta available: \(recoletaFont != nil)")
print("Manrope available: \(manropeFont != nil)")
```

## Step 5: Update Typography.swift (if needed)

If font names don't match, update the font names in Typography.swift:

```swift
// Current expected names
private let headingFontName = "Recoleta-Black"
private let bodyFontName = "Manrope-Regular"
private let bodyMediumFontName = "Manrope-Medium"
```

**Common variations**:
- `Recoleta-Black` vs `RecoletaBlack`
- `Manrope-Regular` vs `ManropeRegular`
- `Manrope-Medium` vs `ManropeMedium`

## Step 6: Build and Test

1. **Clean Build**: Product > Clean Build Folder
2. **Build**: Product > Build
3. **Run**: Test on simulator/device
4. **Verify**: Check that custom fonts are rendering

## Troubleshooting

### Fonts Not Loading
1. **Check file names**: Exact match in Info.plist and file system
2. **Target membership**: Ensure fonts are in app target
3. **File format**: iOS supports .ttf and .otf
4. **Case sensitivity**: Font names are case-sensitive

### Font Names Don't Match
1. Use FontDebugger to see actual PostScript names
2. Update Typography.swift with correct names
3. Rebuild project

### Build Errors
1. **Missing files**: Check file references in Xcode
2. **Info.plist syntax**: Validate XML format
3. **Target membership**: Ensure fonts are in correct target

## Expected Result

Once implemented, you should see:
- **Headings**: Recoleta Black font (h1, h2, h3, h4)
- **Body text**: Manrope Regular/Medium font
- **Fallback**: System fonts if custom fonts fail to load
- **Dynamic Type**: Support for accessibility scaling

## File Sizes
- Recoleta-Black: ~50-100KB
- Manrope-Regular: ~200-300KB  
- Manrope-Medium: ~200-300KB

Total additional bundle size: ~500-700KB

## Next Steps After Implementation

1. **Remove FontDebugger**: Clean up debug code
2. **Test thoroughly**: All screens, light/dark modes
3. **Accessibility**: Test with Dynamic Type
4. **Performance**: Monitor app launch time
5. **Commit changes**: Add font files to version control
