# MeetMemento

A journaling app with AI-powered insights.

## Setup

### 1. Supabase Configuration

**⚠️ IMPORTANT:** Use local xcconfig override files for Supabase values. Do not commit real keys.

1. Copy the local override templates:
   ```bash
   cp MeetMemento/Config/Debug.local.xcconfig.template MeetMemento/Config/Debug.local.xcconfig
   cp MeetMemento/Config/Release.local.xcconfig.template MeetMemento/Config/Release.local.xcconfig
   ```

2. Open both local files and replace placeholders with your actual credentials:
   - Get your Supabase URL and anon key from: [Supabase Dashboard → Settings → API](https://app.supabase.com/project/_/settings/api)

3. `SUPABASE_URL` and `SUPABASE_ANON_KEY` are injected into `Info.plist` from xcconfig and read at runtime by `SupabaseService`.

4. **Never commit** `Debug.local.xcconfig` or `Release.local.xcconfig` (already ignored in `.gitignore`).

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
- Supabase values are loaded from local `*.local.xcconfig` files
- Use the `.template` files as references for required configuration keys

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
