# Preview Provider Fix Guide

## Issue
Xcode Previews were not working after project restructuring.

## Root Causes & Fixes

### 1. ✅ Build Phase Issues (FIXED)
- `JournalCard.swift` and `PermissionsView.swift` were in Resources phase instead of Sources
- Removed them from exception sets in `project.pbxproj`

### 2. ✅ Preview Format Update (FIXED)
- Converted old `PreviewProvider` structs to modern `#Preview` macros
- Updated `ContentView` and `WelcomeView` to use new format

### 3. ✅ Environment Objects (FIXED)
All views requiring `@EnvironmentObject var authViewModel: AuthViewModel` now have it in previews:
- `ContentView.swift`
- `SignInView.swift`
- `SignUpView.swift`
- `SettingsView.swift`

### 4. Preview Cache Issues

If previews still don't work in Xcode:

## Troubleshooting Steps

### Step 1: Clean Build in Xcode
1. Open Xcode
2. **Product** → **Clean Build Folder** (⌘⇧K)
3. Wait for completion
4. **Product** → **Build** (⌘B)

### Step 2: Reset Xcode Preview Cache
In Xcode, with your project open:
1. **Editor** → **Canvas** (turn it on if off)
2. Right-click on any preview
3. Select **"Refresh Canvas"**

### Step 3: Restart Xcode
1. Quit Xcode completely (⌘Q)
2. Reopen project
3. Try previews again

### Step 4: Delete Derived Data Manually
If Xcode is closed:
```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/withMemento-*
```

Then reopen Xcode and build.

### Step 5: Check Specific Preview
Open a specific file and look for these common issues:

#### Missing Environment Objects
```swift
// ❌ Won't work - missing AuthViewModel
#Preview {
    ContentView()
}

// ✅ Works - has AuthViewModel
#Preview {
    ContentView()
        .environmentObject(AuthViewModel())
}
```

#### Missing Theme/Typography
```swift
// ❌ Won't work - missing custom environment
#Preview {
    WelcomeView()
}

// ✅ Works - has theme and typography
#Preview {
    WelcomeView()
        .useTheme()
        .useTypography()
}
```

## Current Preview Status

All views should now have working previews:

### ✅ Views with Previews
- `ContentView` - Has AuthViewModel
- `WelcomeView` - Has theme/typography
- `SignInView` - Has AuthViewModel + theme/typography
- `SignUpView` - Has AuthViewModel + theme/typography
- `SettingsView` - Has AuthViewModel
- `JournalCard` - Self-contained with #Preview
- `AppleSignInButton` - Self-contained
- `GoogleSignInButton` - Self-contained

### 📝 Preview Format
Using modern `#Preview` macro (iOS 17+):
```swift
#Preview("Display Name") {
    YourView()
        .environmentObject(AuthViewModel())
        .useTheme()
        .useTypography()
        .preferredColorScheme(.light)
}
```

## If Previews Still Don't Work

### Check Console for Errors
1. Open preview
2. Check Xcode's console (bottom panel)
3. Look for specific error messages

### Common Errors:

**"Failed to build"**
- Run full build first (⌘B)
- Check for compilation errors

**"Failed to launch preview"**
- Restart Xcode
- Clean derived data

**"Missing environment object"**
- Add `.environmentObject(AuthViewModel())` to preview

**"Cannot find type in scope"**
- Ensure all imports are correct
- Check file is in correct target

### Verify Simulator
Make sure a simulator is selected:
1. Top bar → Select any iOS simulator
2. Try preview again

## Success Indicators

When previews work, you should see:
- ✅ Live preview in canvas
- ✅ Ability to switch between light/dark mode
- ✅ Ability to interact with preview
- ✅ Multiple preview variants visible

## Prevention

To keep previews working:
- Always include required environment objects
- Use modern `#Preview` format
- Don't put Swift files in Resources phase
- Keep build clean (clean occasionally)

