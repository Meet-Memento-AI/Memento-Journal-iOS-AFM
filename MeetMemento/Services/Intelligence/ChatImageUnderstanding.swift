//
//  ChatImageUnderstanding.swift
//  MeetMemento
//
//  A text reading of attached chat photos for the Ask prompt.
//
//  iOS 27 Foundation Models can take image `Attachment`s directly; that type
//  is not in the iOS 26 SDK this target builds against. Until the app is
//  built with Xcode 27, this is how the on-device model "sees" a photo:
//  classify what's in it, read any visible text, and note whether people
//  are present. No `import FoundationModels` — this file is prompt input,
//  not a second intelligence importer.
//

import UIKit
import Vision

enum ChatImageUnderstanding {

    /// Labeled visual readings for the current turn plus any earlier photos
    /// still sitting on in-session history.
    static func promptBlock(current: [Data], history: [ChatTurn]) async -> String {
        var sections: [String] = []
        for (turnIndex, turn) in history.enumerated() {
            for (photoIndex, jpeg) in turn.imageJPEGs.enumerated() {
                let label = "earlier-turn-\(turnIndex + 1)-photo-\(photoIndex + 1)"
                sections.append("[\(label)]\n\(await describe(jpeg))")
            }
        }
        for (photoIndex, jpeg) in current.enumerated() {
            let label = "this-message-photo-\(photoIndex + 1)"
            sections.append("[\(label)]\n\(await describe(jpeg))")
        }
        return sections.joined(separator: "\n\n")
    }

    private static func describe(_ jpeg: Data) async -> String {
        await Task.detached(priority: .userInitiated) {
            guard let image = UIImage(data: jpeg), let cgImage = image.cgImage else {
                return "Could not read this photo."
            }
            return describeCGImage(cgImage)
        }.value
    }

    private static func describeCGImage(_ cgImage: CGImage) -> String {
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let classify = VNClassifyImageRequest()
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = true
        let faces = VNDetectFaceRectanglesRequest()

        do {
            try handler.perform([classify, textRequest, faces])
        } catch {
            return "Could not analyze this photo."
        }

        var lines: [String] = []

        let identifiers = (classify.results ?? [])
            .filter { $0.confidence >= 0.2 }
            .prefix(8)
            .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
        if !identifiers.isEmpty {
            lines.append("Likely contents: \(identifiers.joined(separator: ", ")).")
        }

        let snippets = (textRequest.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(12)
        if !snippets.isEmpty {
            lines.append("Visible text: \(snippets.joined(separator: " | ")).")
        }

        let faceCount = faces.results?.count ?? 0
        if faceCount == 1 {
            lines.append("People: 1 face visible.")
        } else if faceCount > 1 {
            lines.append("People: \(faceCount) faces visible.")
        }

        if lines.isEmpty {
            return "A photo is attached, but no labels, text, or faces were recognized."
        }
        return lines.joined(separator: " ")
    }
}
