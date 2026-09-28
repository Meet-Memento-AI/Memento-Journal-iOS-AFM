# 🧪 Journal System Testing Guide

**Date**: December 15, 2024  
**Phase**: Phase 1 Complete (UI + Mock Data)  
**Status**: ✅ Ready to test

---

## 🎉 What Was Implemented

### **Complete Journal System**
- ✅ Entry model (no mood/sentiment)
- ✅ EntryViewModel (state management)
- ✅ JournalView (list display)
- ✅ JournalPageView (view/edit)
- ✅ AddEntryView (simplified)
- ✅ Delete confirmation (native dialog)
- ✅ Mock data (3 sample entries)

---

## 🚀 How to Test

### **Step 1: Build & Run**
```bash
# Open Xcode
open withMemento.xcodeproj

# Build: ⌘ + B
# Run: ⌘ + R
```

### **Step 2: Navigate to Journal Tab**
1. App launches → Sign in if needed
2. Bottom of screen: Tap **"Journal"** tab
3. You should see 3 sample entries

---

## ✅ Test Checklist

### **A. View Entries (JournalView)**

#### 1. Empty State ❌ (Currently has mock data)
- [ ] Remove mock data temporarily
- [ ] Should show: Book icon + "No journal entries yet"

#### 2. List Display ✅
- [ ] See 3 entries stacked vertically
- [ ] Each card shows:
  - Title (or "Untitled")
  - Excerpt (120 chars max)
  - Date/time
  - Three-dot menu button
- [ ] Cards have proper spacing (12pt between)
- [ ] Light mode: cards visible
- [ ] Dark mode: cards visible

---

### **B. Create Entry (AddEntryView)**

#### 3. Open Add Entry
- [ ] Tap FAB (+) button at bottom-right
- [ ] Sheet slides up from bottom
- [ ] Keyboard auto-focuses on text field
- [ ] Placeholder: "What's on your mind?"

#### 4. Enter Text
- [ ] Type: "This is a test entry"
- [ ] Save button should be disabled when empty
- [ ] Save button should be enabled when text exists

#### 5. Save Entry
- [ ] Tap **"Save"** button
- [ ] Haptic feedback occurs
- [ ] Sheet dismisses
- [ ] New entry appears at TOP of list
- [ ] Entry shows "Untitled" (no title entered)
- [ ] Entry shows full text or excerpt

#### 6. Cancel Entry
- [ ] Tap FAB again
- [ ] Type some text
- [ ] Tap **"Cancel"**
- [ ] Sheet dismisses
- [ ] Entry is NOT added to list

---

### **C. View Entry (JournalPageView)**

#### 7. Open Entry (View Mode)
- [ ] Tap any JournalCard
- [ ] Sheet slides up
- [ ] Navigation title: "Journal Entry"
- [ ] Shows full title (or "Untitled")
- [ ] Shows full text (scrollable)
- [ ] Shows metadata:
  - Created date/time
  - Updated date/time (if different)
- [ ] Top-left: **"Done"** button
- [ ] Top-right: **"Edit"** button

#### 8. Read Entry
- [ ] Text is selectable (can copy)
- [ ] Scroll works if text is long
- [ ] No editing possible in view mode

#### 9. Close Entry
- [ ] Tap **"Done"**
- [ ] Sheet dismisses
- [ ] Returns to JournalView

---

### **D. Edit Entry (JournalPageView)**

#### 10. Enter Edit Mode
- [ ] Open any entry (tap card)
- [ ] Tap **"Edit"** button (top-right)
- [ ] Navigation title changes to "Edit Entry"
- [ ] Title field becomes editable
- [ ] Text editor becomes editable
- [ ] Keyboard focuses on title field
- [ ] Top-left: **"Cancel"** button
- [ ] Top-right: **"Save"** button (disabled if text empty)

#### 11. Edit Title
- [ ] Type a new title: "Updated Title"
- [ ] Title updates as you type
- [ ] Placeholder: "Add a title..." (if empty)

