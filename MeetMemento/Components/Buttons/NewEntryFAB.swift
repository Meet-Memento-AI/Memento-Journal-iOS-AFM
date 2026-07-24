//
//  NewEntryFAB.swift
//  MeetMemento
//
//  Floating Action Button for creating new journal entries.
//  Uses iOS 26 Liquid Glass effect when available, falls back to
//  gradient with inner glow on earlier versions.
//

import SwiftUI

public struct NewEntryFAB: View {
    let action: () -> Void
    var size: CGFloat = 64
    var enableHaptic: Bool = true

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

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
            fabContent
        }
        .buttonStyle(FABPressStyle())
        .accessibilityLabel("New Journal Entry")
        .accessibilityIdentifier("journal.newEntryFAB")
    }

    @ViewBuilder
    private var fabContent: some View {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            glassStyleContent
        } else {
            fallbackStyleContent
        }
        #else
        fallbackStyleContent
        #endif
    }

    #if canImport(FoundationModels)
    // iOS 26+: Pure liquid glass with primary/600 icon
    @available(iOS 26.0, *)
    private var glassStyleContent: some View {
        Image(systemName: "square.and.pencil")
            .font(.system(size: size * 0.4, weight: .bold)) // icon-size: not user text
            .foregroundStyle(PrimaryScale.primary600)
            .frame(width: size, height: size)
            .mementoGlassEffect(
                .regular.tint(theme.primary.opacity(0.85)).interactive(),
                in: Circle()
            )
    }
    #endif

    // iOS 18-25: Gradient with inner glow
    private var fallbackStyleContent: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [theme.fabGradientStart, theme.fabGradientEnd],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))

            // Inner glow for depth
            Circle()
                .fill(RadialGradient(
                    colors: [Color.white.opacity(0.25), Color.white.opacity(0.0)],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: size * 0.8
                ))

            Image(systemName: "square.and.pencil")
                .font(.system(size: size * 0.4, weight: .bold)) // icon-size: not user text
                .foregroundStyle(theme.primaryForeground)
        }
        .frame(width: size, height: size)
        .shadow(color: theme.primary.opacity(0.3), radius: 12, x: 0, y: 6)
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
