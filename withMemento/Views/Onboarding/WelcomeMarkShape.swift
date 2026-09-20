//
//  WelcomeMarkShape.swift
//  MeetMemento
//
//  Rebrand mark paths (hexagon body + sparkle) from AppIcon-Transparent.svg,
//  viewBox 72×72, for Liquid Glass clipping.
//

import SwiftUI

private enum WelcomeMarkViewBox {
    static let size: CGFloat = 72

    static func transform(for rect: CGRect) -> CGAffineTransform {
        CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: rect.width / size, y: rect.height / size)
    }
}

/// Folded-hexagon / journal body of the welcome mark.
struct WelcomeMarkBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 12, y: 28.5076))
        path.addCurve(
            to: CGPoint(x: 20.729, y: 23.8493),
            control1: CGPoint(x: 12, y: 24.0229),
            control2: CGPoint(x: 17.0034, y: 21.3528)
        )
        path.addLine(to: CGPoint(x: 35.6423, y: 33.8428))
        path.addCurve(
            to: CGPoint(x: 36.3577, y: 33.8428),
            control1: CGPoint(x: 35.8587, y: 33.9878),
            control2: CGPoint(x: 36.1413, y: 33.9878)
        )
        path.addLine(to: CGPoint(x: 51.271, y: 23.8493))
        path.addCurve(
            to: CGPoint(x: 60, y: 28.5076),
            control1: CGPoint(x: 54.9966, y: 21.3528),
            control2: CGPoint(x: 60, y: 24.0229)
        )
        path.addLine(to: CGPoint(x: 60, y: 43.6547))
        path.addCurve(
            to: CGPoint(x: 53.6216, y: 55.1),
            control1: CGPoint(x: 60, y: 48.3171),
            control2: CGPoint(x: 57.5868, y: 52.6473)
        )
        path.addLine(to: CGPoint(x: 36.7891, y: 65.5119))
        path.addCurve(
            to: CGPoint(x: 35.2109, y: 65.5119),
            control1: CGPoint(x: 36.3055, y: 65.811),
            control2: CGPoint(x: 35.6945, y: 65.811)
        )
        path.addLine(to: CGPoint(x: 18.3784, y: 55.1))
        path.addCurve(
            to: CGPoint(x: 12, y: 43.6547),
            control1: CGPoint(x: 14.4132, y: 52.6473),
            control2: CGPoint(x: 12, y: 48.3171)
        )
        path.addLine(to: CGPoint(x: 12, y: 28.5076))
        path.closeSubpath()
        return path.applying(WelcomeMarkViewBox.transform(for: rect))
    }
}

/// Four-point sparkle above the welcome mark body.
struct WelcomeMarkSparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 33.7679, y: 7.59582))
        path.addCurve(
            to: CGPoint(x: 38.1599, y: 7.40835),
            control1: CGPoint(x: 34.473, y: 5.5325),
            control2: CGPoint(x: 37.3239, y: 5.47001)
        )
        path.addLine(to: CGPoint(x: 38.2306, y: 7.597))
        path.addLine(to: CGPoint(x: 39.1821, y: 10.3795))
        path.addCurve(
            to: CGPoint(x: 40.2154, y: 12.092),
            control1: CGPoint(x: 39.4002, y: 11.0177),
            control2: CGPoint(x: 39.7525, y: 11.6016)
        )
        path.addCurve(
            to: CGPoint(x: 41.8656, y: 13.2222),
            control1: CGPoint(x: 40.6784, y: 12.5824),
            control2: CGPoint(x: 41.2411, y: 12.9678)
        )
        path.addLine(to: CGPoint(x: 42.1215, y: 13.3177))
        path.addLine(to: CGPoint(x: 44.904, y: 14.268))
        path.addCurve(
            to: CGPoint(x: 45.0927, y: 18.6599),
            control1: CGPoint(x: 46.9673, y: 14.9731),
            control2: CGPoint(x: 47.0298, y: 17.824)
        )
        path.addLine(to: CGPoint(x: 44.904, y: 18.7307))
        path.addLine(to: CGPoint(x: 42.1215, y: 19.6821))
        path.addCurve(
            to: CGPoint(x: 40.4083, y: 20.7153),
            control1: CGPoint(x: 41.4831, y: 19.9001),
            control2: CGPoint(x: 40.8989, y: 20.2524)
        )
        path.addCurve(
            to: CGPoint(x: 39.2776, y: 22.3656),
            control1: CGPoint(x: 39.9177, y: 21.1782),
            control2: CGPoint(x: 39.5322, y: 21.741)
        )
        path.addLine(to: CGPoint(x: 39.1821, y: 22.6203))
        path.addLine(to: CGPoint(x: 38.2318, y: 25.404))
        path.addCurve(
            to: CGPoint(x: 33.841, y: 25.5927),
            control1: CGPoint(x: 37.5267, y: 27.4673),
            control2: CGPoint(x: 34.6758, y: 27.5298)
        )
        path.addLine(to: CGPoint(x: 33.7679, y: 25.404))
        path.addLine(to: CGPoint(x: 32.8176, y: 22.6215))
        path.addCurve(
            to: CGPoint(x: 31.7845, y: 20.9084),
            control1: CGPoint(x: 32.5997, y: 21.9831),
            control2: CGPoint(x: 32.2474, y: 21.399)
        )
        path.addCurve(
            to: CGPoint(x: 30.1341, y: 19.7776),
            control1: CGPoint(x: 31.3215, y: 20.4178),
            control2: CGPoint(x: 30.7587, y: 20.0322)
        )
        path.addLine(to: CGPoint(x: 29.8794, y: 19.6821))
        path.addLine(to: CGPoint(x: 27.0969, y: 18.7318))
        path.addCurve(
            to: CGPoint(x: 26.9082, y: 14.3411),
            control1: CGPoint(x: 25.0324, y: 18.0268),
            control2: CGPoint(x: 24.9699, y: 15.1759)
        )
        path.addLine(to: CGPoint(x: 27.0969, y: 14.268))
        path.addLine(to: CGPoint(x: 29.8794, y: 13.3177))
        path.addCurve(
            to: CGPoint(x: 31.5919, y: 12.2843),
            control1: CGPoint(x: 30.5176, y: 13.0996),
            control2: CGPoint(x: 31.1015, y: 12.7473)
        )
        path.addCurve(
            to: CGPoint(x: 32.7221, y: 10.6342),
            control1: CGPoint(x: 32.0823, y: 11.8214),
            control2: CGPoint(x: 32.4677, y: 11.2587)
        )
        path.addLine(to: CGPoint(x: 32.8176, y: 10.3795))
        path.addLine(to: CGPoint(x: 33.7679, y: 7.59582))
        path.closeSubpath()
        return path.applying(WelcomeMarkViewBox.transform(for: rect))
    }
}
