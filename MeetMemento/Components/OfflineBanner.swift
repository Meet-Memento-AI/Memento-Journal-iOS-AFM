//
//  OfflineBanner.swift
//  MeetMemento
//
//  Dismissible banner shown while the device has no connectivity.
//  Journaling remains fully local — this is informational only.
//

import SwiftUI

struct OfflineBanner: View {
    var onDismiss: (() -> Void)?

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 13, weight: .bold)) // icon-size: not user text

            Text("You're offline. Your journal stays on this device and keeps working.")
                .font(type.caption)
                .fontWeight(.medium)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold)) // icon-size: not user text
                }
                .accessibilityLabel("Dismiss offline notice")
            }
        }
        .foregroundStyle(theme.overlayText)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule().fill(theme.destructive)
        )
        .shadow(color: theme.foreground.opacity(0.12), radius: 8, x: 0, y: 3)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// Wraps `OfflineBanner` with the show/dismiss state driven by `NetworkMonitor`.
struct OfflineBannerContainer: View {
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @State private var isDismissed = false

    var body: some View {
        Group {
            if !networkMonitor.isConnected && !isDismissed {
                OfflineBanner(onDismiss: { isDismissed = true })
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: networkMonitor.isConnected && !isDismissed)
        .onChange(of: networkMonitor.isConnected) { _, isConnected in
            if isConnected {
                isDismissed = false
            }
        }
    }
}

// MARK: - Previews

#Preview("Offline Banner") {
    ZStack {
        Color.gray.opacity(0.2).ignoresSafeArea()
        VStack {
            OfflineBanner(onDismiss: {})
                .padding(.top, 40)
            Spacer()
        }
    }
    .useTheme()
    .useTypography()
}
