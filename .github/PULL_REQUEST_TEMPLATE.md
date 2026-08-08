## Summary

<!-- What changed and why (1–3 sentences). -->

## Testing

- [ ] I added or updated tests for behavior changes (unit / UI / Edge Function helpers as applicable).
- [ ] `xcodebuild -scheme MeetMemento -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' test` (requires Xcode 26+ for the Foundation Models SDK; adjust name to a device you have via `xcodebuild -showdestinations -scheme MeetMemento`)
- [ ] `cd supabase/functions && deno check chat-feedback/index.ts generate-insights/index.ts && deno test --no-check --allow-read --allow-net --allow-env chat-feedback/lib_test.ts generate-insights/lib_test.ts _shared/rate_limit_test.ts _shared/auth_test.ts` (if an edge function changed)

## CI and Security

- [ ] This PR targets `dev` unless it is a release promotion PR from `dev` to `main`.
- [ ] If auth/OAuth configuration changed, I verified Supabase Site URL and Redirect URLs using the checklist in `README.md` (Setup -> Supabase Auth URL Configuration).
- [ ] SwiftLint passes in strict mode.
- [ ] Coverage gate passes.
- [ ] Security checks pass (CodeQL, dependency review, secret scanning).
