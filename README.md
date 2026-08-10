# MeetMemento

A private journaling app with an on-device AI companion. Everything runs
**on device** — there are no accounts and no backend, and your journal never
leaves the phone.

## Setup

No configuration, accounts, or API keys are required.

1. Open `MeetMemento.xcodeproj` in Xcode.
2. Select a device or simulator.
3. Build and run (⌘R).

The AI features use Apple's on-device Foundation Models, so they need a device
(or simulator) that supports Apple Intelligence; where the model is unavailable
the app degrades gracefully.

## Project Structure

```
MeetMemento/
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

- Journal content is stored in encrypted local storage; there is no server copy.
- No accounts, no sign-in, no third-party data processors.
- AI generation and journal retrieval run entirely on device.

## Development

### Requirements
- Xcode **26+** (the on-device intelligence layer needs the Foundation Models SDK)
- iOS **26+**
- Swift 6

### Testing
Run tests with ⌘U in Xcode, or:

```bash
xcodebuild -scheme MeetMemento \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -skip-testing:MeetMementoUITests test
```

### Branching and CI/CD
- Branch model: feature branches merge into `dev`, then `dev` is promoted into `main` by pull request.
- Merge CI focuses on **online-testable** gates: SDK-free spec/store checks, security scanning, and an iOS job centered on **build specifications** plus mockable unit tests — not live on-device Foundation Models generation (that stays local / optional).
- Plan: [specs/025-ci-online-ios-build-gates.md](specs/025-ci-online-ios-build-gates.md) · runners: [docs/CI_RUNNERS.md](docs/CI_RUNNERS.md)
- Full policy: [docs/BRANCHING_AND_CI_POLICY.md](docs/BRANCHING_AND_CI_POLICY.md)
- Branch protection setup: [docs/BRANCH_PROTECTION_SETUP.md](docs/BRANCH_PROTECTION_SETUP.md)
- Quality gate rollout: [docs/QUALITY_GATE_ROLLOUT.md](docs/QUALITY_GATE_ROLLOUT.md)

## License

[Add your license here]
