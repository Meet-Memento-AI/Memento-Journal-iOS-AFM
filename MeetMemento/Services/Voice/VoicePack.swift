//
//  VoicePack.swift
//  MeetMemento
//
//  Locates the bundled neural-voice assets (spec 030 R2).
//
//  There is no download and no asset pack — the model ships inside the app
//  binary. What this type exists to absorb is one non-obvious fact about how it
//  gets there: the app target uses a PBXFileSystemSynchronizedRootGroup, which
//  **flattens every resource into the bundle root**. The files live at
//  MeetMemento/Resources/Voices/ in the repository, but at runtime there is no
//  Voices/ directory and no voice_styles/ subdirectory — VectorEstimator.mlmodelc
//  and F1.json sit at the top level beside Figtree-Regular.ttf.
//
//  Code written against a Voices/ path compiles and fails at runtime. This is
//  the single place that knows the truth.
//

import Foundation

enum VoicePack {

    /// The four CoreML graphs, by the filename each `.mlmodelc` ships under.
    enum Graph: String, CaseIterable {
        case textEncoder = "TextEncoder"
        case durationPredictor = "DurationPredictor"
        case vectorEstimator = "VectorEstimator"
        case vocoder = "Vocoder"
    }

    /// Directory the graphs resolve against — the bundle root, because of the
    /// flattening described above.
    static var modelsDirectory: URL? { Bundle.main.resourceURL }

    /// `unicode_indexer.json` — the tokenizer's index table. The engine is
    /// G2P-free: text is NFKD-normalized and mapped through this, with no
    /// phonemizer anywhere (which is why it clears spec 018 R12's licence gate).
    static var unicodeIndexer: URL? {
        Bundle.main.url(forResource: "unicode_indexer", withExtension: "json")
    }

    /// Style vectors for the shipping roster, keyed by style id.
    ///
    /// Only the four vendored voices can resolve — the other six the base model
    /// publishes are not in the repository at all (spec 030 R4), so this cannot
    /// return them however it is called.
    static func styleURLs() -> [String: URL] {
        var out: [String: URL] = [:]
        for voice in VoiceCatalog.all {
            if let url = Bundle.main.url(forResource: voice.id, withExtension: "json") {
                out[voice.id] = url
            }
        }
        return out
    }

    /// True when every asset the engine needs is present in the bundle.
    /// A false here means a build problem, not a runtime state to design for —
    /// there is no "not downloaded yet".
    static var isComplete: Bool {
        guard let dir = modelsDirectory, unicodeIndexer != nil else { return false }
        let graphsPresent = Graph.allCases.allSatisfy {
            FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("\($0.rawValue).mlmodelc").path
            )
        }
        return graphsPresent && styleURLs().count == VoiceCatalog.all.count
    }

    /// Human-readable description of what is missing, for diagnostics.
    static func missingAssets() -> [String] {
        var missing: [String] = []
        if unicodeIndexer == nil { missing.append("unicode_indexer.json") }
        if let dir = modelsDirectory {
            for graph in Graph.allCases where !FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("\(graph.rawValue).mlmodelc").path
            ) {
                missing.append("\(graph.rawValue).mlmodelc")
            }
        } else {
            missing.append("bundle resourceURL")
        }
        let styles = styleURLs()
        for voice in VoiceCatalog.all where styles[voice.id] == nil {
            missing.append("\(voice.id).json")
        }
        return missing
    }
}
