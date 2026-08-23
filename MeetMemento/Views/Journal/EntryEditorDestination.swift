//
//  EntryEditorDestination.swift
//  MeetMemento
//
//  Shared NavigationStack destination for AddEntryView. ContentView's overlay
//  stack and JournalView's standalone stack both use this so save, dismiss,
//  zoom, and hidden system chrome cannot drift.
//

import SwiftUI

// MARK: - Zoom namespace

private struct EntryZoomNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    /// Shared by create/open sources (FAB, cards, chat write control) and the
    /// editor destination so `.navigationTransition(.zoom)` can morph.
    var entryZoomNamespace: Namespace.ID? {
        get { self[EntryZoomNamespaceKey.self] }
        set { self[EntryZoomNamespaceKey.self] = newValue }
    }
}

extension View {
    /// Marks this view as the zoom source for an `EntryRoute`.
    ///
    /// `cornerRadius` clips the transition-source platter. Pass it for any
    /// non-rectangular source — without it the platter is an unclipped square,
    /// which reads as a grey plate behind a round control like the FAB. Half
    /// the control's size spells a circle; `nil` keeps the system default.
    func entryZoomSource(_ sourceID: String, cornerRadius: CGFloat? = nil) -> some View {
        modifier(EntryZoomSourceModifier(sourceID: sourceID, cornerRadius: cornerRadius))
    }
}

private struct EntryZoomSourceModifier: ViewModifier {
    @Environment(\.entryZoomNamespace) private var namespace
    let sourceID: String
    let cornerRadius: CGFloat?

    func body(content: Content) -> some View {
        if let namespace {
            if let cornerRadius {
                // `RoundedRectangle` is the only shape this configuration
                // accepts — the generic `clipShape` overload is marked
                // unavailable ("matchedTransitionSource only supports
                // `RoundedRectangle` clip shapes"), so a fully-rounded rect is
                // how a circular source gets spelled.
                content.matchedTransitionSource(id: sourceID, in: namespace) {
                    $0.clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
            } else {
                content.matchedTransitionSource(id: sourceID, in: namespace)
            }
        } else {
            content
        }
    }
}

private struct EntryZoomDestinationModifier: ViewModifier {
    @Environment(\.entryZoomNamespace) private var namespace
    let sourceID: String

    func body(content: Content) -> some View {
        if let namespace {
            content.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            content
        }
    }
}

// MARK: - Destination

struct EntryEditorDestination: View {
    let route: EntryRoute
    var onSaved: () -> Void = {}

    @EnvironmentObject private var entryViewModel: EntryViewModel

    var body: some View {
        editor
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar(.hidden, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
            .environment(\.fabVisible, false)
            .modifier(EntryZoomDestinationModifier(sourceID: route.zoomSourceID))
    }

    @ViewBuilder
    private var editor: some View {
        switch route {
        case .create:
            AddEntryView(state: .create) { title, text, photoAction in
                entryViewModel.createEntry(title: title, text: text, photoAction: photoAction)
                onSaved()
            }
        case .createWithTitle(let prefillTitle):
            AddEntryView(state: .createWithTitle(prefillTitle)) { title, text, photoAction in
                entryViewModel.createEntry(title: title, text: text, photoAction: photoAction)
                onSaved()
            }
        case .createWithContent(let prefillTitle, let prefillContent):
            AddEntryView(state: .createWithContent(title: prefillTitle, content: prefillContent)) { title, text, photoAction in
                entryViewModel.createEntry(title: title, text: text, photoAction: photoAction)
                onSaved()
            }
        case .edit(let entry):
            AddEntryView(state: .edit(entry)) { title, text, photoAction in
                var updated = entry
                updated.title = title
                updated.text = text
                entryViewModel.updateEntry(updated, photoAction: photoAction)
                onSaved()
            }
        }
    }
}
