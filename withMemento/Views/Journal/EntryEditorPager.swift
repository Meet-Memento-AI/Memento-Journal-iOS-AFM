//
//  EntryEditorPager.swift
//  MeetMemento
//
//  Horizontal paging between saved entries inside the full-page editor
//  (PRES-023). A thumb swipe walks the journal timeline's own order — newest
//  on the left, older to the right — so the gesture and the list agree
//  directionally, the same contract `RootPager` holds for the root pages.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Page activity

private struct EditorPageActiveKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// False on an editor page the pager has moved off. `AddEntryView` reads it
    /// to drop the keyboard, end dictation, write pending edits, and to skip
    /// the full-file decrypt plus CoreImage treated bake — a swipe is
    /// navigation between entries, not a discard, but a neighbour must not
    /// pay for a cover nobody can see.
    ///
    /// Defaults to `true` so the create routes, the standalone destinations and
    /// previews behave exactly as they did before paging existed.
    var editorPageIsActive: Bool {
        get { self[EditorPageActiveKey.self] }
        set { self[EditorPageActiveKey.self] = newValue }
    }
}

// MARK: - Pager

/// Built on `TabView` + `.page` for the same reason `RootPager` is: it gives
/// interruptible, rubber-banded, velocity-aware paging and per-page state,
/// none of which a hand-rolled `DragGesture` gets right.
///
/// Only existing entries page. A `.create` route has no neighbours, so
/// `EntryEditorDestination` mounts `AddEntryView` directly for those.
/// Existing pages open in view; `AddEntryView` owns the view/edit session
/// and writes back through `updateEntry` without dismissing.
struct EntryEditorPager: View {
    /// The entry the zoom transition opened. Also the *only* page when the
    /// timeline hasn't been loaded in this session (deep link, Spotlight),
    /// which keeps the editor's pre-paging behavior intact.
    let startEntry: Entry

    @EnvironmentObject private var entryViewModel: EntryViewModel

    @State private var selection: UUID

    init(startEntry: Entry) {
        self.startEntry = startEntry
        _selection = State(initialValue: startEntry.id)
    }

    /// `entries` is already sorted newest-first — the timeline's own order — so
    /// a right-to-left swipe walks the list downward exactly as scrolling does.
    private var pages: [Entry] {
        let timeline = entryViewModel.entries
        guard timeline.contains(where: { $0.id == startEntry.id }) else { return [startEntry] }
        return timeline
    }

    var body: some View {
        GeometryReader { proxy in
            // `RootPager`'s lift: a page `TabView` keeps a top inset of its own
            // even when told to ignore the safe area, and that inset would push
            // the editor header off `windowTop`.
            let topLift = max(proxy.frame(in: .global).minY, 0)
            let bottomLift = topLift > 0 ? AppHeaderMetrics.windowBottom : 0
            TabView(selection: $selection) {
                ForEach(pages) { entry in
                    editor(for: entry)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ignoresSafeArea()
                        .environment(\.editorPageIsActive, entry.id == selection)
                        .tag(entry.id)
                }
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif
            .frame(
                width: proxy.size.width,
                height: proxy.size.height + topLift + bottomLift
            )
            .offset(y: -topLift)
        }
        .ignoresSafeArea()
        // The pager is the navigation destination for edit routes. A default
        // container fill here is the white cap above the Dynamic Island;
        // each page's AddEntryView paints the cover into that strip.
        .containerBackground(.clear, for: .navigation)
        // NO `.accessibilityIdentifier` on this container: it would overwrite
        // the identifier of every SwiftUI-native descendant, which is how the
        // editor's own header ids were lost once before (see `AddEntryView`).
        //
        // Same commit haptic as the root pager, so both swipes read as one
        // gesture vocabulary (PRES-004, PRES-093).
        .onChange(of: selection) { _, _ in
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        }
    }

    /// The one place an existing entry is written back. `AddEntryView` calls
    /// it from in-place save *and* when a swipe carries the page off screen with
    /// unsaved edits. The journal toast is create-only — the user stays here.
    private func editor(for entry: Entry) -> some View {
        AddEntryView(state: .edit(entry)) { title, text, photoAction, locationAction in
            var updated = entry
            updated.title = title
            updated.text = text
            entryViewModel.updateEntry(
                updated, photoAction: photoAction, locationAction: locationAction
            )
        }
    }
}

// MARK: - Previews

#Preview("Editor paging") {
    NavigationStack {
        EntryEditorPager(startEntry: Entry.sampleEntries[0])
            .environmentObject(EntryViewModel.withPreviewEntries())
    }
    .useTheme()
    .useTypography()
}
