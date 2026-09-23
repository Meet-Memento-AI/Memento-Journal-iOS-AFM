# 📝 Journal System Implementation Plan

**Date**: December 15, 2024  
**Focus**: UI-First Approach → Database Integration Later  
**Status**: 🎯 Ready to implement

---

## 🎯 Goals

1. **Display journal entries** in JournalView as vertically stacked JournalCards
2. **Click JournalCard** → Navigate to JournalPageView (read/edit mode)
3. **Three-dot menu** → Delete entry option
4. **Save entries** to Supabase (Phase 2)
5. **Use existing components** + Theme/Typography tokens

---

## 📊 Architecture Overview

```
User Flow:
1. Create Entry (AddEntryView) → Save
2. Entry appears as JournalCard in JournalView
3. Tap JournalCard → JournalPageView (read/edit)
4. Tap three-dot → Dropdown → Delete

Data Flow:
AddEntryView → EntryViewModel → Supabase
                     ↓
                JournalView (displays cards)
                     ↓
                JournalPageView (view/edit)
```

---

## 📦 Phase 1: UI Implementation (Current Focus)

### Step 1: Update Entry Model ✅ NEEDED
**File**: `withMemento/Models/Entry.swift`

**Current**:
```swift
struct Entry: Identifiable, Codable {
    let id: UUID
    // Add your Entry model properties here
}
```

**New**:
```swift
struct Entry: Identifiable, Codable {
    let id: UUID
    var title: String
    var text: String
    var mood: String?
    var createdAt: Date
    var updatedAt: Date
    
    // Computed property for excerpt
    var excerpt: String {
        let maxLength = 120
        if text.count > maxLength {
            return String(text.prefix(maxLength)) + "..."
        }
        return text
    }
}
```

---

### Step 2: Create EntryViewModel ✅ NEEDED
**File**: `withMemento/ViewModels/EntryViewModel.swift`

**Purpose**: Manage entry state and operations

**Features**:
- `@Published var entries: [Entry] = []`
- `func createEntry(_ entry: Entry)`
- `func updateEntry(_ entry: Entry)`
- `func deleteEntry(id: UUID)`
- `func loadEntries()` (mock data for now)

---

### Step 3: Update JournalView ✅ NEEDED
**File**: `withMemento/Views/Journal/JournalView.swift`

**Changes**:
- Remove empty state (or show conditionally)
- Add `ScrollView` with `LazyVStack` of JournalCards
- Connect to EntryViewModel
- Navigate to JournalPageView on card tap
- Show delete confirmation on three-dot tap

---

### Step 4: Create JournalPageView ✅ NEEDED
**File**: `withMemento/Views/Journal/JournalPageView.swift`

**Design**: Similar to AddEntryView but for viewing/editing

**Features**:
- Pre-filled title and text fields
- Mood selector (pre-selected if exists)
- Edit mode toggle
- Save changes
- Delete button in toolbar

---

### Step 5: Create Delete Confirmation Component ❓ NEW COMPONENT?

**Question**: Do you want a reusable dropdown menu component, or use SwiftUI's built-in `.confirmationDialog`?

**Option A**: Use native `.confirmationDialog` (Recommended)
```swift
.confirmationDialog("Delete Entry?", isPresented: $showDeleteConfirmation) {
    Button("Delete", role: .destructive) { deleteEntry() }
    Button("Cancel", role: .cancel) { }
}
```

**Option B**: Create custom `DropdownMenu` component
- More control over appearance
- Matches design system precisely
- More code to maintain

**My Recommendation**: Use Option A (native) for speed and reliability.

---

## 🔧 Detailed Implementation

### 1. Entry Model (Complete Code)

