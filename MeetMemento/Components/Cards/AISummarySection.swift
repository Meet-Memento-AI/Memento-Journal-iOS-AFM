import SwiftUI

/// AI Summary section for Insights view
/// Displays a title (max 4 lines, h2) and body paragraph (max 300 words)
public struct AISummarySection: View {
    public let title: String
    public let bodyText: String

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    public init(title: String, body: String) {
        self.title = title
        self.bodyText = body
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header with icon
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .bold)) // icon-size: not user text
                    .foregroundStyle(theme.accent)

                Text("YOUR AI SUMMARY")
                    .font(type.h6)
                    .foregroundStyle(theme.foreground)
            }

            // Main content
            VStack(alignment: .leading, spacing: 24) {
                // Title (max 4 lines)
                Text(title)
                    .font(type.h2)
                    // h2 display headings carry primary/600.
                    .foregroundStyle(PrimaryScale.primary600)
                    .lineLimit(5)
                    .multilineTextAlignment(.leading)

                // Body paragraph (max 300 words)
                Text(bodyText)
                    .font(type.body1)
                    .foregroundStyle(theme.mutedForeground)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Preview
#Preview {
    ZStack {
        // Purple gradient background to match Insights view
        LinearGradient(
            gradient: Gradient(colors: [
                GrayScale.gray50,
                GrayScale.gray50
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        ScrollView {
            AISummarySection(
                title: "Your emotional landscape reveals a blend of reflection, frustration, and growth.",
                body: "You've been processing heavy emotions around work, identity, and control, yet your tone has steadily shifted toward acceptance and purpose. Despite moments of doubt, there's an emerging sense of trust in your own process. You're beginning to see growth not as a finish line, but as an ongoing practice of alignment and awareness."
            )
            .padding(20)
        }
    }
    .useTheme()
    .useTypography()
}
