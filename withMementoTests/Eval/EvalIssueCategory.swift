import Foundation

/// Stable category tags for device-eval failures (T5). CI logs and
/// `scripts/eval/run_mac_eval.sh` reference these raw values when triaging
/// `xcresult` bundles — they are not XCTest runtime tags yet.
enum EvalIssueCategory: String, CaseIterable, Sendable {
    case deviceGate = "device_gate"
    case convoSim = "convo_sim"
    case chatEval = "chat_eval"
    case agentic = "agentic"
    case fmCLI = "fm_cli"
    case intelligenceService = "intelligence_service"
}
