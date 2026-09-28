//
//  AIChatAccessibilityPreviews.swift
//  withMemento
//
//  AX5 Dynamic Type canvases for Chat. Kept out of AIChatView.swift, which is
//  at the SwiftLint file_length limit.
//

import SwiftUI

#Preview("Empty State · AX5") {
    @Previewable @StateObject var viewModel = ChatViewModel()
    NavigationStack {
        AIChatView(
            viewModel: viewModel,
            isEmbedded: true,
            hasEntries: true,
            seededSuggestions: ChatSuggestion.previewSamples
        )
    }
    .useTheme()
    .useTypography()
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Narration · Speaking · AX5") {
    @Previewable @StateObject var viewModel = ChatViewModel()
    AIChatView(
        viewModel: viewModel,
        isEmbedded: true,
        narrationPreview: AIChatNarrationPreviewConfiguration(
            phase: .speaking,
            messages: AIChatNarrationPreviewConfiguration.sampleTurn
        )
    )
    .useTheme()
    .useTypography()
    .environment(\.dynamicTypeSize, .accessibility5)
}
