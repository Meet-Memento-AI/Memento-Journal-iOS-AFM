// swift-tools-version: 5.10
import PackageDescription

// Vendored fork — see VENDORING.md. Deliberately has NO dependencies: the
// upstream `AudioCommon` target pulls `Hub` from `swift-transformers`
// (HuggingFace's hub client), which spec 030 R1 forbids shipping. The only
// symbol SupertonicTTS actually needed from it, `CoreMLComputeUnitsResolver`,
// is vendored as a single file instead.
//
// This is also the module boundary that makes CONSTITUTION rule 11 — "exactly
// one Swift module imports CoreML" — true structurally rather than by
// convention. The app target imports this; it does not import CoreML itself.
let package = Package(
    name: "SupertonicTTS",
    // iOS only — matches the app. A macOS platform was briefly declared so the
    // package could be built standalone on the host; that was a mistake (it made
    // tooling evaluate macOS builds of an iOS-only package, and MLMultiArray's
    // .int8 case is iOS 26 / macOS 26). Verify through the app build instead.
    platforms: [.iOS("26.0")],
    products: [
        .library(name: "SupertonicTTS", targets: ["SupertonicTTS"])
    ],
    targets: [
        .target(name: "SupertonicTTS")
    ]
)
