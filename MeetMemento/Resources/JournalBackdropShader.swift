//
//  JournalBackdropShader.swift
//  MeetMemento
//
//  Tokenized Figma shader "Journal backdrop" (node 786:2721). The WebGPU
//  runtime cannot run on iOS; these are the three operations that shader
//  applies (separable Gaussian, saturation toward luma, mix toward a dark
//  scrim), with the *applied* instance values as defaults.
//

import SwiftUI

/// Average sRGB of a cover photo, sampled once when the thumbnail decrypts.
struct JournalBackdropSample: Equatable, Sendable, Codable {
    let red: Double
    let green: Double
    let blue: Double
}

/// Resolved blur / saturation / scrim to apply on a photo card.
struct JournalBackdropParameters: Equatable, Sendable {
    var blurStrength: CGFloat
    var scrimOpacity: Double
    var saturation: Double
}

enum JournalBackdropShader {
    /// Figma `blurStrength` on 786:2721.
    static let blurStrength: CGFloat = 12
    /// Figma instance `scrimOpacity` (not the shader's 0.55 control default).
    static let scrimOpacity: Double = 0.34
    /// Figma instance `saturation`.
    static let saturation: Double = 0.92
    /// Shader `scrimColor` `vec3f(0.039)`.
    static let scrimColor = Color(red: 0.039, green: 0.039, blue: 0.039)
    static let scrimRed = 0.039
    static let scrimGreen = 0.039
    static let scrimBlue = 0.039
    /// WCAG AA for normal text. Title is 20pt (large-text 3:1 would pass);
    /// white-on-photo still aims at 4.5.
    static let minimumContrast: Double = 4.5
    static let maxBlur: CGFloat = 24
    /// Increase Contrast accessibility floor for scrim.
    static let increaseContrastFloor: Double = 0.55

    static let designDefaults = JournalBackdropParameters(
        blurStrength: blurStrength,
        scrimOpacity: scrimOpacity,
        saturation: saturation
    )

    /// Figma editor instance 818:4087 — full-bleed max-blur cover
    /// (title and body both sit on the photo).
    static let editorDefaults = JournalBackdropParameters(
        blurStrength: 100,
        scrimOpacity: 0.51,
        saturation: 0.89
    )
}
