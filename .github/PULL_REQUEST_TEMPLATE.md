## Summary

<!-- What changed and why (1–3 sentences). -->

## Testing

- [ ] I added or updated tests for behavior changes (unit / UI as applicable).
- [ ] Online suite: `CI_ONLINE=1 xcodebuild -scheme MeetMemento -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -skip-testing:MeetMementoUITests test` (requires Xcode 26+; adjust destination via `xcodebuild -showdestinations -scheme MeetMemento`)
- [ ] Device/eval changes (if any) were validated locally or via `ios-device-eval.yml` — not required to merge.

## CI and Security

- [ ] This PR targets `dev` unless it is a release promotion PR from `dev` to `main`.
- [ ] Online checks pass: **iOS build (online)**, Spec gates (2.0), dependency review, secret scanning.
- [ ] SwiftLint passes in strict mode on changed files.
- [ ] Coverage gate passes (online suite).