```swift
//
//  Entry.swift
//  withMemento
//

import Foundation

/// Represents a journal entry with title, text, mood, and timestamps.
struct Entry: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var text: String
    var mood: String?
    var createdAt: Date
    var updatedAt: Date
    
    /// Creates a new entry with default values.
    init(
        id: UUID = UUID(),
        title: String = "",
        text: String,
        mood: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.text = text
        self.mood = mood
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    /// Short excerpt of the entry text for display in cards.
    var excerpt: String {
        let maxLength = 120
        if text.count > maxLength {
            return String(text.prefix(maxLength)) + "..."
        }
        return text
    }
    
    /// Display title, or "Untitled" if empty.
    var displayTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Untitled"
            : title
    }
}

// MARK: - Sample Data

extension Entry {
    static let sampleEntries: [Entry] = [
        Entry(
            title: "Morning Reflection",
            text: "Started the day with a 5km run. Feeling grateful for the clear weather and my health. Need to remember to drink more water throughout the day.",
            mood: "😊",
            createdAt: Date().addingTimeInterval(-86400), // 1 day ago
            updatedAt: Date().addingTimeInterval(-86400)
        ),
        Entry(
            title: "Project Planning",
            text: "Working on the withMemento journal feature. The UI is coming together nicely. Need to focus on database integration next week.",
            mood: "😐",
            createdAt: Date().addingTimeInterval(-3600), // 1 hour ago
            updatedAt: Date().addingTimeInterval(-3600)
        ),
        Entry(
            title: "",
            text: "Quick note: Remember to call mom this weekend.",
            mood: "🤍",
            createdAt: Date().addingTimeInterval(-300), // 5 minutes ago
            updatedAt: Date().addingTimeInterval(-300)
        )
    ]
}
```

---

### 2. EntryViewModel (Complete Code)

```swift
//
//  EntryViewModel.swift
//  withMemento
//

import Foundation
import SwiftUI

/// Manages journal entries and provides CRUD operations.
@MainActor
class EntryViewModel: ObservableObject {
    @Published var entries: [Entry] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    init() {
        loadMockEntries()
    }
    
    // MARK: - CRUD Operations
    
    /// Creates a new entry and adds it to the list.
    func createEntry(title: String = "", text: String, mood: String?) {
        let entry = Entry(
            title: title,
            text: text,
            mood: mood
        )
        entries.insert(entry, at: 0) // Add to beginning
        
        // TODO: Save to Supabase
        print("✅ Created entry: \(entry.id)")
    }
    
    /// Updates an existing entry.
    func updateEntry(_ updatedEntry: Entry) {
        guard let index = entries.firstIndex(where: { $0.id == updatedEntry.id }) else {
            errorMessage = "Entry not found"
            return
        }
        
        var entry = updatedEntry
        entry.updatedAt = Date()
        entries[index] = entry
        
        // TODO: Update in Supabase
        print("✅ Updated entry: \(entry.id)")
    }
    
    /// Deletes an entry by ID.
    func deleteEntry(id: UUID) {
        entries.removeAll(where: { $0.id == id })
        
        // TODO: Delete from Supabase
        print("✅ Deleted entry: \(id)")
    }
    
    /// Loads entries from storage.
    func loadEntries() async {
        isLoading = true
        
        // TODO: Load from Supabase
        // For now, use mock data
        await Task.sleep(1_000_000_000) // 1 second delay
        
        isLoading = false
    }
    
    // MARK: - Mock Data
    
    private func loadMockEntries() {
        entries = Entry.sampleEntries
    }
}
```

---

### 3. Updated JournalView (Complete Code)

