//
//  NarrationListeningCanvas.swift
//  MeetMemento
//
//  The only page copy while Chat is narrating: a centered serif prompt
//  over the dissolved thread. Header, glow, and NarrationFooter stay.
//

import SwiftUI

struct NarrationListeningCanvas: View {
    @Environment(\.typography) private var type

    var body: some View {
        Text("What\u{2019}s on your\nmind?")
            .font(type.h2)
            .foregroundStyle(PrimaryScale.primary600)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel("What's on your mind?")
    }
}

#Preview("Listening canvas") {
    NarrationListeningCanvas()
        .useTheme()
        .useTypography()
}
