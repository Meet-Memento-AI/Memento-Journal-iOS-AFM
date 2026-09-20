//
//  LoadingTypes.swift
//  MeetMemento
//
//  Shared types and data for loading screens
//

import Foundation

// MARK: - Loading Phases

enum LoadingPhase {
    case initial
    case authenticating
    case loadingData
    case finalizing

    var message: String {
        switch self {
        case .initial:
            return ""
        case .authenticating:
            return "Preparing your space..."
        case .loadingData:
            return "Loading your memories..."
        case .finalizing:
            return "Almost there..."
        }
    }
}

// MARK: - Loading Tips

struct LoadingTip {
    let icon: String
    let title: String
    let message: String
}

let loadingTips = [
    LoadingTip(
        icon: "heart.fill",
        title: "Daily practice",
        message: "Journaling for just 5 minutes a day can improve mental clarity and reduce stress."
    ),
    LoadingTip(
        icon: "wind",
        title: "Breathe mindfully",
        message: "Take three slow, deep breaths. Notice how your body feels right now."
    ),
    LoadingTip(
        icon: "brain.head.profile",
        title: "Spot patterns",
        message: "Regular reflection helps you understand recurring thoughts and behaviors."
    ),
    LoadingTip(
        icon: "target",
        title: "Set intentions",
        message: "Writing down your goals makes you 42% more likely to achieve them."
    ),
    LoadingTip(
        icon: "lock.shield.fill",
        title: "Safe space",
        message: "Your journal is private. Write honestly without judgment or fear."
    ),
    LoadingTip(
        icon: "sparkles",
        title: "Find joy",
        message: "Small moments of mindfulness can transform your entire day."
    )
]
