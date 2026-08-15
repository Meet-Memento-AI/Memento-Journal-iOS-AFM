//
//  PhotoAction.swift
//  MeetMemento
//
//  What AddEntryView's composer did to an entry's photo during this session.
//

import Foundation

/// A tri-state, not `Data?` — `Data?` can't distinguish "editing an entry that
/// already has a photo, untouched this session" from "explicitly cleared it",
/// since both collapse to `nil`. This type keeps those distinct so the save
/// path only ever touches `PhotoStorage` when the user actually changed something.
public enum PhotoAction: Equatable {
    /// The photo (if any) is exactly as it was — don't touch `PhotoStorage`.
    case unchanged
    /// A new photo was captured/picked, replacing whatever was there before.
    case set(Data)
    /// The photo was explicitly removed.
    case removed
}
