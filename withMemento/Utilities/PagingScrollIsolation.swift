//
//  PagingScrollIsolation.swift
//  MeetMemento
//
//  Nested horizontal ScrollViews inside RootPager (TabView + `.page`) share an
//  axis with the paging UIScrollView. UIKit transfers leftover pan — especially
//  rubber-band bounce — into the pager, so Journal/Chat slides. This probe
//  disables the ancestor paging scroller for the life of the nested pan.
//

import SwiftUI
import UIKit

extension View {
    /// Keeps this view's horizontal scroll from rubber-banding RootPager.
    func isolateFromPagingScroll() -> some View {
        background(PagingScrollIsolation())
    }
}

private struct PagingScrollIsolation: UIViewRepresentable {
    func makeUIView(context: Context) -> PagingScrollIsolationProbe {
        PagingScrollIsolationProbe()
    }

    func updateUIView(_ uiView: PagingScrollIsolationProbe, context: Context) {
        uiView.attachIfNeeded()
    }
}

final class PagingScrollIsolationProbe: UIView {
    private weak var inner: UIScrollView?
    private weak var paging: UIScrollView?
    private var pagingWasEnabled = true

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        detach()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            detach()
        } else {
            attachIfNeeded()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        attachIfNeeded()
    }

    func attachIfNeeded() {
        guard window != nil else { return }
        if inner?.window != nil, paging?.window != nil { return }
        let foundInner = findInnerScrollView()
        let foundPaging = foundInner.flatMap { findPagingScrollView(after: $0) }
        guard let foundInner, let foundPaging else { return }

        if inner !== foundInner {
            inner?.panGestureRecognizer.removeTarget(self, action: #selector(handlePan(_:)))
            inner = foundInner
            foundInner.isDirectionalLockEnabled = true
            foundInner.panGestureRecognizer.addTarget(self, action: #selector(handlePan(_:)))
        }
        paging = foundPaging
    }

    private func detach() {
        inner?.panGestureRecognizer.removeTarget(self, action: #selector(handlePan(_:)))
        unlockPaging()
        inner = nil
        paging = nil
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began, .changed:
            lockPaging()
        case .ended, .cancelled, .failed:
            // Finger is up. Bounce-back after lift does not transfer into the
            // pager; keeping it locked here would never re-enable paging.
            unlockPaging()
        default:
            break
        }
    }

    private func lockPaging() {
        guard let paging else { return }
        if paging.isScrollEnabled {
            pagingWasEnabled = true
            paging.isScrollEnabled = false
        }
        snapPagingToNearestPage(paging)
    }

    private func unlockPaging() {
        guard let paging else { return }
        if !paging.isScrollEnabled && pagingWasEnabled {
            paging.isScrollEnabled = true
        }
    }

    private func snapPagingToNearestPage(_ paging: UIScrollView) {
        let width = paging.bounds.width
        guard width > 0 else { return }
        let page = (paging.contentOffset.x / width).rounded()
        let x = page * width
        guard abs(paging.contentOffset.x - x) > 0.5 else { return }
        paging.setContentOffset(CGPoint(x: x, y: paging.contentOffset.y), animated: false)
    }

    // MARK: - Hierarchy

    private func findInnerScrollView() -> UIScrollView? {
        nearbyScrollViews().first { scroll in
            scroll.contentSize.width > scroll.bounds.width + 1
                && !isPagingScrollView(scroll)
        }
    }

    private func findPagingScrollView(after inner: UIScrollView) -> UIScrollView? {
        nearbyScrollViews().first { scroll in
            scroll !== inner && isPagingScrollView(scroll)
        }
    }

    private func isPagingScrollView(_ scroll: UIScrollView) -> Bool {
        if scroll.isPagingEnabled { return true }
        let width = scroll.bounds.width
        guard width > 0 else { return false }
        // TabView `.page` on recent iOS is not always flagged `isPagingEnabled`.
        // The root pager is full-bleed and at least two pages wide; the
        // suggestion carousel is a short row (~200pt).
        return scroll.contentSize.width >= width * 1.9 && scroll.bounds.height >= 400
    }

    /// Ancestors plus nearby sibling subtrees. SwiftUI's `.background` probe is
    /// often a sibling of the `UIScrollView` it is attached to, not a descendant.
    private func nearbyScrollViews() -> [UIScrollView] {
        var seen = Set<ObjectIdentifier>()
        var result: [UIScrollView] = []

        func add(_ scroll: UIScrollView) {
            let id = ObjectIdentifier(scroll)
            guard !seen.contains(id) else { return }
            seen.insert(id)
            result.append(scroll)
        }

        var current: UIView? = self
        while let view = current {
            if let scroll = view as? UIScrollView { add(scroll) }
            if let parent = view.superview {
                for sub in parent.subviews {
                    collectScrollViews(from: sub, into: add, depth: 0)
                }
            }
            current = view.superview
        }
        return result
    }

    private func collectScrollViews(
        from view: UIView,
        into add: (UIScrollView) -> Void,
        depth: Int
    ) {
        if let scroll = view as? UIScrollView {
            add(scroll)
            return
        }
        guard depth < 4 else { return }
        for sub in view.subviews {
            collectScrollViews(from: sub, into: add, depth: depth + 1)
        }
    }
}