```swift
//
//  JournalView.swift
//  withMemento
//

import SwiftUI

public struct JournalView: View {
    @State private var topSelection: JournalTopTab = .yourEntries
    @StateObject private var entryViewModel = EntryViewModel()
    @State private var selectedEntry: Entry?
    @State private var showDeleteConfirmation: Bool = false
    @State private var entryToDelete: Entry?
    
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Top navigation with tabs
            TopNav(variant: .tabs, selection: $topSelection)
                .useTheme()
                .useTypography()
                .padding(.top, 12)
            
            // Content area
            if entryViewModel.entries.isEmpty {
                emptyState
            } else {
                entriesList
            }
        }
        .background(theme.background.ignoresSafeArea())
        .sheet(item: $selectedEntry) { entry in
            JournalPageView(entry: entry, entryViewModel: entryViewModel)
                .useTheme()
                .useTypography()
        }
        .confirmationDialog(
            "Delete this entry?",
            isPresented: $showDeleteConfirmation,
            presenting: entryToDelete
        ) { entry in
            Button("Delete", role: .destructive) {
                entryViewModel.deleteEntry(id: entry.id)
            }
            Button("Cancel", role: .cancel) { }
        } message: { entry in
            Text("This action cannot be undone.")
        }
    }
    
    // MARK: - Subviews
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            
            Image(systemName: "book.closed.fill")
                .font(.system(size: 36))
                .foregroundStyle(theme.mutedForeground)
            
            Text("No journal entries yet")
                .font(type.h3)
                .fontWeight(.semibold)
                .foregroundStyle(theme.foreground)
            
            Text("Start writing your first entry to see it here.")
                .font(type.body)
                .foregroundStyle(theme.mutedForeground)
            
            Spacer()
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
    }
    
    private var entriesList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(filteredEntries) { entry in
                    JournalCard(
                        title: entry.displayTitle,
                        excerpt: entry.excerpt,
                        date: entry.createdAt,
                        onTap: {
                            selectedEntry = entry
                        },
                        onMoreTapped: {
                            entryToDelete = entry
                            showDeleteConfirmation = true
                        }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
    
    private var filteredEntries: [Entry] {
        // TODO: Filter by topSelection (Your Entries vs Follow-ups)
        entryViewModel.entries
    }
}

// MARK: - Previews

#Preview("Journal • Empty") {
    struct PreviewWrapper: View {
        @StateObject var viewModel = EntryViewModel()
        var body: some View {
            JournalView()
                .onAppear {
                    viewModel.entries = []
                }
        }
    }
    return PreviewWrapper()
}

#Preview("Journal • With Entries") {
    JournalView()
}
```

---

### 4. JournalPageView (Complete Code)

```swift
//
//  JournalPageView.swift
//  withMemento
//

import SwiftUI

struct JournalPageView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    
    @ObservedObject var entryViewModel: EntryViewModel
    
    let entry: Entry
    @State private var editedTitle: String
    @State private var editedText: String
    @State private var editedMood: String
    @State private var isEditing: Bool = false
    @State private var isSaving: Bool = false
    @FocusState private var focusedField: Field?
    
    enum Field: Hashable {
        case title
        case text
    }
    
    init(entry: Entry, entryViewModel: EntryViewModel) {
        self.entry = entry
        self.entryViewModel = entryViewModel
        _editedTitle = State(initialValue: entry.title)
        _editedText = State(initialValue: entry.text)
        _editedMood = State(initialValue: entry.mood ?? "")
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Mood selector
                    MoodSelector(selected: $editedMood)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .disabled(!isEditing)
                    
                    // Title field
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(theme.inputBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(theme.border, lineWidth: 1)
                            )
                        
                        TextField("Title", text: $editedTitle, axis: .vertical)
                            .font(.title3.bold())
                            .padding(12)
                            .background(.clear)
                            .focused($focusedField, equals: .title)
                            .disabled(!isEditing)
                        
                        if editedTitle.isEmpty && isEditing {
                            Text("Add a title...")
                                .font(.title3.bold())
                                .foregroundStyle(theme.mutedForeground)
                                .padding(.top, 18)
                                .padding(.leading, 18)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(minHeight: 50)
                    .padding(.horizontal, 16)
                    
                    // Text editor
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(theme.inputBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(theme.border, lineWidth: 1)
                            )
                        
                        TextEditor(text: $editedText)
                            .padding(12)
                            .frame(minHeight: 200)
                            .background(.clear)
                            .focused($focusedField, equals: .text)
                            .scrollContentBackground(.hidden)
                            .disabled(!isEditing)
                        
                        if editedText.isEmpty && isEditing {
                            Text("Write your thoughts...")
                                .foregroundStyle(theme.mutedForeground)
                                .padding(.top, 18)
                                .padding(.leading, 18)
                                .allowsHitTesting(false)
                        }
                    }
                    .padding(.horizontal, 16)
                    
                    // Metadata
                    metadataSection
                    
                    Spacer(minLength: 20)
                }
            }
            .background(theme.background.ignoresSafeArea())
            .navigationTitle(isEditing ? "Edit Entry" : "Journal Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isEditing ? "Cancel" : "Done") {
                        if isEditing {
                            // Revert changes
                            editedTitle = entry.title
                            editedText = entry.text
                            editedMood = entry.mood ?? ""
                            isEditing = false
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if isEditing {
                        Button {
                            saveChanges()
                        } label: {
                            if isSaving {
                                ProgressView().tint(theme.primary)
                            } else {
                                Text("Save").fontWeight(.medium)
                            }
                        }
                        .disabled(isSaving || editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    } else {
                        Button("Edit") {
                            isEditing = true
                            focusedField = .title
                        }
                    }
                }
            }
        }
    }
    
    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .imageScale(.small)
                    .foregroundStyle(theme.mutedForeground)
                Text("Created: \(entry.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(type.body)
                    .foregroundStyle(theme.mutedForeground)
            }
            
            HStack(spacing: 8) {
                Image(systemName: "pencil")
                    .imageScale(.small)
                    .foregroundStyle(theme.mutedForeground)
                Text("Updated: \(entry.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(type.body)
                    .foregroundStyle(theme.mutedForeground)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    private func saveChanges() {
        isSaving = true
        
        var updatedEntry = entry
        updatedEntry.title = editedTitle
        updatedEntry.text = editedText
        updatedEntry.mood = editedMood.isEmpty ? nil : editedMood
        
        entryViewModel.updateEntry(updatedEntry)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isSaving = false
            isEditing = false
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}

// MARK: - Previews

#Preview("View Mode") {
    JournalPageView(
        entry: Entry.sampleEntries[0],
        entryViewModel: EntryViewModel()
    )
    .useTheme()
    .useTypography()
}
```

