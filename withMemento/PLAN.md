# Fix Journal Empty State Flash on Load

## Problem
When returning to the app after unlock, users see a brief flash (~1 second) of the "No journal entries yet" empty state before their actual entries appear.

## Root Cause

The issue is a **race condition** in the loading state management:

1. `EntryViewModel` initializes with:
   - `entries: [Entry] = []` (empty)
   - `isLoading = false`

2. When `JournalView.onAppear` fires, it calls `loadEntriesIfNeeded()`

3. **The gap**: Before `loadEntries()` sets `isLoading = true`, there's a brief render cycle where:
   - `entries.isEmpty = true`
   - `isLoading = false`
   - This triggers the empty state condition at `YourEntriesView.swift:47`

4. The conditional logic in `YourEntriesView`:
   ```swift
   if entryViewModel.isLoading && entryViewModel.entries.isEmpty {
       loadingState  // Only shows if BOTH conditions true
   } else if entryViewModel.entries.isEmpty {
       emptyState    // Shows when entries empty but NOT loading
   }
   ```

The empty state should **only** appear after we've confirmed there are no entries (i.e., after the first load completes).

---

## Solution

Introduce a `hasCompletedInitialLoad` flag to distinguish between:
- **Not yet loaded**: Show loading state (spinner)
- **Loaded with entries**: Show entries
- **Loaded with no entries**: Show empty state

### Fix 1: Add `hasCompletedInitialLoad` to EntryViewModel

```swift
@Published var hasCompletedInitialLoad = false
```

Reset it when needed (e.g., on sign out) and set it to `true` after `loadEntries()` completes.

### Fix 2: Update `loadEntries()` to Set Flag

```swift
func loadEntries() async {
    isLoading = true
    errorMessage = nil

    // ... existing fetch logic ...

    isLoading = false
    hasCompletedInitialLoad = true  // Mark initial load complete
}
```

### Fix 3: Update YourEntriesView Conditional Logic

Change the conditional to only show empty state after initial load:

```swift
var body: some View {
    Group {
        if !entryViewModel.hasCompletedInitialLoad {
            // Initial load in progress - always show loading
            loadingState
        } else if entryViewModel.isLoading && entryViewModel.entries.isEmpty {
            // Refreshing with no cached entries
            loadingState
        } else if let errorMessage = entryViewModel.errorMessage, entryViewModel.entries.isEmpty {
            // Error with no cached entries
            errorState(message: errorMessage)
        } else if entryViewModel.entries.isEmpty {
            // Confirmed empty after load
            emptyState
        } else {
            // Has entries
            entriesList
        }
    }
}
```

---

## Files to Modify

| File | Changes |
|------|---------|
| `ViewModels/EntryViewModel.swift` | Add `hasCompletedInitialLoad` property, set to `true` after load |
| `Views/Journal/YourEntriesView.swift` | Update conditional to check `hasCompletedInitialLoad` first |

---

## Verification

1. **Fresh app launch**: Should show loading spinner, then entries (no empty state flash)
2. **Return from lock screen**: Should show loading briefly, then entries smoothly
3. **User with no entries**: Should show loading, then empty state (correct behavior)
4. **Pull to refresh**: Should work as before (show entries while refreshing in background)

---

## Alternative Considered

Could also solve by setting `isLoading = true` in `init()` of EntryViewModel, but this is less explicit and could cause issues if entries are pre-populated (e.g., from cache).

The `hasCompletedInitialLoad` approach is cleaner because it explicitly tracks the load lifecycle.
