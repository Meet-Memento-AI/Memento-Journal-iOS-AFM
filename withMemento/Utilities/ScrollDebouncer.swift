//
//  ScrollDebouncer.swift
//  MeetMemento
//
//  Utility for debouncing scroll updates to reduce per-pixel tracking overhead.
//

import Foundation
import SwiftUI

@MainActor
final class ScrollDebouncer: ObservableObject {
    private var task: Task<Void, Never>?
    private let delay: TimeInterval

    init(delay: TimeInterval = 0.1) {
        self.delay = delay
    }

    func debounce(_ action: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            action()
        }
    }

    deinit {
        task?.cancel()
    }
}
