//
//  TransparentNavigationContainer.swift
//  MeetMemento
//
//  Makes a NavigationStack's container genuinely see-through, so a transparent
//  stack root reveals what sits behind the stack instead of a system fill.
//
//  ContentView pushes the entry editor onto an overlay stack layered above
//  RootPager specifically so `.navigationTransition(.zoom)` morphs over the live
//  journal timeline. `.containerBackground(.clear, for: .navigation)` states that
//  intent declaratively, but its coverage for `.navigation` has moved between iOS
//  releases; when it does not take, the container paints an opaque fill and the
//  zoom happens over a blank plate. This asserts the same thing in UIKit so the
//  backdrop does not depend on which behavior the running OS has.
//

import SwiftUI
import UIKit

extension View {
    /// Clears the fill of every layer between this view and the enclosing
    /// `UINavigationController`'s view, inclusive.
    func transparentNavigationContainer() -> some View {
        background(TransparentNavigationContainer())
    }
}

private struct TransparentNavigationContainer: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        ContainerClearingProbe()
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        (uiView as? ContainerClearingProbe)?.clearContainerFills()
    }
}

private final class ContainerClearingProbe: UIView {
    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        clearContainerFills()
    }

    /// The navigation controller rebuilds the wrapper view around its root on
    /// every push, so one pass at creation is not enough — re-assert on layout.
    /// `clear(_:)` no-ops once a layer is already transparent, so the steady
    /// state costs nothing.
    override func layoutSubviews() {
        super.layoutSubviews()
        clearContainerFills()
    }

    /// Walks from this probe up to the navigation controller's own view. Those
    /// are the layers that can paint over whatever is behind the stack; the walk
    /// deliberately stops there rather than continuing into ContentView's ZStack
    /// host or the app's root hosting view, which are shared with every other
    /// surface.
    func clearContainerFills() {
        guard let navigationView = nearestViewController()?.navigationController?.view else { return }

        var ancestor: UIView? = self
        while let current = ancestor, !(current is UIWindow) {
            clear(current)
            if current === navigationView { return }
            ancestor = current.superview
        }
    }

    private func clear(_ view: UIView) {
        if view.backgroundColor != UIColor.clear {
            view.backgroundColor = UIColor.clear
        }
        if view.isOpaque {
            view.isOpaque = false
        }
    }
}