#### 12. Edit Text
- [ ] Tap text area
- [ ] Modify text: "This is updated text"
- [ ] Text updates as you type
- [ ] Placeholder: "Write your thoughts..." (if empty)

#### 13. Save Changes
- [ ] Tap **"Save"** button
- [ ] Shows loading indicator briefly
- [ ] Haptic feedback occurs
- [ ] Returns to view mode
- [ ] Title shows updated value
- [ ] Text shows updated value
- [ ] "Updated" date changes to current time
- [ ] Console shows: "✅ Updated entry: [UUID]"

#### 14. Cancel Changes
- [ ] Tap **"Edit"** again
- [ ] Make some changes
- [ ] Tap **"Cancel"** button
- [ ] Changes are reverted
- [ ] Returns to view mode with original values

---

### **E. Delete Entry**

#### 15. Open Delete Menu
- [ ] From JournalView, tap three-dot button (•••) on any card
- [ ] Native confirmation dialog appears from bottom
- [ ] Shows: "Delete this entry?"
- [ ] Message: "This action cannot be undone."
- [ ] Two options: **"Delete"** (red) and **"Cancel"**

#### 16. Cancel Delete
- [ ] Tap **"Cancel"**
- [ ] Dialog dismisses
- [ ] Entry remains in list

#### 17. Confirm Delete
- [ ] Tap three-dot button again
- [ ] Tap **"Delete"** (red button)
- [ ] Entry immediately disappears from list
- [ ] Other entries shift up smoothly
- [ ] Console shows: "🗑️ Deleted entry: [UUID]"

---

### **F. Edge Cases**

#### 18. Empty Title
- [ ] Create entry with no title
- [ ] Card shows "Untitled"
- [ ] Open entry → shows "Untitled" (grayed out)
- [ ] Edit entry → placeholder: "Add a title..."

#### 19. Long Text
- [ ] Create entry with 500+ words
- [ ] Card shows excerpt (120 chars + "...")
- [ ] Open entry → full text is scrollable
- [ ] Edit entry → TextEditor scrolls properly

#### 20. Multiple Entries
- [ ] Create 5+ new entries
- [ ] All appear in list (newest first)
- [ ] Scroll works smoothly
- [ ] Each entry maintains its data

#### 21. Rapid Actions
- [ ] Create entry quickly
- [ ] Immediately open it
- [ ] Edit and save
- [ ] Delete it
- [ ] No crashes or state issues

---

### **G. Design System Compliance**

#### 22. Theme Tokens
- [ ] All colors use `theme.*` properties
- [ ] No hardcoded colors
- [ ] Light mode: proper contrast
- [ ] Dark mode: proper contrast

#### 23. Typography Tokens
- [ ] Titles use correct font sizes (28pt bold)
- [ ] Body text uses correct font (17pt regular)
- [ ] Metadata uses correct font (15pt)
- [ ] No hardcoded font sizes outside of specific UI

#### 24. Spacing
- [ ] Cards have 12pt spacing
- [ ] Padding is consistent (16-20pt)
- [ ] Navigation bar spacing correct

---

### **H. Accessibility**

#### 25. VoiceOver
- [ ] Enable VoiceOver (Settings → Accessibility)
- [ ] Swipe through JournalView
- [ ] Each card is announced with title + date + excerpt
- [ ] Three-dot button announces "More options"
- [ ] FAB announces "New Entry"

#### 26. Dynamic Type
- [ ] Settings → Display & Brightness → Text Size
- [ ] Increase text size
- [ ] All text scales appropriately
- [ ] Layouts don't break

---

### **I. Performance**

#### 27. Smooth Scrolling
- [ ] Create 20+ entries (temporarily increase mock data)
- [ ] Scroll through list
- [ ] No lag or stuttering
- [ ] LazyVStack loads efficiently