---

### 5. Update ContentView to Pass EntryViewModel

**File**: `withMemento/ContentView.swift`

**Changes**:
```swift
// Add @StateObject
@StateObject private var entryViewModel = EntryViewModel()

// Update AddEntryView sheet
.sheet(isPresented: $showAddEntry) {
    AddEntryView(
        onSave: { text, mood in
            // Use entryViewModel to save
            entryViewModel.createEntry(title: "", text: text, mood: mood)
            showAddEntry = false
        },
        onCancel: { showAddEntry = false }
    )
    .useTheme()
    .useTypography()
}

// Pass entryViewModel to JournalView
case .journal:
    JournalView()
        .environmentObject(entryViewModel)
```

---

## ✅ Implementation Checklist

### Phase 1: Models & ViewModels
- [ ] Update `Entry.swift` with full model
- [ ] Create `EntryViewModel.swift`
- [ ] Add sample data for testing

### Phase 2: Views
- [ ] Update `JournalView.swift` to display cards
- [ ] Create `JournalPageView.swift` for viewing/editing
- [ ] Wire up delete confirmation dialog

### Phase 3: Integration
- [ ] Update `ContentView.swift` to create EntryViewModel
- [ ] Pass EntryViewModel to JournalView
- [ ] Connect AddEntryView to EntryViewModel
- [ ] Test full flow: Create → Display → View → Edit → Delete

### Phase 4: Polish (UI Complete)
- [ ] Test all transitions
- [ ] Verify theme/typography usage
- [ ] Test light/dark modes
- [ ] Accessibility review
- [ ] Preview providers for all views

---

## 🚀 Phase 2: Database Integration (Later)

### Supabase Setup
1. Update `Entry` model with Supabase fields
2. Create database table schema
3. Update `EntryViewModel` CRUD operations
4. Add error handling
5. Add loading states
6. Implement optimistic updates

---

## 📚 Components Used

### Existing (No Changes Needed)
- ✅ `JournalCard.swift` - Already has `onTap` and `onMoreTapped`
- ✅ `MoodSelector` - From AddEntryView.swift
- ✅ Theme tokens - Colors, radius, spacing
- ✅ Typography tokens - Fonts

### New Components Created
- ✅ `EntryViewModel.swift` - State management
- ✅ `JournalPageView.swift` - View/edit entries

### Native SwiftUI Used
- ✅ `.confirmationDialog` - Delete confirmation
- ✅ `.sheet` - Modal presentations
- ✅ `LazyVStack` - Efficient list rendering

---

## ❓ Questions for You

1. **Delete Menu**: Use native `.confirmationDialog` (recommended) or create custom dropdown?
2. **Edit Mode**: Auto-enter edit mode when opening JournalPageView, or view-only first?
3. **Title Field**: Required or optional? (Currently optional with "Untitled" fallback)

---

**Status**: 📝 Implementation plan complete  
**Next**: Await your approval to proceed with implementation

🎉 **Ready to build!**
