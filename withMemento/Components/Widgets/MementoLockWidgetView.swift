//
//  MementoLockWidgetView.swift
//  MeetMemento
//
//  Spec 020 R4: lock-screen widget redaction contract. When the device is
//  locked, journal text is not shown — only a generic prompt to capture.
//  A WidgetKit extension target can host this view; the redaction rule is
//  enforced here so it cannot drift.
//

import SwiftUI

struct MementoLockWidgetView: View {
    var isDeviceLocked: Bool
    var entryCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Memento")
                .font(.headline)
            if isDeviceLocked {
                Text("Journal")
                    .font(.subheadline)
                    .redacted(reason: .privacy)
                Text("Unlock to read")
                    .font(.caption)
            } else {
                Text("\(entryCount) entries")
                    .font(.subheadline)
                    .accessibilityIdentifier("widget.entryCount")
            }
        }
        .padding()
    }
}

#Preview("Locked") {
    MementoLockWidgetView(isDeviceLocked: true, entryCount: 12)
}

#Preview("Unlocked") {
    MementoLockWidgetView(isDeviceLocked: false, entryCount: 12)
}
