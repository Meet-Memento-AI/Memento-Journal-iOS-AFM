//
//  FollowUpQuestion.swift
//  MeetMemento
//
//  Created by Sebastian Mendo on 1/13/26.
//

import SwiftUI

/// A clickable follow-up question card
struct FollowUpQuestion: View {
    // MARK: - Inputs
    let question: String
    var onTap: (() -> Void)?

    // MARK: - Environment
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    // MARK: - State
    @State private var isPressed = false

    // MARK: - Body
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.turn.down.right")
                .font(type.h4)
                .foregroundStyle(theme.overlayText)

            Text(question)
                .font(type.h6)
                .foregroundStyle(theme.overlayText)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .onTapGesture {
            onTap?()
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    isPressed = true
                }
                .onEnded { _ in
                    isPressed = false
                }
        )
    }
}

// MARK: - Previews

#Preview("Single Question") {
    ZStack {
        PrimaryScale.primary900
            .ignoresSafeArea()

        FollowUpQuestion(
            question: "What would happen if you let go of the need to control everything?",
            onTap: {
                AppLogger.log("Question tapped")
            }
        )
        .padding(.horizontal, 20)
    }
    .useTypography()
}

#Preview("With Tap Handler") {
    ZStack {
        PrimaryScale.primary900
            .ignoresSafeArea()

        FollowUpQuestion(
            question: "How might your relationships change if you prioritized vulnerability over perfection?",
            onTap: {
                AppLogger.log("Question tapped")
            }
        )
        .padding(.horizontal, 20)
    }
    .useTypography()
}
