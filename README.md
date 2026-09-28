# withMemento

A private journaling app with an on-device AI companion. Journal entries
stay on device — there are no accounts. Submitting a Report sends that
reply for verification. Ratings can be sent if you turn on Share quality
feedback (spec 042).

## Setup

No accounts are required. A fresh clone builds without API keys (verification
upload is a no-op until you add them).

To send volunteered chat feedback to the live evaluations project, copy
`withMemento/Config/Supabase.xcconfig.example` to
`withMemento/Config/Supabase.xcconfig` and fill the publishable anon key.
Never put a `service_role` key in the app or the repo.

Keep the `SUPABASE_URL` line exactly as the example writes it — the slashes are
composed through `$(SUPABASE_SLASH)` because xcconfig treats `//` as the start
of a comment, so a literal `https://host` is silently truncated to `https:`.

1. Open `withMemento.xcodeproj` in Xcode.
2. Select a device or simulator.
3. Build and run (⌘R).

The AI features use Apple's on-device Foundation Models, so they need a device
(or simulator) that supports Apple Intelligence; where the model is unavailable
the app degrades gracefully.

## Project Structure

```
withMemento/
├── Components/          # Reusable UI components
├── Models/              # Data models
├── Resources/           # Fonts, themes, configurations
├── Services/            # On-device services (storage, security, intelligence)
│   └── Intelligence/    # The single Foundation Models boundary + retrieval
├── ViewModels/          # Business logic
└── Views/               # SwiftUI views
```

## Features

- **Journal entries:** create, edit, and delete entries, stored **encrypted on device**.
- **AI chat:** converse with an on-device assistant that grounds its replies in
  your own entries (retrieval runs locally — nothing is uploaded).
- **Chat summary:** turn a conversation into a first-person journal entry.
- **Speech-to-text:** voice input for journaling and chat.

## Privacy & security

- Journal content is stored in encrypted local storage; there is no server copy of the journal.
- No accounts and no sign-in. Submitting a Report writes that question and answer to a verification database. If you opt in to Share quality feedback, volunteered ratings can also be sent.
- AI generation and journal retrieval run on device.

## Development

### Requirements
- Xcode **26+** (the on-device intelligence layer needs the Foundation Models SDK)
- iOS **26+**
- Swift 5 language mode (`SWIFT_VERSION = 5.0`) on the Swift 6 compiler.
  This is deliberate, not drift: a Release build currently emits ~44 warnings,
  most of them `this is an error in the Swift 6 language mode` (non-Sendable
  captures in `@Sendable` closures, non-Sendable stored properties on
  `Sendable`-conforming classes, and locking calls unavailable from async
  contexts). Moving to Swift 6 mode is a real concurrency-audit project, not a
  build-setting flip — do it on its own branch with its own test run.

### Testing
Online suite (matches merge CI — skips UITests and live FM generation):

```bash
CI_ONLINE=1 xcodebuild -scheme withMemento \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -skip-testing:withMementoUITests test
```

Device/eval (optional): run without `CI_ONLINE`, or dispatch
`.github/workflows/ios-device-eval.yml`. Live Foundation Models generation needs
a physical Apple Intelligence device.

### Branching and CI/CD
- Branch model: feature branches merge into `dev`, then `dev` is promoted into `main` by pull request.
- Merge workflows: `ios-build-online.yml`, `security.yml`, `spec-gates.yml`.
- Optional non-blocking: `ios-device-eval.yml` (on-device model / spikes / eval).
- Spec: [specs/025-ci-online-ios-build-gates.md](specs/025-ci-online-ios-build-gates.md) · runners: [docs/CI_RUNNERS.md](docs/CI_RUNNERS.md)
- Full policy: [docs/BRANCHING_AND_CI_POLICY.md](docs/BRANCHING_AND_CI_POLICY.md)
- Branch protection setup: [docs/BRANCH_PROTECTION_SETUP.md](docs/BRANCH_PROTECTION_SETUP.md)
- Quality gate rollout: [docs/QUALITY_GATE_ROLLOUT.md](docs/QUALITY_GATE_ROLLOUT.md)

## License

[Add your license here]