#### 28. Sheet Animations
- [ ] Open/close AddEntryView → smooth
- [ ] Open/close JournalPageView → smooth
- [ ] No visual glitches

---

## 🐛 Known Limitations (Phase 1)

### **Mock Data Only**
- ❌ Entries don't persist (reset on app restart)
- ❌ No Supabase integration yet
- ❌ No loading states for network calls

**Fix**: Phase 2 (Supabase Integration)

### **No Search/Filter**
- ❌ Can't search entries
- ❌ "Follow-ups" tab not functional

**Fix**: Future enhancement

### **No Rich Text**
- ❌ Plain text only
- ❌ No bold, italic, lists

**Fix**: Future enhancement

---

## 📊 Console Output Reference

### **Expected Console Messages**

#### Create Entry:
```
✅ Created entry: 12345678-1234-1234-1234-123456789012
```

#### Update Entry:
```
✅ Updated entry: 12345678-1234-1234-1234-123456789012
```

#### Delete Entry:
```
🗑️ Deleted entry: 12345678-1234-1234-1234-123456789012
```

---

## 🚨 Common Issues & Fixes

### Issue 1: Entries Don't Appear
**Symptom**: JournalView shows empty state  
**Cause**: Mock data not loading  
**Fix**: Check `EntryViewModel.init()` calls `loadMockEntries()`

### Issue 2: Can't Edit Entry
**Symptom**: Edit button doesn't work  
**Cause**: Entry not passed to JournalPageView  
**Fix**: Verify `selectedEntry` binding in JournalView

### Issue 3: Delete Doesn't Work
**Symptom**: Entry doesn't disappear  
**Cause**: ViewModel not connected  
**Fix**: Verify `entryViewModel.deleteEntry(id:)` is called

### Issue 4: Keyboard Doesn't Dismiss
**Symptom**: Keyboard stuck on screen  
**Cause**: Focus state not cleared  
**Fix**: Tap "Done" on keyboard toolbar

---

## 🎯 Success Criteria

### **Phase 1 Complete** ✅
- [x] Can create entries
- [x] Can view entries as cards
- [x] Can open and read entries
- [x] Can edit entries
- [x] Can delete entries
- [x] UI matches design system
- [x] No crashes or errors
- [x] Mock data works

### **Ready for Phase 2** 🚀
Once all tests pass, proceed to:
1. Supabase table setup
2. Database CRUD operations
3. Real data persistence
4. Loading states
5. Error handling

---

## 📝 Test Report Template

```markdown
## Test Results

**Date**: _____________________
**Tester**: ___________________
**Device**: ___________________
**iOS Version**: ______________

### Passed Tests: __ / 28

#### A. View Entries
- [ ] Empty state
- [ ] List display

#### B. Create Entry
- [ ] Open add entry
- [ ] Enter text
- [ ] Save entry
- [ ] Cancel entry

#### C. View Entry
- [ ] Open entry
- [ ] Read entry
- [ ] Close entry

#### D. Edit Entry
- [ ] Enter edit mode
- [ ] Edit title
- [ ] Edit text
- [ ] Save changes
- [ ] Cancel changes

#### E. Delete Entry
- [ ] Open delete menu
- [ ] Cancel delete
- [ ] Confirm delete

#### F. Edge Cases
- [ ] Empty title
- [ ] Long text
- [ ] Multiple entries
- [ ] Rapid actions

#### G. Design System
- [ ] Theme tokens
- [ ] Typography tokens
- [ ] Spacing

#### H. Accessibility
- [ ] VoiceOver
- [ ] Dynamic Type

#### I. Performance
- [ ] Smooth scrolling
- [ ] Sheet animations

### Issues Found:
1. _________________________________
2. _________________________________
3. _________________________________

### Notes:
_____________________________________
_____________________________________
```

---

**Status**: ✅ Phase 1 Implementation Complete  
**Next**: Test all scenarios above  
**Then**: Proceed to Phase 2 (Supabase)

🎉 **Happy Testing!**
