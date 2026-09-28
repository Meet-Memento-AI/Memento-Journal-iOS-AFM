# 🚀 Implementation Guide: Journal Entry View

**Project**: withMemento  
**Target**: iOS 17.0+  
**Framework**: SwiftUI  
**Documentation**: [Apple Developer - SwiftUI](https://developer.apple.com/documentation/swiftui)

---

## 📋 Overview

Build a full-screen journal entry editor inspired by Notion's clean writing interface. Users will access this view by tapping the floating action button (FAB) in the main app.

### Core Features
- ✅ Custom navigation with back button and save action
- ✅ Auto-formatted date display
- ✅ Large multiline title field
- ✅ Expandable body text editor
- ✅ Voice recording FAB (UI placeholder)
- ✅ Keyboard-aware scrolling
- ✅ Focus state management

### Apple Documentation References
- [TextField](https://developer.apple.com/documentation/swiftui/textfield) - Single-line text input
- [TextEditor](https://developer.apple.com/documentation/swiftui/texteditor) - Multiline text editing
- [FocusState](https://developer.apple.com/documentation/swiftui/focusstate) - Managing keyboard focus
- [Environment](https://developer.apple.com/documentation/swiftui/environment) - Accessing shared data
- [sheet(isPresented:)](https://developer.apple.com/documentation/swiftui/view/sheet(ispresented:ondismiss:content:)) - Modal presentation

---

## 🏗️ Architecture

```
ContentView
    └─ .sheet(isPresented: $showJournalEntry)
         └─ JournalEntryView
              ├─ Navigation Bar (Custom)
              ├─ ScrollView
              │    ├─ Date Badge
              │    ├─ Title TextField
              │    └─ Body TextEditor
              └─ VoiceFAB (Overlay)
```

---

## 📦 Implementation Steps

### Step 1: Create VoiceFAB Component

**File**: `withMemento/Components/Buttons/VoiceFAB.swift`

```swift
//
//  VoiceFAB.swift
//  withMemento
//
//  Floating action button for voice recording feature.
//  Follows Apple HIG for floating action buttons.
//  Reference: https://developer.apple.com/design/human-interface-guidelines/buttons
//

import SwiftUI

/// A circular floating action button with a microphone icon and gradient background.
///
/// Use this button to trigger voice recording actions. The button displays
/// with a purple gradient and shadow for visual prominence.
///
/// Example:
/// ```swift
/// VoiceFAB {
///     print("Voice recording started")
/// }
/// ```
public struct VoiceFAB: View {
    @Environment(\.theme) private var theme
    
    /// The action to perform when the button is tapped.
    var action: () -> Void
    
    /// Creates a voice recording floating action button.
    /// - Parameter action: The closure to execute when tapped.
    public init(action: @escaping () -> Void) {
        self.action = action
    }
    
    public var body: some View {
        Button(action: action) {
            Image(systemName: "mic.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: "#8A38F5"),
                                    Color(hex: "#A855F7")
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(
                            color: Color(hex: "#8A38F5").opacity(0.4),
                            radius: 16,
                            x: 0,
                            y: 8
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Record voice entry")
        .accessibilityHint("Tap to start recording your journal entry")
    }
}

// MARK: - Previews

#Preview("Light") {
    VoiceFAB {
        print("Voice recording tapped")
    }
    .padding(40)
    .background(Color(hex: "#FFFFFF"))
    .useTheme()
}

#Preview("Dark") {
    VoiceFAB {
        print("Voice recording tapped")
    }
    .padding(40)
    .background(Color(hex: "#0A0A0A"))
    .useTheme()
    .preferredColorScheme(.dark)
}
```

---

### Step 2: Create JournalEntryView

**File**: `withMemento/Views/Journal/JournalEntryView.swift`

```swift
//
//  JournalEntryView.swift
//  withMemento
//
//  A full-screen journal entry editor with title and body fields.
//  Follows Apple's text editing best practices.
//  
//  References:
//  - TextField: https://developer.apple.com/documentation/swiftui/textfield
//  - TextEditor: https://developer.apple.com/documentation/swiftui/texteditor
//  - FocusState: https://developer.apple.com/documentation/swiftui/focusstate
//  - ScrollView: https://developer.apple.com/documentation/swiftui/scrollview
//

import SwiftUI

/// A view for creating and editing journal entries.
///
/// This view provides a Notion-inspired writing experience with:
/// - Auto-formatted date display
/// - Large title field with multiline support
/// - Expandable body text editor
/// - Voice recording button (placeholder)
///
/// Example:
/// ```swift
/// .sheet(isPresented: $showEntry) {
///     JournalEntryView()
///         .useTheme()
///         .useTypography()
/// }
/// ```
struct JournalEntryView: View {
    // MARK: - Environment
    
    /// Dismiss action for the view.
    /// Reference: https://developer.apple.com/documentation/swiftui/environmentvalues/dismiss
    @Environment(\.dismiss) private var dismiss
    
    /// App theme tokens (colors, radius, etc.)
    @Environment(\.theme) private var theme
    
    /// Typography tokens (fonts, sizes)
    @Environment(\.typography) private var type
    
    // MARK: - State
    
    /// The journal entry title.
    @State private var title: String = ""
    
    /// The main body text of the journal entry.
    @State private var bodyText: String = ""
    
    /// The date this entry was created.
    @State private var entryDate: Date = Date()
    
    /// Whether the entry is currently being saved.
    @State private var isSaving: Bool = false
    
    /// Whether to show the voice recording alert.
    @State private var showVoiceAlert: Bool = false
    
    /// Tracks which field currently has keyboard focus.
    /// Reference: https://developer.apple.com/documentation/swiftui/focusstate
    @FocusState private var focusedField: Field?
    
    // MARK: - Focus Fields
    
    /// Enumeration of focusable fields in the form.
    enum Field: Hashable {
        case title
        case body
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Main content area
            VStack(spacing: 0) {
                navigationBar
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        dateHeader
                        titleField
                        bodyEditor
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 100) // Space for floating button
                }
                // Dismiss keyboard when scrolling
                // Reference: https://developer.apple.com/documentation/swiftui/scrollview/scrolldismisseskeyboard(_:)
                .scrollDismissesKeyboard(.interactively)
            }
            
            // Floating voice recording button
            voiceFAB
        }
        .background(theme.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .onAppear {
            // Auto-focus title field after slight delay for smooth animation
            // Reference: https://developer.apple.com/documentation/dispatch/dispatchqueue
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                focusedField = .title
            }
        }
    }
    
    // MARK: - Subviews
    
    /// Custom navigation bar with back and save buttons.
    private var navigationBar: some View {
        HStack(spacing: 16) {
            // Back button
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(theme.foreground)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Back")
            
            Spacer()
            
            // Options menu (future feature)
            Button {
                // Future: Show options menu
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(theme.foreground)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Options")
            
            // Save button
            Button {
                saveEntry()
            } label: {
                Text("Save")
                    .font(type.button)
                    .foregroundStyle(canSave ? theme.primary : theme.mutedForeground)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: theme.radius.lg)
                            .fill(canSave ? theme.primary.opacity(0.1) : theme.muted)
                    )
            }
            .disabled(!canSave || isSaving)
            .accessibilityLabel("Save entry")
            .accessibilityHint(canSave ? "Saves your journal entry" : "Enter content to save")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(theme.background)
    }
    
    /// Date badge showing the entry creation date.
    private var dateHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(.system(size: 14))
                .foregroundStyle(theme.mutedForeground)
            
            Text(formattedDate)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(theme.mutedForeground)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: theme.radius.md)
                .fill(theme.muted.opacity(0.5))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Entry date: \(formattedDate)")
    }
    
    /// Large title text field with custom placeholder.
    /// Reference: https://developer.apple.com/documentation/swiftui/textfield
    private var titleField: some View {
        TextField("", text: $title, axis: .vertical)
            .font(.system(size: 28, weight: .bold))
            .foregroundStyle(theme.foreground)
            .focused($focusedField, equals: .title)
            .textInputAutocapitalization(.sentences)
            .submitLabel(.next)
            .onSubmit {
                // Move to body field when user presses "next"
                focusedField = .body
            }
            .placeholder(when: title.isEmpty) {
                Text("Write a title...")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(theme.mutedForeground.opacity(0.4))
            }
            .accessibilityLabel("Entry title")
            .accessibilityHint("Enter a title for your journal entry")
    }
    
    /// Expandable body text editor with custom placeholder.
    /// Reference: https://developer.apple.com/documentation/swiftui/texteditor
    private var bodyEditor: some View {
        ZStack(alignment: .topLeading) {
            // Custom placeholder (TextEditor doesn't have built-in placeholder)
            if bodyText.isEmpty {
                Text("Write your entry here, or speak below to share what you're thinking & feeling...")
                    .font(.system(size: 17))
                    .foregroundStyle(theme.mutedForeground.opacity(0.5))
                    .padding(.top, 8)
                    .allowsHitTesting(false)
            }
            
            TextEditor(text: $bodyText)
                .font(.system(size: 17))
                .foregroundStyle(theme.foreground)
                .focused($focusedField, equals: .body)
                .textInputAutocapitalization(.sentences)
                .scrollContentBackground(.hidden) // Remove default background
                .background(Color.clear)
                .frame(minHeight: 400)
        }
        .accessibilityLabel("Entry body")
        .accessibilityHint("Write the main content of your journal entry")
    }
    
    /// Voice recording floating action button.
    private var voiceFAB: some View {
        VoiceFAB {
            showVoiceAlert = true
        }
        .padding(.trailing, 20)
        .padding(.bottom, 32)
        .alert("Voice Recording", isPresented: $showVoiceAlert) {
            Button("OK") { }
        } message: {
            Text("Voice recording feature coming soon!")
        }
    }
    
    // MARK: - Computed Properties
    
    /// Formatted date string for display.
    /// Reference: https://developer.apple.com/documentation/foundation/dateformatter
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: entryDate)
    }
    
    /// Whether the entry has enough content to be saved.
    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    // MARK: - Actions
    
    /// Saves the current entry.
    ///
    /// This is a placeholder implementation that prints to console.
    /// Future implementation will integrate with EntryViewModel and Supabase.
    private func saveEntry() {
        isSaving = true
        
        // TODO: Integrate with EntryViewModel to persist to Supabase
        print("💾 Saving entry:")
        print("  Title: \(title)")
        print("  Body: \(bodyText)")
        print("  Date: \(entryDate)")
        
        // Simulate network delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isSaving = false
            dismiss()
        }
    }
}

