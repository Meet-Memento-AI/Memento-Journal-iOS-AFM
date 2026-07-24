//
//  InsightAnnotationsSection.swift
//  MeetMemento
//
//  Timeline visualization of key dates mentioned in insights
//  Displays date annotations between description and themes
//

import SwiftUI

public struct InsightAnnotationsSection: View {
    let annotations: [InsightAnnotation]
    @State private var selectedAnnotation: InsightAnnotation?
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    public init(annotations: [InsightAnnotation]) {
        self.annotations = annotations
    }

    public var body: some View {
        if !annotations.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                // Section header
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.system(size: 16, weight: .medium)) // icon-size: not user text
                        .foregroundColor(theme.overlayTextSecondary)

                    Text("Timeline")
                        .font(type.body1Medium)
                        .foregroundColor(theme.overlayText)
                }

                // Annotations - horizontally wrapped, tappable
                FlowLayout(spacing: 12) {
                    ForEach(annotations.sorted(by: { $0.date < $1.date }), id: \.date) { annotation in
                        InsightDateTag(dateString: annotation.date, format: .short)
                            .onTapGesture {
                                selectedAnnotation = annotation
                            }
                    }
                }
            }
            .padding(.vertical, 8)
            .sheet(item: $selectedAnnotation) { annotation in
                AnnotationDetailSheet(annotation: annotation)
            }
        }
    }
}

// MARK: - Annotation Detail Sheet

private struct AnnotationDetailSheet: View {
    let annotation: InsightAnnotation
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                // Date header
                Text(formattedDate)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(theme.foreground)

                // Summary paragraph
                if !annotation.summary.isEmpty {
                    Text(annotation.summary)
                        .font(.body)
                        .foregroundColor(theme.foreground.opacity(0.8))
                        .lineSpacing(6)
                } else {
                    Text("No details available for this date.")
                        .font(.body)
                        .foregroundColor(theme.mutedForeground)
                        .italic()
                }

                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(theme.foreground)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var formattedDate: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        guard let date = formatter.date(from: annotation.date) else {
            return annotation.date
        }

        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .long
        return displayFormatter.string(from: date)
    }
}

// MARK: - Flow Layout

/// A layout that arranges its children in a horizontal flow, wrapping to the next line when needed
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.frames[index].minX, y: bounds.minY + result.frames[index].minY), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var frames: [CGRect] = []
        var size: CGSize = .zero

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > maxWidth && x > 0 {
                    // Move to next line
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }

                frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
            }

            self.size = CGSize(width: maxWidth, height: y + lineHeight)
        }
    }
}

// MARK: - Previews

#Preview("Single Annotation") {
    InsightAnnotationsSection(
        annotations: [
            InsightAnnotation(date: "2025-10-03", summary: "This was the presentation that kept replaying in your mind. The performance anxiety peaked here, revealing patterns of self-criticism even when others saw success.")
        ]
    )
    .padding()
    .background(Color.black)
    .preferredColorScheme(.dark)
}

#Preview("Multiple Annotations") {
    InsightAnnotationsSection(
        annotations: [
            InsightAnnotation(date: "2025-10-03", summary: "This was the presentation that kept replaying in your mind. The performance anxiety peaked here, revealing patterns of self-criticism even when others saw success."),
            InsightAnnotation(date: "2025-09-28", summary: "The farmer's market visit marked a shift toward reconnecting with simple pleasures. This moment of presence contrasted sharply with the work stress dominating other days."),
            InsightAnnotation(date: "2025-10-22", summary: "You finally vocalized your need for support to your manager. This represented a breakthrough in recognizing that asking for help isn't weakness, but wisdom."),
            InsightAnnotation(date: "2025-10-18", summary: "Work overwhelm reached a tipping point. This day highlighted the unsustainability of your current pace."),
            InsightAnnotation(date: "2025-10-20", summary: "A creative solution emerged after days of feeling stuck. This breakthrough restored confidence in your problem-solving abilities."),
            InsightAnnotation(date: "2025-10-25", summary: "You began to find a rhythm between work demands and personal needs. Small adjustments made a noticeable difference.")
        ]
    )
    .padding()
    .background(Color.black)
    .preferredColorScheme(.dark)
}

#Preview("Empty Annotations") {
    InsightAnnotationsSection(annotations: [])
        .padding()
        .background(Color.black)
        .preferredColorScheme(.dark)
}

#Preview("In Dark Mode") {
    VStack(alignment: .leading, spacing: 24) {
        Text("Your Emotional Landscape")
            .font(.title2)
            .fontWeight(.bold)
            .foregroundColor(.white)

        Text("Over the past week, you've been processing performance anxiety at work, particularly around presentations where you sometimes freeze despite being well-prepared.")
            .font(.body)
            .foregroundColor(.white.opacity(0.8))

        InsightAnnotationsSection(
            annotations: [
                InsightAnnotation(date: "2025-10-03", summary: "This was the presentation that kept replaying in your mind. The performance anxiety peaked here, revealing patterns of self-criticism even when others saw success."),
                InsightAnnotation(date: "2025-09-28", summary: "The farmer's market visit marked a shift toward reconnecting with simple pleasures. This moment of presence contrasted sharply with the work stress dominating other days."),
                InsightAnnotation(date: "2025-10-22", summary: "You finally vocalized your need for support to your manager. This represented a breakthrough in recognizing that asking for help isn't weakness, but wisdom.")
            ]
        )

        Divider()
            .background(.white.opacity(0.2))

        Text("Your Themes")
            .font(.title3)
            .fontWeight(.semibold)
            .foregroundColor(.white)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding()
    .background(Color.black)
    .preferredColorScheme(.dark)
}
