//
//  FollowUpQuestionGroup.swift
//  MeetMemento
//
//  Created by Sebastian Mendo on 1/13/26.
//

import SwiftUI

/// A group of follow-up questions with configurable content
struct FollowUpQuestionGroup: View {
    // MARK: - Inputs
    let questions: [String]
    var onQuestionTap: ((Int, String) -> Void)?

    // MARK: - Environment
    @Environment(\.theme) private var theme

    // MARK: - Body
    var body: some View {
        VStack(spacing: 24) {
            ForEach(Array(questions.enumerated()), id: \.offset) { index, question in
                FollowUpQuestion(
                    question: question,
                    onTap: {
                        onQuestionTap?(index, question)
                    }
                )
                .padding(.horizontal, 20)

                // Add divider between questions (not after the last one)
                if index < questions.count - 1 {
                    Rectangle()
                        .fill(theme.glassBorder)
                        .frame(height: 1)
                        .padding(.horizontal, 20)
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Three Questions") {
    ZStack {
        GrayScale.gray50
            .ignoresSafeArea()

        ScrollView {
            FollowUpQuestionGroup(
                questions: [
                    "What would happen if you let go of the need to control everything?",
                    "How does your past shape the way you see your future?",
                    "What are you afraid to admit to yourself?"
                ],
                onQuestionTap: { index, question in
                    AppLogger.log("Question \(index + 1) tapped: \(question)")
                }
            )
        }
    }
    .useTypography()
}

#Preview("Two Questions") {
    ZStack {
        GrayScale.gray50
            .ignoresSafeArea()

        ScrollView {
            FollowUpQuestionGroup(
                questions: [
                    "How might your relationships change if you prioritized vulnerability?",
                    "What are you avoiding by staying busy?"
                ],
                onQuestionTap: { index, question in
                    AppLogger.log("Tapped: \(question)")
                }
            )
        }
    }
    .useTypography()
}

#Preview("Four Questions") {
    ZStack {
        GrayScale.gray50
            .ignoresSafeArea()

        ScrollView {
            FollowUpQuestionGroup(
                questions: [
                    "What would happen if you let go of the need to control everything?",
                    "How does your past shape the way you see your future?",
                    "What are you afraid to admit to yourself?",
                    "How might your relationships change if you prioritized vulnerability over perfection?"
                ]
            )
        }
    }
    .useTypography()
}

#Preview("In Insights Context") {
    ZStack {
        GrayScale.gray50
            .ignoresSafeArea()

        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Text("Your Reflections")
                    .font(Typography().h3)
                    .foregroundStyle(BaseColors.black)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                FollowUpQuestionGroup(
                    questions: [
                        "What would happen if you let go of the need to control everything?",
                        "How does your past shape the way you see your future?",
                        "What are you afraid to admit to yourself?"
                    ],
                    onQuestionTap: { index, question in
                        AppLogger.log("Reflection \(index + 1) selected")
                    }
                )

                Spacer()
            }
        }
    }
    .useTypography()
}
