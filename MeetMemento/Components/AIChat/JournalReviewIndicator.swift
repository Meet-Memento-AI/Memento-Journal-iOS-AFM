//
//  JournalReviewIndicator.swift
//  MeetMemento
//
//  Indicator component showing number of reviewed journals with detail sheet
//

import SwiftUI

public struct JournalReviewIndicator: View {
    let reviewedCount: Int
    var onTap: (() -> Void)?
    
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @State private var showDetailSheet = false
    
    public init(
        reviewedCount: Int,
        onTap: (() -> Void)? = nil
    ) {
        self.reviewedCount = reviewedCount
        self.onTap = onTap
    }
    
    public var body: some View {
        Button {
            if let onTap = onTap {
                onTap()
            } else {
                showDetailSheet = true
            }
        } label: {
            HStack(spacing: 6) {
                Text("Reviewed \(reviewedCount) \(reviewedCount == 1 ? "journal" : "journals")")
                    .font(type.body2)
                    .foregroundStyle(theme.primary)
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold)) // icon-size: not user text
                    .foregroundStyle(theme.primary)
            }
        }
        .sheet(isPresented: $showDetailSheet) {
            JournalReviewDetailSheet(reviewedCount: reviewedCount)
        }
    }
}

// MARK: - Detail Sheet

private struct JournalReviewDetailSheet: View {
    let reviewedCount: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Journal Review Details")
                        .font(type.h3)
                        .foregroundStyle(theme.foreground)
                        .padding(.top, 8)
                    
                    Text("This feature will show detailed information about the \(reviewedCount) journal\(reviewedCount == 1 ? "" : "s") that have been reviewed by the AI.")
                        .font(type.body1)
                        .foregroundStyle(theme.mutedForeground)
                    
                    Text("Future implementation will include:")
                        .font(type.body1Bold)
                        .foregroundStyle(theme.foreground)
                        .padding(.top, 8)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        DetailRow(text: "List of reviewed journal entries")
                        DetailRow(text: "Date range of reviewed entries")
                        DetailRow(text: "Key themes identified")
                        DetailRow(text: "Citation references in AI responses")
                    }
                }
                .padding(20)
            }
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("Journal Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .useTheme()
        .useTypography()
    }
}

private struct DetailRow: View {
    let text: String
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16)) // icon-size: not user text
                .foregroundStyle(theme.primary)
            
            Text(text)
                .font(type.body1)
                .foregroundStyle(theme.foreground)
        }
    }
}

// MARK: - Previews

#Preview("Journal Review Indicator") {
    VStack {
        JournalReviewIndicator(reviewedCount: 5)
        Spacer()
    }
    .padding()
    .useTheme()
    .useTypography()
}

#Preview("Journal Review Indicator • Single") {
    VStack {
        JournalReviewIndicator(reviewedCount: 1)
        Spacer()
    }
    .padding()
    .useTheme()
    .useTypography()
}
