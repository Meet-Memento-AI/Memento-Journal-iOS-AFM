//
//  ViewModifiers.swift
//  MeetMemento
//
//  Created by Claude Code
//  Reusable view modifiers for consistent UI patterns
//

import SwiftUI
import UIKit

// MARK: - Reduce Motion Support

/// Checks if the user has enabled "Reduce Motion" in accessibility settings.
/// Use this to disable or simplify animations for users who are sensitive to motion.
extension View {
    /// Applies animation only when reduce motion is not enabled.
    /// When reduce motion is enabled, uses no animation (instant transitions).
    /// - Parameters:
    ///   - animation: The animation to apply when reduce motion is disabled
    ///   - value: The value to watch for changes
    /// - Returns: View with accessibility-aware animation
    func accessibleAnimation<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        modifier(AccessibleAnimationModifier(animation: animation, value: value))
    }

    /// Applies animation only when reduce motion is not enabled.
    /// When reduce motion is enabled, uses no animation (instant transitions).
    /// - Parameter animation: The animation to apply when reduce motion is disabled
    /// - Returns: View with accessibility-aware animation
    func accessibleAnimation(_ animation: Animation?) -> some View {
        modifier(AccessibleAnimationValuelessModifier(animation: animation))
    }
}

private struct AccessibleAnimationModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation?
    let value: V

    func body(content: Content) -> some View {
        content
            .animation(reduceMotion ? nil : animation, value: value)
    }
}

private struct AccessibleAnimationValuelessModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation?

    func body(content: Content) -> some View {
        content
            .transaction { transaction in
                transaction.animation = reduceMotion ? nil : animation
            }
    }
}

/// Executes a closure with animation, respecting reduce motion preference.
/// - Parameters:
///   - animation: The animation to use when reduce motion is disabled
///   - reduceMotion: Whether reduce motion is enabled
///   - body: The closure to execute
public func withAccessibleAnimation<Result>(
    _ animation: Animation? = .default,
    reduceMotion: Bool,
    _ body: () throws -> Result
) rethrows -> Result {
    if reduceMotion {
        return try body()
    } else {
        return try withAnimation(animation, body)
    }
}

/// A view that provides reduce motion context to its content.
/// Use this wrapper to access reduce motion state in non-view contexts.
public struct ReduceMotionReader<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let content: (Bool) -> Content

    public init(@ViewBuilder content: @escaping (Bool) -> Content) {
        self.content = content
    }

    public var body: some View {
        content(reduceMotion)
    }
}

// MARK: - Card Styling

extension View {
    /// Apply standard card styling with rounded corners, background, optional border, and shadow
    /// - Parameters:
    ///   - radius: Corner radius (default: 24)
    ///   - border: Whether to show border (default: false)
    ///   - shadow: Whether to show shadow (default: true)
    ///   - backgroundColor: Optional background color (defaults to theme.cardBackground)
    /// - Returns: Styled view with card appearance
    func cardStyle(radius: CGFloat = 24, border: Bool = false, shadow: Bool = true, backgroundColor: Color? = nil) -> some View {
        modifier(CardStyleModifier(cornerRadius: radius, showBorder: border, showShadow: shadow, backgroundColor: backgroundColor))
    }
}

private struct CardStyleModifier: ViewModifier {
    @Environment(\.theme) private var theme

    let cornerRadius: CGFloat
    let showBorder: Bool
    let showShadow: Bool
    let backgroundColor: Color?

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(backgroundColor ?? theme.cardBackground)
            )
            .overlay(
                Group {
                    if showBorder {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(theme.border, lineWidth: 1)
                    }
                }
            )
            .shadow(
                color: showShadow ? .black.opacity(0.1) : .clear,
                radius: showShadow ? 8 : 0,
                x: 0,
                y: showShadow ? 4 : 0
            )
    }
}

// MARK: - Press Effects

