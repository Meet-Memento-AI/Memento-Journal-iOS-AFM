//
//  NewEntryFAB.swift
//  MeetMemento
//
//  Floating Action Button for creating new journal entries.
//  Rendered as a prominent, tinted Liquid Glass button (native `.glassProminent`
//  button style). The deployment target is iOS 26, so glass is always available.
//

import SwiftUI

public struct NewEntryFAB: View {
    let action: () -> Void
    var size: CGFloat = 64
    var enableHaptic: Bool = true

    @Environment(\.theme) private var theme

    public init(size: CGFloat = 64, enableHaptic: Bool = true, action: @escaping () -> Void) {
        self.size = size
        self.enableHaptic = enableHaptic
        self.action = action
    }

    public var body: some View {
        Button {
            if enableHaptic {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            action()
        } label: {
            // Liquid Glass removed — brand color intentionally kept (prominent
            // FAB); flat purple circle, no glass.
            Image(systemName: "square.and.pencil")
                .font(.system(size: size * 0.4, weight: .bold)) // icon-size: not user text
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Circle().fill(theme.primary))
        }
        .buttonStyle(FABPressStyle())
        .accessibilityLabel("New Journal Entry")
        .accessibilityIdentifier("journal.newEntryFAB")
    }
}

private struct FABPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Positioned Wrapper

/// Wrapper that positions the FAB in the bottom-right corner with swipe animations
public struct PositionedNewEntryFAB: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let swipeProgress: CGFloat
    let action: () -> Void

    public init(swipeProgress: CGFloat = 0, action: @escaping () -> Void) {
        self.swipeProgress = swipeProgress
        self.action = action
    }

    public var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                NewEntryFAB(action: action)
                    .opacity(1 - swipeProgress)
                    .scaleEffect(1 - (swipeProgress * 0.3))
                    .offset(x: swipeProgress * 60)
                    .allowsHitTesting(swipeProgress < 0.5)
                    .animation(reduceMotion ? nil : .interactiveSpring(response: 0.3, dampingFraction: 0.8), value: swipeProgress)
                    .padding(.trailing, 20)
                    .padding(.bottom, 56)
            }
        }
    }
}

// MARK: - Previews

#Preview("Light") {
    ZStack {
        LinearGradient(colors: [.blue.opacity(0.3), .purple.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
        VStack { Spacer(); HStack { Spacer(); NewEntryFAB { }.padding(20) } }
    }
    .useTheme().useTypography()
}

#Preview("Dark") {
    ZStack {
        GrayScale.gray900.ignoresSafeArea()
        VStack { Spacer(); HStack { Spacer(); NewEntryFAB { }.padding(20) } }
    }
    .useTheme().useTypography().preferredColorScheme(.dark)
}
