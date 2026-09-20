//
//  KeyboardObserver.swift
//  MeetMemento
//
//  Observable object that tracks keyboard height using Combine for smooth animations
//

import SwiftUI
import Combine
import UIKit

@MainActor
final class KeyboardObserver: ObservableObject {
    @Published var keyboardHeight: CGFloat = 0
    @Published var isKeyboardVisible: Bool = false

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Keyboard will show
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .compactMap { notification -> (CGFloat, Double)? in
                guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
                      let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
                else { return nil }
                return (frame.height, duration)
            }
            .sink { [weak self] height, duration in
                withAnimation(.easeOut(duration: duration)) {
                    self?.keyboardHeight = height
                    self?.isKeyboardVisible = true
                }
            }
            .store(in: &cancellables)

        // Keyboard will hide
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .compactMap { $0.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double }
            .sink { [weak self] duration in
                withAnimation(.easeOut(duration: duration)) {
                    self?.keyboardHeight = 0
                    self?.isKeyboardVisible = false
                }
            }
            .store(in: &cancellables)
    }
}