extension View {
    /// Apply press/scale animation effect
    /// - Parameters:
    ///   - isPressed: Binding to pressed state
    ///   - scale: Scale factor when pressed (default: 0.98)
    ///   - duration: Animation duration (default: Spacing.Duration.fast)
    /// - Returns: View with press animation
    func pressEffect(isPressed: Binding<Bool>, scale: CGFloat = 0.98, duration: CGFloat = Spacing.Duration.fast) -> some View {
        modifier(PressEffectModifier(isPressed: isPressed, scale: scale, duration: duration))
    }
}

private struct PressEffectModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var isPressed: Bool
    let scale: CGFloat
    let duration: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? scale : 1.0)
            .animation(reduceMotion ? nil : .easeInOut(duration: duration), value: isPressed)
    }
}

// MARK: - Haptic Feedback

extension View {
    /// Add haptic feedback to tap gesture
    /// - Parameters:
    ///   - style: Haptic feedback style (default: .light)
    ///   - action: Action to perform on tap
    /// - Returns: View with haptic tap gesture
    func hapticTap(style: UIImpactFeedbackGenerator.FeedbackStyle = .light, action: @escaping () -> Void) -> some View {
        modifier(HapticTapModifier(style: style, action: action))
    }
}

private struct HapticTapModifier: ViewModifier {
    let style: UIImpactFeedbackGenerator.FeedbackStyle
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture {
                let impactFeedback = UIImpactFeedbackGenerator(style: style)
                impactFeedback.impactOccurred()
                action()
            }
    }
}

// MARK: - Keyboard

extension View {
    /// Dismisses the keyboard when the user taps outside a text field or editor.
    /// Taps on `UITextView` / `UITextField` still focus and type; buttons keep
    /// their own action because the recognizer does not cancel touches.
    func dismissKeyboardOnOutsideTap() -> some View {
        background(DismissKeyboardOnOutsideTap())
    }
}

private struct DismissKeyboardOnOutsideTap: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let probe = UIView(frame: .zero)
        probe.backgroundColor = .clear
        probe.isUserInteractionEnabled = false
        return probe
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.install(from: uiView)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var installedOn: UIView?
        private var recognizer: UITapGestureRecognizer?

        func install(from probe: UIView) {
            DispatchQueue.main.async { [weak self] in
                guard let self, let host = probe.nearestViewController()?.view ?? probe.superview else { return }
                if installedOn === host { return }
                uninstall()
                let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
                tap.cancelsTouchesInView = false
                tap.delegate = self
                host.addGestureRecognizer(tap)
                recognizer = tap
                installedOn = host
            }
        }

        func uninstall() {
            if let recognizer {
                installedOn?.removeGestureRecognizer(recognizer)
            }
            recognizer = nil
            installedOn = nil
        }

        @objc func dismissKeyboard() {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil,
                from: nil,
                for: nil
            )
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view {
                if current is UITextView || current is UITextField {
                    return false
                }
                view = current.superview
            }
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

extension UIView {
    /// Walks the responder chain for the controller hosting this view.
    /// Shared with `TransparentNavigationContainer`, which needs the same walk
    /// to reach the enclosing `UINavigationController`.
    func nearestViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let controller = current as? UIViewController {
                return controller
            }
            responder = current.next
        }
        return nil
    }
}

// MARK: - Spacing Shortcuts

extension View {
    /// Apply horizontal padding using semantic spacing
    /// - Parameter value: Spacing value (default: Spacing.md)
    /// - Returns: View with horizontal padding
    func hPadding(_ value: CGFloat = Spacing.md) -> some View {
        padding(.horizontal, value)
    }

    /// Apply vertical padding using semantic spacing
    /// - Parameter value: Spacing value (default: Spacing.md)
    /// - Returns: View with vertical padding
    func vPadding(_ value: CGFloat = Spacing.md) -> some View {
        padding(.vertical, value)
    }
}