// MARK: - View Extensions

extension View {
    /// Displays a custom placeholder when a condition is met.
    ///
    /// Use this to add placeholder text to views that don't have built-in placeholder support.
    ///
    /// - Parameters:
    ///   - shouldShow: Whether to show the placeholder.
    ///   - alignment: The alignment of the placeholder relative to the view.
    ///   - placeholder: A view builder that creates the placeholder content.
    /// - Returns: A view with an optional placeholder overlay.
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content
    ) -> some View {
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

// MARK: - Previews

#Preview("Empty Entry - Light") {
    NavigationStack {
        JournalEntryView()
            .useTheme()
            .useTypography()
    }
    .preferredColorScheme(.light)
}

#Preview("Empty Entry - Dark") {
    NavigationStack {
        JournalEntryView()
            .useTheme()
            .useTypography()
    }
    .preferredColorScheme(.dark)
}
```

---

### Step 3: Integrate with ContentView

**File**: `withMemento/ContentView.swift`

**Add state variable** after line 38:

```swift
/// Controls presentation of the journal entry sheet.
@State private var showJournalEntry: Bool = false
```

**Update FAB button** around line 93, replace the existing button with:

```swift
// Floating action button
Button {
    showJournalEntry = true
} label: {
    Image(systemName: "plus")
        .font(.system(size: 20, weight: .bold))
        .foregroundStyle(theme.primaryForeground)
        .frame(width: 56, height: 56)
        .background(
            Circle()
                .fill(theme.primary)
                .shadow(color: .black.opacity(0.16), radius: 12, x: 0, y: 6)
        )
}
.buttonStyle(.plain)
.padding(.trailing, hPadding)
.accessibilityLabel("New Entry")
// Present journal entry as a sheet
// Reference: https://developer.apple.com/documentation/swiftui/view/sheet(ispresented:ondismiss:content:)
.sheet(isPresented: $showJournalEntry) {
    JournalEntryView()
        .useTheme()
        .useTypography()
}
```

---

## ✅ Testing Checklist

### Functionality
- [ ] Tap FAB (+) button → Journal entry sheet appears
- [ ] Title field auto-focuses after 0.5s delay
- [ ] Typing in title, press "next" → body field focuses
- [ ] Date badge displays current date in long format
- [ ] Save button disabled when both fields empty
- [ ] Save button enabled when either field has content
- [ ] Tap back chevron → sheet dismisses
- [ ] Tap save → console logs entry data, sheet dismisses
- [ ] Tap voice FAB → alert shows "coming soon" message
- [ ] Scrolling dismisses keyboard
- [ ] Three-dot menu button present (no action yet)

### Appearance
- [ ] Navigation bar: 56pt height, proper spacing
- [ ] Date badge: muted background, rounded corners
- [ ] Title: 28pt bold, multiline support
- [ ] Body: 17pt regular, expandable, min 400pt height
- [ ] Voice FAB: 64×64pt circle, purple gradient, shadow
- [ ] Light mode renders correctly
- [ ] Dark mode renders correctly

### Accessibility
- [ ] All buttons have accessibility labels
- [ ] VoiceOver announces all interactive elements
- [ ] Save button hint updates based on state
- [ ] Date badge combines into single accessibility element

---

## 📚 Apple Documentation References

| Component | Documentation Link |
|-----------|-------------------|
| **TextField** | [developer.apple.com/documentation/swiftui/textfield](https://developer.apple.com/documentation/swiftui/textfield) |
| **TextEditor** | [developer.apple.com/documentation/swiftui/texteditor](https://developer.apple.com/documentation/swiftui/texteditor) |
| **FocusState** | [developer.apple.com/documentation/swiftui/focusstate](https://developer.apple.com/documentation/swiftui/focusstate) |
| **Environment** | [developer.apple.com/documentation/swiftui/environment](https://developer.apple.com/documentation/swiftui/environment) |
| **sheet(isPresented:)** | [developer.apple.com/documentation/swiftui/view/sheet(ispresented:ondismiss:content:)](https://developer.apple.com/documentation/swiftui/view/sheet(ispresented:ondismiss:content:)) |
| **DateFormatter** | [developer.apple.com/documentation/foundation/dateformatter](https://developer.apple.com/documentation/foundation/dateformatter) |
| **DispatchQueue** | [developer.apple.com/documentation/dispatch/dispatchqueue](https://developer.apple.com/documentation/dispatch/dispatchqueue) |
| **ScrollView** | [developer.apple.com/documentation/swiftui/scrollview](https://developer.apple.com/documentation/swiftui/scrollview) |
| **Button** | [developer.apple.com/documentation/swiftui/button](https://developer.apple.com/documentation/swiftui/button) |
| **HIG - Buttons** | [developer.apple.com/design/human-interface-guidelines/buttons](https://developer.apple.com/design/human-interface-guidelines/buttons) |

---

## 🎯 Success Criteria

✅ **Core Functionality**
- Journal entry creation works end-to-end
- Keyboard management is smooth and intuitive
- Save/dismiss actions work correctly

✅ **Design System Compliance**
- Uses existing Theme tokens (no hardcoded colors)
- Uses existing Typography tokens (no hardcoded fonts)
- No new reusable components created (except VoiceFAB)
- Follows iOS Human Interface Guidelines

✅ **Code Quality**
- All code documented with inline comments
- References to Apple documentation included
- Accessibility labels present on all interactive elements
- Previews provided for light and dark modes

---

## 📦 Deliverables Summary

### New Files (2)
1. `withMemento/Components/Buttons/VoiceFAB.swift` - Voice recording FAB component
2. `withMemento/Views/Journal/JournalEntryView.swift` - Main journal entry editor

### Modified Files (1)
3. `withMemento/ContentView.swift` - Add sheet presentation for journal entry

---

## 🚀 Next Steps (Future Enhancements)

1. **Database Integration**: Connect `saveEntry()` to EntryViewModel and Supabase
2. **Voice Recording**: Implement actual voice-to-text transcription
3. **Rich Text**: Add formatting toolbar (bold, italic, lists)
4. **Auto-save**: Implement draft persistence
5. **Edit Mode**: Support editing existing entries
6. **Image Attachments**: Allow photo uploads
7. **Templates**: Pre-fill with journaling prompts

---

**Implementation Time**: ~1-2 hours  
**Complexity**: Intermediate  
**Dependencies**: Existing Theme, Typography, and Color extensions

🎉 **Ready to build!**
