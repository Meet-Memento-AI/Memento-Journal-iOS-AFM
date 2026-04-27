# MeetMemento

A journaling app with AI-powered insights.

## Setup

### 1. Supabase Configuration

**⚠️ IMPORTANT:** The Supabase configuration file is not included in version control for security reasons.

1. Copy the template file:
   ```bash
   cp MeetMemento/Resources/SupabaseConfig.swift.template MeetMemento/Resources/SupabaseConfig.swift
   ```

2. Open `SupabaseConfig.swift` and replace placeholders with your actual credentials:
   - Get your Supabase URL and anon key from: [Supabase Dashboard → Settings → API](https://app.supabase.com/project/_/settings/api)

3. **Never commit** `SupabaseConfig.swift` to version control (it's already in `.gitignore`)

### 2. Build & Run

1. Open `MeetMemento.xcodeproj` in Xcode
2. Select your target device/simulator
3. Build and run (⌘R)

## Project Structure

```
MeetMemento/
├── Components/        # Reusable UI components
├── Models/           # Data models
├── Resources/        # Fonts, themes, configurations
├── Services/         # API services, auth, etc.
├── ViewModels/       # Business logic
└── Views/            # SwiftUI views
```

## Features

- **Journal Entries:** Create, edit, and delete journal entries
- **AI Insights:** View themes and summaries from your entries
- **Authentication:** Secure sign-in with Apple
- **Speech-to-Text:** Voice input for journal entries

## Security

- Supabase credentials are stored locally and never committed to version control
- All API keys should be stored in `SupabaseConfig.swift` (local only)
- Use the `.template` file as a reference for required configuration

## Development

### Requirements
- Xcode 15.0+
- iOS 17.0+
- Swift 5.9+

### Testing
Run tests with ⌘U in Xcode.

### Branching and CI/CD
- Branch model: feature branches merge into dev, then dev is promoted into main by pull request.
- CI quality and security checks run on pull requests to dev and main.
- Pushes to dev trigger automated deployment to dev and staging environments.
- Full policy: [docs/BRANCHING_AND_CI_POLICY.md](docs/BRANCHING_AND_CI_POLICY.md)
- Branch protection setup: [docs/BRANCH_PROTECTION_SETUP.md](docs/BRANCH_PROTECTION_SETUP.md)
- Quality gate rollout: [docs/QUALITY_GATE_ROLLOUT.md](docs/QUALITY_GATE_ROLLOUT.md)

## License

[Add your license here]
