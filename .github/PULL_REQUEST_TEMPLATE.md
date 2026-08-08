## Summary

<!-- What changed and why (1–3 sentences). -->

## Testing

- [ ] I added or updated tests for behavior changes (unit / UI as applicable).
- [ ] `xcodebuild -scheme MeetMemento -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' test` (requires Xcode 26+ for the Foundation Models SDK; adjust name to a device you have via `xcodebuild -showdestinations -scheme MeetMemento`)

## CI and Security

- [ ] This PR targets `dev` unless it is a release promotion PR from `dev` to `main`.
- [ ] SwiftLint passes in strict mode.
- [ ] Coverage gate passes.
- [ ] Security checks pass (CodeQL, dependency review, secret scanning).
