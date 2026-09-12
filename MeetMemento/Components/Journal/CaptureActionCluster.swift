//
//  CaptureActionCluster.swift
//  MeetMemento
//
//  Editor footer Capture control. Same native SwiftUI `Menu` wrapper as
//  `ReplyOverflowMenu`: the capsule stays put; Take photo / Upload photo
//  appear as system Liquid Glass menu rows. Do not wrap this in a second
//  GlassEffectContainer — the footer already owns the sampling region.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct CaptureActionCluster: View {
    var foreground: Color
    var interactive: Bool
    var onTakePhoto: () -> Void
    var onUploadPhoto: () -> Void

    @Environment(\.typography) private var type

    private static let labelGap: CGFloat = 8
    private static let padding: CGFloat = 16

    var body: some View {
        Menu {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onTakePhoto()
            } label: {
                Label("Take photo", systemImage: "camera")
            }
            .accessibilityIdentifier("journal.entryEditor.capture.takePhoto")

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onUploadPhoto()
            } label: {
                Label("Upload photo", systemImage: "photo")
            }
            .accessibilityIdentifier("journal.entryEditor.capture.uploadPhoto")
        } label: {
            HStack(spacing: Self.labelGap) {
                Image(systemName: "camera")
                    .font(AppHeaderMetrics.controlSymbolFont)
                Text("Capture")
                    .font(type.button)
                    .lineLimit(1)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, Self.padding)
            .mementoFooterGlassButtonChrome(interactive: interactive)
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .accessibilityLabel("Capture")
        .accessibilityHint("Double-tap to take a photo or choose one from your library")
        .accessibilityIdentifier("journal.entryEditor.capture")
    }
}
