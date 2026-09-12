//
//  LocationAction.swift
//  MeetMemento
//
//  What AddEntryView's composer did to an entry's place name this session.
//

import Foundation

/// A tri-state, not `String?` — `String?` can't distinguish "editing an
/// entry that already has a place, untouched this session" from "explicitly
/// cleared it", since both collapse to `nil`. Same reason as `PhotoAction`.
public enum LocationAction: Equatable {
    /// The place (if any) is exactly as it was — don't change `placeName`.
    case unchanged
    /// A place was attached or replaced this session.
    case set(String)
    /// The place was explicitly removed.
    case removed
}
