//
//  DeviceCopy.swift
//  MeetMemento
//
//  Spec 040 R6: device-neutral / idiom-aware user-facing copy.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum DeviceCopy {
    /// Idiom-aware: "this iPhone" or "this iPad".
    static var thisDevice: String {
        #if canImport(UIKit)
        UIDevice.current.userInterfaceIdiom == .pad ? "this iPad" : "this iPhone"
        #else
        "this device"
        #endif
    }

    static var thisDeviceGeneric: String { "this device" }

    static var journalLivesLocally: String {
        "Your journal lives on \(thisDevice)."
    }

    static var signedOutSync: String {
        "Your journal lives on \(thisDevice). iCloud backup is off — sign in to iCloud to turn it on."
    }

    static var quotaExceeded: String {
        "iCloud is full, so recent entries aren't backed up yet. Everything is still safe on \(thisDevice)."
    }

    static var writtenOnDevice: String {
        "Written on \(thisDevice)."
    }

    static var indexingIncomplete: String {
        "Search may be incomplete while \(thisDevice) finishes indexing."
    }
}
