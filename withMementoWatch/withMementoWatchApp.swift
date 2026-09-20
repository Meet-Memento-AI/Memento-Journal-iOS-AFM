//
//  MeetMementoWatchApp.swift
//  MeetMementoWatch
//
//  Spec 020 R5 / DEC-005: Watch companion in 2.0. The four App Intents in
//  the iOS target are the on-wrist surface (Siri / Shortcuts on Apple Watch).
//  This WatchKit host is the dedicated target for complications / glance UI;
//  it is not yet attached to the iOS scheme so merge CI stays green.
//

import SwiftUI

@main
struct MeetMementoWatchApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Memento on Watch uses the same four shortcuts as iPhone.")
                .padding()
        }
    }
}
